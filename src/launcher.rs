//! Touch-first iOS launcher.  Keep all launcher text ASCII: the game's
//! archive bitmap font intentionally only has the original Latin glyph set.
use crate::{assets::Assets, preferences::Preferences, ui::Ui};
use macroquad::prelude::*;
use serde::{Deserialize, Serialize};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum LauncherResult { Play, Quit }

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(default)]
pub struct LauncherSettings {
    pub fps_choice: usize, pub metal_hud: bool, pub aspect_choice: usize,
    pub gamepad_style: usize, pub language_choice: usize, pub touch_scale: usize,
}

impl Default for LauncherSettings {
    fn default() -> Self {
        Self { fps_choice: 1, metal_hud: false, aspect_choice: 0,
            gamepad_style: 0, language_choice: 0, touch_scale: 0 }
    }
}

impl LauncherSettings {
    pub fn load() -> Self {
        let path = crate::preferences::path("ios-launcher.json");
        let Ok(bytes) = std::fs::read(path) else { return Self::default(); };
        let Ok(settings) = serde_json::from_slice::<Self>(&bytes) else { return Self::default(); };
        (settings.fps_choice < 3 && settings.aspect_choice < 3 && settings.gamepad_style < 2
            && settings.language_choice < 2 && settings.touch_scale < 3)
            .then_some(settings)
            .unwrap_or_default()
    }

    pub fn save(&self) {
        let path = crate::preferences::path("ios-launcher.json");
        if let Some(parent) = path.parent() {
            let _ = std::fs::create_dir_all(parent);
        }
        if let Ok(bytes) = serde_json::to_vec_pretty(self) {
            let _ = std::fs::write(path, bytes);
        }
    }
}

fn tapped(r: Rect) -> bool {
    macroquad::input::touches().iter().any(|t|
        t.phase == TouchPhase::Started && r.contains(t.position))
        || (is_mouse_button_pressed(MouseButton::Left) && r.contains(Vec2::from(mouse_position())))
}

fn option<'a>(index: usize, values: &'a [&'a str]) -> &'a str { values[index % values.len()] }

pub async fn run_launcher(
    _assets: &mut Assets, ui: &Ui, _prefs: &mut Preferences, settings: &mut LauncherSettings,
) -> LauncherResult {
    loop {
        let w = screen_width();
        let h = screen_height();
        // UI coordinates are logical points on iOS; this stays comfortable on
        // iPhone and uses the available width on iPad without Retina over-scaling.
        let margin = (h * 0.035).clamp(14., 38.);
        let compact = w < h * 1.45;
        clear_background(Color::new(0.035, 0.025, 0.04, 1.));
        set_default_camera();
        gl_use_default_material();

        let content = Rect::new(margin, margin, w - margin * 2., h - margin * 2.);
        ui.panel(content);
        let title_h = (h * 0.15).clamp(64., 130.);
        ui.label("AMERICAN McGEE'S", content.x + margin, content.y + title_h * 0.32, title_h * 0.20, WHITE);
        ui.label("ALICE", content.x + margin, content.y + title_h * 0.72, title_h * 0.42, Color::new(0.95, 0.22, 0.23, 1.));
        ui.label("LOOKINGMETAL  |  iOS & macOS METAL EDITION", content.x + margin, content.y + title_h - 8., title_h * 0.16, Color::new(0.92, 0.76, 0.35, 1.));

        let footer_h = (h * 0.18).clamp(78., 144.);
        let list_top = content.y + title_h + margin * 0.35;
        let list_bottom = content.bottom() - footer_h - margin * 0.35;
        let gap = (h * 0.012).clamp(6., 14.);
        let row_h = ((list_bottom - list_top - gap * 5.) / 6.).max(42.);
        let rows = [
            ("FRAME RATE", option(settings.fps_choice, &["60 FPS", "120 FPS / PROMOTION", "30 FPS / SAVE POWER"])),
            ("METAL PERFORMANCE HUD", if settings.metal_hud { "ON" } else { "OFF" }),
            ("SCREEN FORMAT", option(settings.aspect_choice, &["FULL SCREEN", "16:9 WIDE", "4:3 CLASSIC"])),
            ("ON-SCREEN CONTROLS", option(settings.gamepad_style, &["TOUCH + CONTROLLER", "CONTROLLER ONLY"])),
            ("GAME LANGUAGE", option(settings.language_choice, &["ENGLISH / ORIGINAL", "RUSSIAN / SOFTCLUB"])),
            ("BUTTON SIZE", option(settings.touch_scale, &["LARGE 125%", "STANDARD 100%", "HUGE 150%"])),
        ];

        let mut change = None;
        for (i, (label, value)) in rows.iter().enumerate() {
            let y = list_top + i as f32 * (row_h + gap);
            let r = Rect::new(content.x + margin, y, content.w - margin * 2., row_h);
            let value_w = (r.w * if compact { 0.54 } else { 0.46 }).clamp(160., 560.);
            let value_r = Rect::new(r.right() - value_w, r.y, value_w, r.h);
            draw_rectangle(r.x, r.y, r.w, r.h, Color::new(0.08, 0.07, 0.08, 0.72));
            draw_rectangle_lines(r.x, r.y, r.w, r.h, 2., Color::new(0.55, 0.43, 0.25, 0.9));
            draw_rectangle(value_r.x, value_r.y, value_r.w, value_r.h, Color::new(0.42, 0.09, 0.10, 0.95));
            draw_rectangle_lines(value_r.x, value_r.y, value_r.w, value_r.h, 2., Color::new(0.98, 0.72, 0.30, 0.95));
            let font = (row_h * 0.28).clamp(14., 32.);
            ui.label(label, r.x + row_h * 0.32, r.y + row_h * 0.62, font, Color::new(0.95, 0.91, 0.80, 1.));
            ui.center(value, value_r, (row_h * 0.27).clamp(13., 30.), WHITE);
            if tapped(r) { change = Some(i); }
        }
        if let Some(i) = change {
            match i {
                0 => settings.fps_choice = (settings.fps_choice + 1) % 3,
                1 => settings.metal_hud = !settings.metal_hud,
                2 => settings.aspect_choice = (settings.aspect_choice + 1) % 3,
                3 => settings.gamepad_style = (settings.gamepad_style + 1) % 2,
                4 => settings.language_choice = (settings.language_choice + 1) % 2,
                5 => settings.touch_scale = (settings.touch_scale + 1) % 3,
                _ => unreachable!(),
            }
        }

        let play = Rect::new(content.x + margin, content.bottom() - footer_h + margin * 0.15,
            content.w - margin * 2., footer_h - margin * 0.3);
        draw_rectangle(play.x, play.y, play.w, play.h, Color::new(0.78, 0.10, 0.11, 0.98));
        draw_rectangle_lines(play.x, play.y, play.w, play.h, 3., Color::new(1., 0.82, 0.25, 1.));
        ui.center("PLAY", play, (play.h * 0.43).clamp(24., 52.), WHITE);
        if tapped(play) || is_key_pressed(KeyCode::Enter) || is_key_pressed(KeyCode::Space) {
            settings.save();
            return LauncherResult::Play;
        }
        if is_quit_requested() || is_key_pressed(KeyCode::Escape) { return LauncherResult::Quit; }
        next_frame().await;
    }
}
