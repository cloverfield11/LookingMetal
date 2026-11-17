//! Clean, modern mobile action-game touch controls (Brawl Stars / GTA mobile style).
use macroquad::prelude::*;
use std::collections::HashSet;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum TouchButton {
    A,     // Jump / Climb (Space)
    B,     // Alt Attack (Blade Throw / Mouse 2)
    X,     // Primary Attack (Blade Slash / Mouse 1)
    Y,     // Action / Interact / Use (Key E)
    Next,  // Next Toy / Weapon Switch (Wheel Down)
    Start, // Pause / Menu (+)
}

pub struct TouchGamepad {
    // Left Joystick (Locomotion)
    lstick_touch_id: Option<u64>,
    lstick_center: Vec2,
    lstick_current: Vec2,
    lstick_vector: Vec2,

    // Right Joystick (Camera Look - ONLY source of camera rotation)
    rstick_touch_id: Option<u64>,
    rstick_center: Vec2,
    rstick_current: Vec2,
    rstick_vector: Vec2,

    // Buttons state
    held_buttons: HashSet<TouchButton>,
    pressed_buttons: HashSet<TouchButton>,
    button_touches: Vec<(u64, TouchButton)>,

    // Scale multiplier
    pub scale_mult: f32,
    pub enabled: bool,
}

impl Default for TouchGamepad {
    fn default() -> Self {
        Self {
            lstick_touch_id: None,
            lstick_center: Vec2::ZERO,
            lstick_current: Vec2::ZERO,
            lstick_vector: Vec2::ZERO,

            rstick_touch_id: None,
            rstick_center: Vec2::ZERO,
            rstick_current: Vec2::ZERO,
            rstick_vector: Vec2::ZERO,

            held_buttons: HashSet::new(),
            pressed_buttons: HashSet::new(),
            button_touches: Vec::new(),

            scale_mult: 1.0,
            #[cfg(target_os = "ios")]
            enabled: true,
            #[cfg(not(target_os = "ios"))]
            enabled: false,
        }
    }
}

impl TouchGamepad {
    pub fn scale(&self, h: f32) -> f32 {
        (h / 390.0).clamp(0.75, 1.6) * self.scale_mult
    }

    pub fn update(&mut self) {
        if !self.enabled {
            self.held_buttons.clear();
            self.pressed_buttons.clear();
            self.button_touches.clear();
            self.lstick_touch_id = None;
            self.lstick_vector = Vec2::ZERO;
            self.rstick_touch_id = None;
            self.rstick_vector = Vec2::ZERO;
            return;
        }

        let w = screen_width();
        let h = screen_height();
        let s = self.scale(h);
        let stick_radius = 50.0 * s;

        let touches = macroquad::input::touches();
        if touches.is_empty() {
            self.lstick_touch_id = None;
            self.lstick_vector = Vec2::ZERO;
            self.rstick_touch_id = None;
            self.rstick_vector = Vec2::ZERO;
            self.held_buttons.clear();
            self.pressed_buttons.clear();
            self.button_touches.clear();
            return;
        }

        self.pressed_buttons.clear();
        let active_ids: HashSet<u64> = touches.iter().map(|t| t.id).collect();

        // Release buttons whose touches are gone
        self.button_touches.retain(|(id, _)| active_ids.contains(id));
        self.held_buttons.clear();
        for (_, btn) in &self.button_touches {
            self.held_buttons.insert(*btn);
        }

        // Release sticks whose touches are gone
        if let Some(id) = self.lstick_touch_id {
            if !active_ids.contains(&id) {
                self.lstick_touch_id = None;
                self.lstick_vector = Vec2::ZERO;
            }
        }
        if let Some(id) = self.rstick_touch_id {
            if !active_ids.contains(&id) {
                self.rstick_touch_id = None;
                self.rstick_vector = Vec2::ZERO;
            }
        }

        let buttons = self.button_layouts(w, h, s);
        let default_rcenter = vec2(w - 230.0 * s, h - 85.0 * s);

        for t in &touches {
            let pos = t.position;

            // 1. Existing Left Stick touch
            if self.lstick_touch_id == Some(t.id) {
                match t.phase {
                    TouchPhase::Moved | TouchPhase::Stationary => {
                        self.lstick_current = pos;
                        let diff = pos - self.lstick_center;
                        let dist = diff.length();
                        if dist > 0.0 {
                            let norm = diff / dist;
                            let clamped = dist.min(stick_radius);
                            self.lstick_vector = norm * (clamped / stick_radius);
                        } else {
                            self.lstick_vector = Vec2::ZERO;
                        }
                    }
                    TouchPhase::Ended | TouchPhase::Cancelled => {
                        self.lstick_touch_id = None;
                        self.lstick_vector = Vec2::ZERO;
                    }
                    _ => {}
                }
                continue;
            }

            // 2. Existing Right Stick touch
            if self.rstick_touch_id == Some(t.id) {
                match t.phase {
                    TouchPhase::Moved | TouchPhase::Stationary => {
                        self.rstick_current = pos;
                        let diff = pos - self.rstick_center;
                        let dist = diff.length();
                        if dist > 0.0 {
                            let norm = diff / dist;
                            let clamped = dist.min(stick_radius);
                            self.rstick_vector = norm * (clamped / stick_radius);
                        } else {
                            self.rstick_vector = Vec2::ZERO;
                        }
                    }
                    TouchPhase::Ended | TouchPhase::Cancelled => {
                        self.rstick_touch_id = None;
                        self.rstick_vector = Vec2::ZERO;
                    }
                    _ => {}
                }
                continue;
            }

            // 3. Existing button touch
            if self.button_touches.iter().any(|(id, _)| *id == t.id) {
                if t.phase == TouchPhase::Ended || t.phase == TouchPhase::Cancelled {
                    self.button_touches.retain(|(id, _)| *id != t.id);
                    self.held_buttons.clear();
                    for (_, btn) in &self.button_touches {
                        self.held_buttons.insert(*btn);
                    }
                }
                continue;
            }

            // 4. New touch: Check button hits (generous hit padding)
            let mut hit_btn = None;
            for (btn, center, radius) in &buttons {
                if pos.distance(*center) <= (*radius + 12.0 * s) {
                    hit_btn = Some(*btn);
                    break;
                }
            }

            if let Some(btn) = hit_btn {
                if t.phase == TouchPhase::Started || t.phase == TouchPhase::Moved || t.phase == TouchPhase::Stationary {
                    self.button_touches.push((t.id, btn));
                    self.pressed_buttons.insert(btn);
                    self.held_buttons.insert(btn);
                }
                continue;
            }

            // 5. New touch on Left half: Left Joystick (Floating center under thumb)
            if pos.x < w * 0.40 && pos.y > 60.0 * s {
                if (t.phase == TouchPhase::Started || t.phase == TouchPhase::Moved) && self.lstick_touch_id.is_none() {
                    self.lstick_touch_id = Some(t.id);
                    self.lstick_center = pos;
                    self.lstick_current = pos;
                    self.lstick_vector = Vec2::ZERO;
                }
                continue;
            }

            // 6. New touch on Right Stick zone ONLY (no free swipe on empty glass!)
            let r_ref_center = if self.rstick_touch_id.is_some() { self.rstick_center } else { default_rcenter };
            let r_dist = pos.distance(r_ref_center);
            if r_dist <= (stick_radius * 1.5) || (pos.x >= w * 0.46 && pos.x <= w * 0.76 && pos.y >= h * 0.45) {
                if (t.phase == TouchPhase::Started || t.phase == TouchPhase::Moved) && self.rstick_touch_id.is_none() {
                    self.rstick_touch_id = Some(t.id);
                    self.rstick_center = if r_dist <= stick_radius { default_rcenter } else { pos };
                    self.rstick_current = pos;
                    let diff = pos - self.rstick_center;
                    let dist = diff.length();
                    if dist > 0.0 {
                        let norm = diff / dist;
                        let clamped = dist.min(stick_radius);
                        self.rstick_vector = norm * (clamped / stick_radius);
                    } else {
                        self.rstick_vector = Vec2::ZERO;
                    }
                }
                continue;
            }

            // All other screen touches on empty glass are completely ignored.
        }
    }

    fn button_layouts(&self, w: f32, h: f32, s: f32) -> Vec<(TouchButton, Vec2, f32)> {
        let mut btns = Vec::new();

        // 1. ABXY Diamond (Bottom-Right corner, comfortably away from mana bar)
        let cx = w - 100.0 * s;
        let cy = h - 85.0 * s;
        let spacing = 38.0 * s;
        let face_r = 21.0 * s;

        // A (bottom, emerald green): Jump / Climb
        btns.push((TouchButton::A, vec2(cx, cy + spacing), face_r));
        // X (left, alice ruby red): Primary Attack (Vorpal Blade slash)
        btns.push((TouchButton::X, vec2(cx - spacing, cy), face_r));
        // B (right, sapphire blue): Alt Attack (Blade throw)
        btns.push((TouchButton::B, vec2(cx + spacing, cy), face_r));
        // Y (top, amber gold): Action / Interact (Key E)
        btns.push((TouchButton::Y, vec2(cx, cy - spacing), face_r));

        // 2. NEXT Toy / Weapon Switch (Positioned above ABXY cluster)
        let next_r = 20.0 * s;
        btns.push((TouchButton::Next, vec2(cx, cy - spacing * 1.85), next_r));

        // 3. Pause / Menu Button (+) (Top-right corner, comfortably inside screen)
        let menu_r = 19.0 * s;
        btns.push((TouchButton::Start, vec2(w - 42.0 * s, 34.0 * s), menu_r));

        btns
    }

    /// Analog movement vector: x = strafe (-1 left, +1 right), y = forward (+1 forward, -1 back)
    pub fn movement(&self) -> Vec2 {
        if !self.enabled {
            return Vec2::ZERO;
        }
        let len = self.lstick_vector.length();
        if len < 0.12 {
            return Vec2::ZERO;
        }
        vec2(self.lstick_vector.x, -self.lstick_vector.y)
    }

    /// Whether Alice should sprint: only when the stick is pushed firmly past 72%
    pub fn is_running(&self) -> bool {
        self.enabled && self.lstick_vector.length() >= 0.72
    }

    /// Apply look rotation to yaw and pitch. ONLY driven by the Right Stick!
    pub fn apply_look(&self, yaw: &mut f32, pitch: &mut f32) {
        if !self.enabled {
            return;
        }
        let dt = get_frame_time().clamp(0.001, 0.05);

        // Right Stick analog rotation with smooth responsive quadratic curve
        if self.rstick_vector != Vec2::ZERO {
            let v = self.rstick_vector;
            let len = v.length();
            let curved_speed = len * len * 2.8; // Quadratic curve: fine aim + quick turnaround
            let norm = v / len;
            *yaw = (*yaw - norm.x * curved_speed * dt).rem_euclid(std::f32::consts::TAU);
            *pitch = (*pitch - norm.y * curved_speed * dt).clamp(-1.5, 1.5);
        }
    }

    pub fn is_held(&self, key: KeyCode) -> bool {
        if !self.enabled {
            return false;
        }
        match key {
            KeyCode::Space => self.held_buttons.contains(&TouchButton::A),
            KeyCode::E => self.held_buttons.contains(&TouchButton::Y),
            KeyCode::Escape => self.held_buttons.contains(&TouchButton::Start),
            _ => false,
        }
    }

    pub fn is_pressed(&self, key: KeyCode) -> bool {
        if !self.enabled {
            return false;
        }
        match key {
            KeyCode::Space => self.pressed_buttons.contains(&TouchButton::A),
            KeyCode::E => self.pressed_buttons.contains(&TouchButton::Y),
            KeyCode::Escape => self.pressed_buttons.contains(&TouchButton::Start),
            _ => false,
        }
    }

    pub fn is_action_held(&self, original: &str) -> bool {
        if !self.enabled {
            return false;
        }
        match original {
            "Mouse 1" | "Primary attack" => self.held_buttons.contains(&TouchButton::X),
            "Mouse 2" | "Alternate attack" => self.held_buttons.contains(&TouchButton::B),
            "Space" | "Jump / climb" => self.held_buttons.contains(&TouchButton::A),
            "E" | "Interact" => self.held_buttons.contains(&TouchButton::Y),
            "Escape" | "Pause" => self.held_buttons.contains(&TouchButton::Start),
            _ => false,
        }
    }

    pub fn is_action_pressed(&self, original: &str) -> bool {
        if !self.enabled {
            return false;
        }
        match original {
            "Mouse 1" | "Primary attack" => self.pressed_buttons.contains(&TouchButton::X),
            "Mouse 2" | "Alternate attack" => self.pressed_buttons.contains(&TouchButton::B),
            "Wheel Down" | "Next toy" => self.pressed_buttons.contains(&TouchButton::Next),
            "Space" | "Jump / climb" => self.pressed_buttons.contains(&TouchButton::A),
            "E" | "Interact" => self.pressed_buttons.contains(&TouchButton::Y),
            "Escape" | "Pause" => self.pressed_buttons.contains(&TouchButton::Start),
            _ => false,
        }
    }

    pub fn draw(&self, ui: &crate::ui::Ui) {
        if !self.enabled {
            return;
        }

        set_default_camera();
        gl_use_default_material();

        let w = screen_width();
        let h = screen_height();
        let s = self.scale(h);
        let stick_radius = 50.0 * s;
        let knob_radius = 24.0 * s;

        // ==========================================
        // 1. Left Stick (Locomotion / Movement)
        // ==========================================
        let (lcenter, lknob) = if self.lstick_touch_id.is_some() {
            (self.lstick_center, self.lstick_center + self.lstick_vector * stick_radius)
        } else {
            let def = vec2(110.0 * s, h - 85.0 * s);
            (def, def)
        };

        // Dark glass base with double ring
        draw_circle(lcenter.x, lcenter.y, stick_radius, Color::new(0.02, 0.02, 0.04, 0.35));
        draw_circle_lines(lcenter.x, lcenter.y, stick_radius, 2.0 * s, Color::new(1.0, 1.0, 1.0, 0.35));
        draw_circle_lines(lcenter.x, lcenter.y, stick_radius * 0.5, 1.0 * s, Color::new(1.0, 1.0, 1.0, 0.15));

        // Direction guide line
        if self.lstick_vector.length_squared() > 0.01 {
            draw_line(lcenter.x, lcenter.y, lknob.x, lknob.y, 2.0 * s, Color::new(1.0, 1.0, 1.0, 0.60));
        }

        // 3D Shaded Knob
        draw_circle(lknob.x, lknob.y, knob_radius, Color::new(0.85, 0.88, 0.92, 0.70));
        draw_circle_lines(lknob.x, lknob.y, knob_radius, 2.0 * s, Color::new(1.0, 1.0, 1.0, 0.95));
        draw_circle_lines(lknob.x, lknob.y, knob_radius * 0.45, 1.5 * s, Color::new(0.2, 0.2, 0.2, 0.35));

        let l_rect = Rect::new(lknob.x - knob_radius, lknob.y - knob_radius, knob_radius * 2.0, knob_radius * 2.0);
        ui.center("MOVE", l_rect, 10.0 * s, Color::new(0.12, 0.12, 0.15, 0.95));

        // ==========================================
        // 2. Right Stick (Camera Look)
        // ==========================================
        let default_rcenter = vec2(w - 230.0 * s, h - 85.0 * s);
        let (rcenter, rknob) = if self.rstick_touch_id.is_some() {
            (self.rstick_center, self.rstick_center + self.rstick_vector * stick_radius)
        } else {
            (default_rcenter, default_rcenter)
        };

        // Dark glass base with double ring
        draw_circle(rcenter.x, rcenter.y, stick_radius, Color::new(0.02, 0.02, 0.04, 0.35));
        draw_circle_lines(rcenter.x, rcenter.y, stick_radius, 2.0 * s, Color::new(1.0, 1.0, 1.0, 0.35));
        draw_circle_lines(rcenter.x, rcenter.y, stick_radius * 0.5, 1.0 * s, Color::new(1.0, 1.0, 1.0, 0.15));

        // Direction guide line
        if self.rstick_vector.length_squared() > 0.01 {
            draw_line(rcenter.x, rcenter.y, rknob.x, rknob.y, 2.0 * s, Color::new(1.0, 1.0, 1.0, 0.60));
        }

        // 3D Shaded Knob
        draw_circle(rknob.x, rknob.y, knob_radius, Color::new(0.85, 0.88, 0.92, 0.70));
        draw_circle_lines(rknob.x, rknob.y, knob_radius, 2.0 * s, Color::new(1.0, 1.0, 1.0, 0.95));
        draw_circle_lines(rknob.x, rknob.y, knob_radius * 0.45, 1.5 * s, Color::new(0.2, 0.2, 0.2, 0.35));

        let r_rect = Rect::new(rknob.x - knob_radius, rknob.y - knob_radius, knob_radius * 2.0, knob_radius * 2.0);
        ui.center("LOOK", r_rect, 10.0 * s, Color::new(0.12, 0.12, 0.15, 0.95));

        // ==========================================
        // 3. Action Buttons (Brawl Stars / GTA Mobile Style)
        // ==========================================
        let buttons = self.button_layouts(w, h, s);
        for (btn, center, radius) in buttons {
            let is_held = self.held_buttons.contains(&btn);

            let (accent_color, fill_color, label) = match btn {
                TouchButton::A => (
                    Color::new(0.25, 0.95, 0.45, 0.95),
                    Color::new(0.15, 0.85, 0.35, 0.90),
                    "A",
                ),
                TouchButton::X => (
                    Color::new(0.95, 0.25, 0.25, 0.95),
                    Color::new(0.88, 0.15, 0.18, 0.95),
                    "X",
                ),
                TouchButton::B => (
                    Color::new(0.30, 0.60, 1.0, 0.95),
                    Color::new(0.20, 0.45, 0.92, 0.95),
                    "B",
                ),
                TouchButton::Y => (
                    Color::new(1.0, 0.82, 0.25, 0.95),
                    Color::new(0.92, 0.70, 0.15, 0.95),
                    "Y",
                ),
                TouchButton::Next => (
                    Color::new(0.80, 0.45, 1.0, 0.95),
                    Color::new(0.68, 0.28, 0.92, 0.95),
                    "NEXT",
                ),
                TouchButton::Start => (
                    Color::new(0.90, 0.92, 0.96, 0.90),
                    Color::new(0.80, 0.82, 0.88, 0.90),
                    "+",
                ),
            };

            let bg_color = if is_held {
                fill_color
            } else {
                Color::new(0.04, 0.03, 0.06, 0.62)
            };

            let border_color = if is_held {
                WHITE
            } else {
                accent_color
            };

            // Soft drop shadow
            draw_circle(center.x + 1.5 * s, center.y + 1.5 * s, radius, Color::new(0.0, 0.0, 0.0, 0.35));

            // Main body
            draw_circle(center.x, center.y, radius, bg_color);
            draw_circle_lines(center.x, center.y, radius, 2.0 * s, border_color);

            // Subtle inner ring for tactical depth
            if !is_held {
                draw_circle_lines(center.x, center.y, radius * 0.78, 1.0 * s, Color::new(border_color.r, border_color.g, border_color.b, 0.30));
            }

            let btn_rect = Rect::new(center.x - radius, center.y - radius, radius * 2.0, radius * 2.0);
            let font_size = if label == "NEXT" {
                11.0 * s
            } else if label == "+" {
                18.0 * s
            } else {
                16.0 * s
            };

            ui.center(label, btn_rect, font_size, WHITE);
        }
    }
}
