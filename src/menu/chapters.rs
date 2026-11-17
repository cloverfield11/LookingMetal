use super::*;
use crate::{
    campaign,
    chapters::{Chapters, Hit},
};

pub enum ChapterChoice {
    Begin(campaign::LevelChoice),
    Back,
    Quit,
}

impl Menu {
    /// The same chapter navigation as the in-game overlay, over the original menu art.
    pub async fn choose_chapter(
        &mut self,
        maps: &[String],
        current: usize,
        entry: Option<&str>,
        difficulty: &mut Difficulty,
        prefs: &Preferences,
        audio: &mut audio::Audio,
        input: &mut crate::input::Input,
    ) -> ChapterChoice {
        let mut choices = campaign::level_choices(maps);
        self.localize_choices(&mut choices, maps);
        let mut chapters = Chapters::default();
        chapters.open(
            campaign::choice_position(&choices, current, entry),
            choices.len(),
        );
        show_mouse(false);
        loop {
            let focused = crate::look::window_focused();
            input.update(prefs, focused);
            audio.update(0., Vec3::ZERO, 0., true, true);
            let sw = screen_width();
            let sh = screen_height();
            if self.touchpad_cursor == Vec2::ZERO {
                self.touchpad_cursor = vec2(sw * 0.5, sh * 0.5);
            }
            let touches = macroquad::input::touches();
            let mut touch_clicked = false;
            if !touches.is_empty() {
                if let Some(t) = touches.iter().find(|t| t.phase == TouchPhase::Moved) {
                    let delta = t.position - self.touchpad_last_pos;
                    self.touchpad_last_pos = t.position;
                    self.touchpad_dragged += delta.length();
                    self.touchpad_cursor += delta * 1.25;
                    self.touchpad_cursor.x = self.touchpad_cursor.x.clamp(0.0, sw);
                    self.touchpad_cursor.y = self.touchpad_cursor.y.clamp(0.0, sh);
                } else if let Some(t) = touches.iter().find(|t| t.phase == TouchPhase::Started) {
                    self.touchpad_last_pos = t.position;
                    self.touchpad_dragged = 0.0;
                } else if let Some(t) = touches.iter().find(|t| t.phase == TouchPhase::Ended) {
                    if self.touchpad_dragged < 15.0 {
                        self.touchpad_cursor = t.position;
                        touch_clicked = true;
                    }
                }
            }
            let canvas = crate::ui::Canvas::new(sw, sh);
            let hit = if touch_clicked {
                chapters.click(canvas.pointer(self.touchpad_cursor), get_time(), choices.len())
            } else {
                chapters.update(input, choices.len(), difficulty)
            };
            let result = if is_quit_requested() {
                Some(ChapterChoice::Quit)
            } else if input.ui(KeyCode::Escape) || input.ui(KeyCode::Tab) || hit == Some(Hit::Back)
            {
                Some(ChapterChoice::Back)
            } else if !choices.is_empty() && (input.ui(KeyCode::Enter) || hit == Some(Hit::Begin)) {
                Some(ChapterChoice::Begin(choices.remove(chapters.selected)))
            } else {
                None
            };
            if let Some(result) = result {
                input.suppress();
                show_mouse(true);
                next_frame().await;
                return result;
            }
            self.backdrop();
            chapters.draw(
                &self.ui,
                &choices,
                maps,
                *difficulty,
                focused,
                input.using_pad,
                &self.chapter_labels,
            );
            if focused {
                self.ui.cursor_at(self.touchpad_cursor);
            }
            next_frame().await;
        }
    }
}
