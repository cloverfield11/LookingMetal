//! Native Apple UIKit Main Menu for iOS
use std::ffi::CString;
use std::os::raw::{c_char, c_float, c_int, c_void};
use macroquad::color::Color;
use macroquad::window::{clear_background, next_frame};
use glam::Vec3;
use crate::assets::Assets;
use crate::campaign::level_title;
use crate::menu::save_screen::timestamp;
use crate::Options;
use crate::powerups::Difficulty;
use crate::preferences::Preferences;
use crate::save::{Slot, Store};
use crate::audio::Audio;
use crate::viewer::start::Start;

#[repr(C)]
#[derive(Copy, Clone, Debug)]
pub struct AliceMenuResult {
    pub action: c_int,
    pub difficulty: c_int,
    pub save_slot: c_int,
    pub chapter_idx: c_int,
    pub sound_vol: c_float,
    pub music_vol: c_float,
    pub voice_vol: c_float,
    pub look_sens: c_float,
    pub invert_y: c_int,
}

#[repr(C)]
pub struct AliceSaveSlotInfo {
    pub slot_idx: c_int,
    pub slot_title: *const c_char,
    pub chapter_name: *const c_char,
    pub save_date: *const c_char,
    pub is_empty: c_int,
}

#[repr(C)]
pub struct AliceChapterInfo {
    pub chapter_idx: c_int,
    pub title: *const c_char,
    pub map_name: *const c_char,
}

extern "C" {
    fn AliceNativeMenu_Show(
        root_vc_ptr: *mut c_void,
        slots: *const AliceSaveSlotInfo,
        slot_count: c_int,
        chapters: *const AliceChapterInfo,
        chapter_count: c_int,
        sound_vol: c_float,
        music_vol: c_float,
        voice_vol: c_float,
        look_sens: c_float,
        invert_y: c_int,
    );
    fn AliceNativeMenu_HasAction() -> c_int;
    fn AliceNativeMenu_GetResult() -> AliceMenuResult;
    #[allow(dead_code)]
    fn AliceNativeMenu_Dismiss();
}

pub async fn choose(
    _assets: &mut Assets,
    options: &mut Options,
    preferences: &mut Preferences,
    audio: &mut Audio,
    store: &Store,
    maps: &[String],
) -> Start {
    // 1. Prepare save slots data
    struct SlotData {
        title: CString,
        chapter: CString,
        date: CString,
        is_empty: bool,
    }

    let mut slots_data = Vec::with_capacity(Slot::ALL.len());
    for slot in Slot::ALL {
        let title_str = match slot {
            Slot::One => "Слот 1",
            Slot::Two => "Слот 2",
            Slot::Three => "Слот 3",
            Slot::Four => "Слот 4",
            Slot::Quick => "Быстрое сохранение (Quick)",
            Slot::Auto => "Автосохранение (Auto)",
        };
        let title = CString::new(title_str).unwrap();

        match store.read(slot) {
            Ok(loaded) => {
                let lvl = loaded.game.level();
                let ch_str = lvl.map_or("Неизвестно", |l| level_title(&l.map));
                let chapter = CString::new(ch_str).unwrap();
                let dt_str = timestamp(loaded.saved_at);
                let date = CString::new(dt_str).unwrap();
                slots_data.push(SlotData {
                    title,
                    chapter,
                    date,
                    is_empty: false,
                });
            }
            Err(_) => {
                let chapter = CString::new("Пусто").unwrap();
                let date = CString::new("").unwrap();
                slots_data.push(SlotData {
                    title,
                    chapter,
                    date,
                    is_empty: true,
                });
            }
        }
    }

    let c_slots: Vec<AliceSaveSlotInfo> = slots_data
        .iter()
        .enumerate()
        .map(|(idx, s)| AliceSaveSlotInfo {
            slot_idx: idx as c_int,
            slot_title: s.title.as_ptr(),
            chapter_name: s.chapter.as_ptr(),
            save_date: s.date.as_ptr(),
            is_empty: if s.is_empty { 1 } else { 0 },
        })
        .collect();

    // 2. Prepare chapters list
    struct ChapterData {
        title: CString,
        map_name: CString,
    }

    let mut chapters_data = Vec::with_capacity(maps.len());
    for map in maps {
        let title_str = level_title(map);
        chapters_data.push(ChapterData {
            title: CString::new(title_str).unwrap(),
            map_name: CString::new(map.as_str()).unwrap(),
        });
    }

    let c_chapters: Vec<AliceChapterInfo> = chapters_data
        .iter()
        .enumerate()
        .map(|(idx, c)| AliceChapterInfo {
            chapter_idx: idx as c_int,
            title: c.title.as_ptr(),
            map_name: c.map_name.as_ptr(),
        })
        .collect();

    // 3. Show UIKit Menu
    unsafe {
        AliceNativeMenu_Show(
            std::ptr::null_mut(),
            c_slots.as_ptr(),
            c_slots.len() as c_int,
            c_chapters.as_ptr(),
            c_chapters.len() as c_int,
            audio.settings.effects,
            audio.settings.music,
            audio.settings.effects,
            preferences.sensitivity,
            if preferences.invert_mouse { 1 } else { 0 },
        );
    }

    // 4. Render loop while UIKit menu is open
    while unsafe { AliceNativeMenu_HasAction() } == 0 {
        clear_background(Color::new(0.02, 0.02, 0.04, 1.0));
        audio.update(0., Vec3::ZERO, 0., true, true);
        next_frame().await;
    }

    let res = unsafe { AliceNativeMenu_GetResult() };

    // Apply settings changes
    audio.settings.effects = res.sound_vol.clamp(0.0, 1.0);
    audio.settings.music = res.music_vol.clamp(0.0, 1.0);
    preferences.sensitivity = res.look_sens;
    preferences.invert_mouse = res.invert_y != 0;
    preferences.invert_pad = res.invert_y != 0;

    // Small delay to let the UIKit fade-out animation play smoothly
    for _ in 0..12 {
        clear_background(Color::new(0.02, 0.02, 0.04, 1.0));
        audio.update(0., Vec3::ZERO, 0., true, true);
        next_frame().await;
    }

    match res.action {
        1 => {
            // New Game
            options.map = "gvillage".into();
            options.entry = None;
            options.difficulty = match res.difficulty {
                0 => Difficulty::Easy,
                1 => Difficulty::Normal,
                2 => Difficulty::Nightmare,
                _ => Difficulty::Normal,
            };
            options.new_game = true;
            Start::NewGame
        }
        2 => {
            // Load Game
            let slot_idx = (res.save_slot as usize).min(Slot::ALL.len() - 1);
            let slot = Slot::ALL[slot_idx];
            match store.read(slot) {
                Ok(loaded) => Start::Load(Box::new(loaded)),
                Err(_) => {
                    options.map = "gvillage".into();
                    options.entry = None;
                    options.difficulty = Difficulty::Normal;
                    options.new_game = true;
                    Start::NewGame
                }
            }
        }
        3 => {
            // Chapters
            let ch_idx = (res.chapter_idx as usize).min(maps.len().saturating_sub(1));
            options.map = maps[ch_idx].clone();
            options.entry = None;
            options.difficulty = match res.difficulty {
                0 => Difficulty::Easy,
                1 => Difficulty::Normal,
                2 => Difficulty::Nightmare,
                _ => Difficulty::Normal,
            };
            options.new_game = true;
            Start::Chapter
        }
        5 => Start::Quit,
        _ => Start::Quit,
    }
}
