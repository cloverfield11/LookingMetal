//! Full virtual Nintendo Switch / Xbox Controller for iOS touch screen.
use macroquad::prelude::*;
use std::collections::HashSet;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum TouchButton {
    // Face buttons (Xbox Diamond)
    A, // Jump (Space)
    B, // Alt Attack (Mouse 2)
    X, // Primary Attack (Mouse 1)
    Y, // Interact / Action (E)
    // Shoulders
    LB, // Run toggle (Shift)
    LT, // Alt Attack (Mouse 2)
    RB, // Next weapon
    RT, // Primary Attack (Mouse 1)
    // D-Pad
    DpadLeft,
    DpadRight,
    DpadUp,
    DpadDown,
    // System buttons
    Start,  // Menu / Pause (+)
    Select, // Cheshire Cat Hint (-)
}

pub struct TouchGamepad {
    // Left Joystick (Movement)
    lstick_touch_id: Option<u64>,
    lstick_center: Vec2,
    lstick_current: Vec2,
    lstick_vector: Vec2,

    // Right Joystick (Camera Look)
    rstick_touch_id: Option<u64>,
    rstick_center: Vec2,
    rstick_current: Vec2,
    rstick_vector: Vec2,

    // Swipe look (fallback right-half swipe)
    look_touch_id: Option<u64>,
    look_last_pos: Vec2,
    look_delta: Vec2,

    // Buttons state
    held_buttons: HashSet<TouchButton>,
    pressed_buttons: HashSet<TouchButton>,
    button_touches: Vec<(u64, TouchButton)>,

    // Run toggle
    pub run_toggled: bool,

    // User scale multiplier (from launcher: 1.0, 1.25, 1.5)
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

            look_touch_id: None,
            look_last_pos: Vec2::ZERO,
            look_delta: Vec2::ZERO,

            held_buttons: HashSet::new(),
            pressed_buttons: HashSet::new(),
            button_touches: Vec::new(),

            run_toggled: true, // Default to running on mobile
            scale_mult: 1.25,  // Large comfortable size by default

            #[cfg(target_os = "ios")]
            enabled: true,
            #[cfg(not(target_os = "ios"))]
            enabled: true,
        }
    }
}

impl TouchGamepad {
    #[inline]
    pub fn scale(&self, h: f32) -> f32 {
        (h / 390.0).clamp(1.0, 3.5) * self.scale_mult
    }

    pub fn update(&mut self) {
        self.pressed_buttons.clear();
        self.look_delta = Vec2::ZERO;

        let touches = macroquad::input::touches();
        if touches.is_empty() {
            self.lstick_touch_id = None;
            self.lstick_vector = Vec2::ZERO;
            self.rstick_touch_id = None;
            self.rstick_vector = Vec2::ZERO;
            self.look_touch_id = None;
            self.held_buttons.clear();
            self.button_touches.clear();
            return;
        }

        let w = screen_width();
        let h = screen_height();
        let s = self.scale(h);
        let stick_radius = 65.0 * s;

        let mut active_ids = HashSet::new();
        for t in &touches {
            active_ids.insert(t.id);
        }

        // Clean up released button touches
        self.button_touches.retain(|(id, _)| active_ids.contains(id));
        self.held_buttons.clear();
        for (_, btn) in &self.button_touches {
            self.held_buttons.insert(*btn);
        }

        // Clean up released stick & look touches
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
        if let Some(id) = self.look_touch_id {
            if !active_ids.contains(&id) {
                self.look_touch_id = None;
            }
        }

        let buttons = self.button_layouts(w, h, s);
        let default_rcenter = vec2(w - 230.0 * s, h - 95.0 * s);

        for t in &touches {
            let pos = t.position;

            // A. If this touch already owns the Left Stick:
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

            // B. If this touch already owns the Right Stick:
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

            // C. If this touch already owns Free Swipe Look:
            if self.look_touch_id == Some(t.id) {
                match t.phase {
                    TouchPhase::Moved => {
                        self.look_delta += pos - self.look_last_pos;
                        self.look_last_pos = pos;
                    }
                    TouchPhase::Stationary => {
                        self.look_last_pos = pos;
                    }
                    TouchPhase::Ended | TouchPhase::Cancelled => {
                        self.look_touch_id = None;
                    }
                    _ => {}
                }
                continue;
            }

            // D. If this touch already owns a button:
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

            // E. New touch: Check button hits
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

                    if btn == TouchButton::LB {
                        self.run_toggled = !self.run_toggled;
                    }
                }
                continue;
            }

            // F. New touch on Left half: Left Joystick (floating / dynamic center)
            if pos.x < w * 0.45 && pos.y > 60.0 * s {
                if (t.phase == TouchPhase::Started || t.phase == TouchPhase::Moved) && self.lstick_touch_id.is_none() {
                    self.lstick_touch_id = Some(t.id);
                    self.lstick_center = pos;
                    self.lstick_current = pos;
                    self.lstick_vector = Vec2::ZERO;
                }
                continue;
            }

            // G. New touch on Right Stick zone
            let r_ref_center = if self.rstick_touch_id.is_some() { self.rstick_center } else { default_rcenter };
            let r_dist = pos.distance(r_ref_center);
            if r_dist <= (stick_radius * 1.5) || (pos.x >= w * 0.50 && pos.x <= w * 0.80 && pos.y >= h * 0.50) {
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

            // H. Remaining Right area: Free Swipe Look
            if pos.x >= w * 0.45 && pos.y > 50.0 * s {
                if self.look_touch_id.is_none() {
                    self.look_touch_id = Some(t.id);
                    self.look_last_pos = pos;
                }
            }
        }
    }

    fn button_layouts(&self, w: f32, h: f32, s: f32) -> Vec<(TouchButton, Vec2, f32)> {
        let mut btns = Vec::new();

        // 1. ABXY Diamond (Bottom-Right corner)
        let cx = w - 90.0 * s;
        let cy = h - 95.0 * s;
        let spacing = 46.0 * s;
        let face_r = 25.0 * s;

        // A (bottom, green): Jump
        btns.push((TouchButton::A, vec2(cx, cy + spacing), face_r));
        // X (left, blue): Primary Attack (Knife / Blade)
        btns.push((TouchButton::X, vec2(cx - spacing, cy), face_r));
        // B (right, red): Alt Attack
        btns.push((TouchButton::B, vec2(cx + spacing, cy), face_r));
        // Y (top, yellow): Interact / Action (E)
        btns.push((TouchButton::Y, vec2(cx, cy - spacing), face_r));

        // 2. D-Pad (Left side to the right of left stick)
        let dpad_cx = 230.0 * s;
        let dpad_cy = h - 95.0 * s;
        let dspacing = 38.0 * s;
        let dpad_r = 21.0 * s;
        btns.push((TouchButton::DpadUp, vec2(dpad_cx, dpad_cy - dspacing), dpad_r));
        btns.push((TouchButton::DpadDown, vec2(dpad_cx, dpad_cy + dspacing), dpad_r));
        btns.push((TouchButton::DpadLeft, vec2(dpad_cx - dspacing, dpad_cy), dpad_r));
        btns.push((TouchButton::DpadRight, vec2(dpad_cx + dspacing, dpad_cy), dpad_r));

        // 3. Top Triggers & Shoulders
        let trig_r = 25.0 * s;
        // LT (Alt Attack) & LB (Run toggle) - Top Left
        btns.push((TouchButton::LT, vec2(60.0 * s, 38.0 * s), trig_r));
        btns.push((TouchButton::LB, vec2(145.0 * s, 38.0 * s), trig_r));

        // RB (Next weapon) & RT (Primary Attack) - Top Right
        btns.push((TouchButton::RB, vec2(w - 145.0 * s, 38.0 * s), trig_r));
        btns.push((TouchButton::RT, vec2(w - 60.0 * s, 38.0 * s), trig_r));

        // 4. System buttons (Center Top)
        let sys_r = 21.0 * s;
        btns.push((TouchButton::Select, vec2(w * 0.44, 38.0 * s), sys_r)); // Cat hint (-)
        btns.push((TouchButton::Start, vec2(w * 0.56, 38.0 * s), sys_r));  // Menu / Pause (+)

        btns
    }

    /// Analog movement vector: x = strafe (-1 left, +1 right), y = forward (+1 forward, -1 back)
    pub fn movement(&self) -> Vec2 {
        if !self.enabled {
            return Vec2::ZERO;
        }
        vec2(self.lstick_vector.x, -self.lstick_vector.y)
    }

    /// Apply look rotation to yaw and pitch (Right Stick analog + Free Swipe).
    pub fn apply_look(&self, yaw: &mut f32, pitch: &mut f32) {
        if !self.enabled {
            return;
        }
        let dt = get_frame_time().clamp(0.001, 0.05);

        // 1. Right Stick analog rotation with smooth quadratic curve
        if self.rstick_vector != Vec2::ZERO {
            let v = self.rstick_vector;
            let mag = v.length();
            let curved_mag = mag * mag; // quadratic response curve
            let dir = v / mag;
            let curved = dir * curved_mag;
            let stick_speed = 3.2 * dt; // ~3.2 radians/sec at full tilt
            *yaw = (*yaw - curved.x * stick_speed).rem_euclid(std::f32::consts::TAU);
            *pitch = (*pitch - curved.y * stick_speed).clamp(-1.5, 1.5);
        }

        // 2. Free swipe look
        if self.look_delta != Vec2::ZERO {
            let s = self.scale(screen_height());
            let swipe_sens = 0.0032 / s;
            *yaw = (*yaw - self.look_delta.x * swipe_sens).rem_euclid(std::f32::consts::TAU);
            *pitch = (*pitch - self.look_delta.y * swipe_sens).clamp(-1.5, 1.5);
        }
    }

    pub fn is_held(&self, key: KeyCode) -> bool {
        if !self.enabled {
            return false;
        }
        match key {
            KeyCode::Space => self.held_buttons.contains(&TouchButton::A),
            KeyCode::E => self.held_buttons.contains(&TouchButton::Y),
            KeyCode::LeftShift => self.run_toggled,
            KeyCode::C => self.held_buttons.contains(&TouchButton::Select),
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
            KeyCode::C => self.pressed_buttons.contains(&TouchButton::Select),
            KeyCode::Escape => self.pressed_buttons.contains(&TouchButton::Start),
            _ => false,
        }
    }

    pub fn is_action_held(&self, original: &str) -> bool {
        if !self.enabled {
            return false;
        }
        match original {
            "Mouse 1" | "Primary attack" => {
                self.held_buttons.contains(&TouchButton::X) || self.held_buttons.contains(&TouchButton::RT)
            }
            "Mouse 2" | "Alternate attack" => {
                self.held_buttons.contains(&TouchButton::B) || self.held_buttons.contains(&TouchButton::LT)
            }
            "Space" | "Jump / climb" => self.held_buttons.contains(&TouchButton::A),
            "E" | "Interact" => self.held_buttons.contains(&TouchButton::Y),
            "Shift" | "Run / walk" => self.run_toggled,
            "C" | "Cheshire hint" => self.held_buttons.contains(&TouchButton::Select),
            "Escape" | "Pause" => self.held_buttons.contains(&TouchButton::Start),
            _ => false,
        }
    }

    pub fn is_action_pressed(&self, original: &str) -> bool {
        if !self.enabled {
            return false;
        }
        match original {
            "Mouse 1" | "Primary attack" => {
                self.pressed_buttons.contains(&TouchButton::X) || self.pressed_buttons.contains(&TouchButton::RT)
            }
            "Mouse 2" | "Alternate attack" => {
                self.pressed_buttons.contains(&TouchButton::B) || self.pressed_buttons.contains(&TouchButton::LT)
            }
            "Wheel Down" | "Next toy" => {
                self.pressed_buttons.contains(&TouchButton::RB)
                    || self.pressed_buttons.contains(&TouchButton::DpadRight)
                    || self.pressed_buttons.contains(&TouchButton::DpadDown)
            }
            "Wheel Up" => {
                self.pressed_buttons.contains(&TouchButton::DpadLeft)
                    || self.pressed_buttons.contains(&TouchButton::DpadUp)
            }
            "Space" | "Jump / climb" => self.pressed_buttons.contains(&TouchButton::A),
            "E" | "Interact" => self.pressed_buttons.contains(&TouchButton::Y),
            "C" | "Cheshire hint" => self.pressed_buttons.contains(&TouchButton::Select),
            "Escape" | "Pause" => self.pressed_buttons.contains(&TouchButton::Start),
            _ => false,
        }
    }

    pub fn draw(&self) {
        if !self.enabled {
            return;
        }

        set_default_camera();
        gl_use_default_material();

        let w = screen_width();
        let h = screen_height();
        let s = self.scale(h);
        let stick_radius = 65.0 * s;
        let knob_radius = 28.0 * s;

        // 1. Draw Left Stick (Movement)
        let (lcenter, lknob) = if self.lstick_touch_id.is_some() {
            (self.lstick_center, self.lstick_center + self.lstick_vector * stick_radius)
        } else {
            let def = vec2(100.0 * s, h - 95.0 * s);
            (def, def)
        };

        // Stick base
        draw_circle(lcenter.x, lcenter.y, stick_radius, Color::new(0.0, 0.0, 0.0, 0.25));
        draw_circle_lines(lcenter.x, lcenter.y, stick_radius, 2.5 * s, Color::new(1.0, 1.0, 1.0, 0.45));
        // Line from base center to knob
        if self.lstick_vector.length_squared() > 0.01 {
            draw_line(lcenter.x, lcenter.y, lknob.x, lknob.y, 2.0 * s, Color::new(1.0, 1.0, 1.0, 0.5));
        }
        // Knob
        draw_circle(lknob.x, lknob.y, knob_radius, Color::new(0.9, 0.9, 0.9, 0.65));
        draw_circle_lines(lknob.x, lknob.y, knob_radius, 2.5 * s, Color::new(1.0, 1.0, 1.0, 0.95));

        let l_label = "L";
        let ldims = measure_text(l_label, None, (16.0 * s) as u16, 1.0);
        draw_text(l_label, lknob.x - ldims.width * 0.5, lknob.y + ldims.height * 0.35, 16.0 * s, Color::new(0.1, 0.1, 0.1, 0.95));

        // 2. Draw Right Stick (Camera Look)
        let default_rcenter = vec2(w - 230.0 * s, h - 95.0 * s);
        let (rcenter, rknob) = if self.rstick_touch_id.is_some() {
            (self.rstick_center, self.rstick_center + self.rstick_vector * stick_radius)
        } else {
            (default_rcenter, default_rcenter)
        };

        draw_circle(rcenter.x, rcenter.y, stick_radius, Color::new(0.0, 0.0, 0.0, 0.25));
        draw_circle_lines(rcenter.x, rcenter.y, stick_radius, 2.5 * s, Color::new(1.0, 1.0, 1.0, 0.45));
        if self.rstick_vector.length_squared() > 0.01 {
            draw_line(rcenter.x, rcenter.y, rknob.x, rknob.y, 2.0 * s, Color::new(1.0, 1.0, 1.0, 0.5));
        }
        draw_circle(rknob.x, rknob.y, knob_radius, Color::new(0.9, 0.9, 0.9, 0.65));
        draw_circle_lines(rknob.x, rknob.y, knob_radius, 2.5 * s, Color::new(1.0, 1.0, 1.0, 0.95));

        let r_label = "R";
        let rdims = measure_text(r_label, None, (16.0 * s) as u16, 1.0);
        draw_text(r_label, rknob.x - rdims.width * 0.5, rknob.y + rdims.height * 0.35, 16.0 * s, Color::new(0.1, 0.1, 0.1, 0.95));

        // 3. Draw All Controller Buttons (ABXY, Shoulders, D-Pad, System)
        let buttons = self.button_layouts(w, h, s);
        for (btn, center, radius) in buttons {
            let is_held = match btn {
                TouchButton::LB => self.run_toggled,
                _ => self.held_buttons.contains(&btn),
            };

            let bg_color = if is_held {
                match btn {
                    TouchButton::A => Color::new(0.15, 0.85, 0.25, 0.90), // Green (Xbox A)
                    TouchButton::B => Color::new(0.90, 0.20, 0.20, 0.90), // Red (Xbox B)
                    TouchButton::X => Color::new(0.20, 0.45, 0.95, 0.90), // Blue (Xbox X)
                    TouchButton::Y => Color::new(0.95, 0.80, 0.15, 0.90), // Yellow (Xbox Y)
                    TouchButton::LB => Color::new(0.25, 0.70, 0.35, 0.85),
                    _ => Color::new(0.85, 0.35, 0.35, 0.85),
                }
            } else {
                Color::new(0.08, 0.08, 0.08, 0.55)
            };

            let border_color = if is_held {
                Color::new(1.0, 1.0, 1.0, 1.0)
            } else {
                match btn {
                    TouchButton::A => Color::new(0.3, 0.9, 0.3, 0.85),
                    TouchButton::B => Color::new(0.9, 0.3, 0.3, 0.85),
                    TouchButton::X => Color::new(0.3, 0.6, 1.0, 0.85),
                    TouchButton::Y => Color::new(1.0, 0.85, 0.3, 0.85),
                    _ => Color::new(1.0, 1.0, 1.0, 0.70),
                }
            };

            draw_circle(center.x, center.y, radius, bg_color);
            draw_circle_lines(center.x, center.y, radius, 2.5 * s, border_color);

            let label = match btn {
                TouchButton::A => "A",
                TouchButton::B => "B",
                TouchButton::X => "X",
                TouchButton::Y => "Y",
                TouchButton::LT => "LT",
                TouchButton::LB => if self.run_toggled { "RUN" } else { "WALK" },
                TouchButton::RT => "RT",
                TouchButton::RB => "RB",
                TouchButton::DpadUp => "^",
                TouchButton::DpadDown => "v",
                TouchButton::DpadLeft => "<",
                TouchButton::DpadRight => ">",
                TouchButton::Start => "+",
                TouchButton::Select => "-",
            };

            let font_size = if label == "RUN" || label == "WALK" {
                12.0 * s
            } else if radius >= 24.0 * s {
                18.0 * s
            } else {
                14.0 * s
            };

            let dims = measure_text(label, None, font_size as u16, 1.0);
            draw_text(
                label,
                center.x - dims.width * 0.5,
                center.y + dims.height * 0.35,
                font_size,
                Color::new(1.0, 1.0, 1.0, 0.95),
            );
        }
    }
}
