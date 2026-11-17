//! Clean, modern mobile action-game touch controls.
//! Features right-screen swipe camera look and large ergonomic action buttons (Platformer layout).
use macroquad::prelude::*;
use std::cell::Cell;
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
    // Left Joystick (Locomotion: Walk / Sprint)
    lstick_touch_id: Option<u64>,
    lstick_center: Vec2,
    lstick_current: Vec2,
    lstick_vector: Vec2,

    // Camera Look Swipe (Right-screen touch swipe)
    look_touch_id: Option<u64>,
    look_prev_pos: Vec2,
    look_delta: Cell<Vec2>,

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

            look_touch_id: None,
            look_prev_pos: Vec2::ZERO,
            look_delta: Cell::new(Vec2::ZERO),

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
            self.look_touch_id = None;
            self.look_delta.set(Vec2::ZERO);
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
            self.look_touch_id = None;
            self.look_delta.set(Vec2::ZERO);
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

        // Release stick if touch is gone
        if let Some(id) = self.lstick_touch_id {
            if !active_ids.contains(&id) {
                self.lstick_touch_id = None;
                self.lstick_vector = Vec2::ZERO;
            }
        }

        // Release look swipe if touch is gone
        if let Some(id) = self.look_touch_id {
            if !active_ids.contains(&id) {
                self.look_touch_id = None;
            }
        }

        let buttons = self.button_layouts(w, h, s);

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

            // 2. Existing Camera Look Swipe touch
            if self.look_touch_id == Some(t.id) {
                match t.phase {
                    TouchPhase::Moved => {
                        let delta = pos - self.look_prev_pos;
                        // Guard against sudden coordinate jumps (e.g. frame lag)
                        if delta.length() < 200.0 * s {
                            self.look_delta.set(self.look_delta.get() + delta);
                        }
                        self.look_prev_pos = pos;
                    }
                    TouchPhase::Stationary => {
                        self.look_prev_pos = pos;
                    }
                    TouchPhase::Ended | TouchPhase::Cancelled => {
                        self.look_touch_id = None;
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

            // 4. New touch: Check button hits with comfortable padding
            let mut hit_btn = None;
            for (btn, center, radius) in &buttons {
                if pos.distance(*center) <= (*radius + 10.0 * s) {
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

            // 5. New touch on Left half: Left Joystick (Locomotion)
            if pos.x < w * 0.42 && pos.y > 60.0 * s {
                if (t.phase == TouchPhase::Started || t.phase == TouchPhase::Moved) && self.lstick_touch_id.is_none() {
                    self.lstick_touch_id = Some(t.id);
                    self.lstick_center = pos;
                    self.lstick_current = pos;
                    self.lstick_vector = Vec2::ZERO;
                }
                continue;
            }

            // 6. New touch on Right half (not hitting any button): Camera Look Swipe!
            if pos.x >= w * 0.40 {
                if (t.phase == TouchPhase::Started || t.phase == TouchPhase::Moved) && self.look_touch_id.is_none() {
                    self.look_touch_id = Some(t.id);
                    self.look_prev_pos = pos;
                }
                continue;
            }
        }
    }

    /// Button layouts adhering to the approved "Platformer (Jump Low)" mapping.
    /// Buttons are large, ergonomic, and comfortably positioned for natural thumb resting.
    fn button_layouts(&self, w: f32, h: f32, s: f32) -> Vec<(TouchButton, Vec2, f32)> {
        let mut btns = Vec::new();

        // 1. Jump & Climb (A): Giant button in bottom-right corner directly under the resting thumb
        // Diameter ~78-80px
        let jump_r = 39.0 * s;
        let jump_center = vec2(w - 70.0 * s, h - 66.0 * s);
        btns.push((TouchButton::A, jump_center, jump_r));

        // 2. Primary Attack: Vorpal Blade Slash (X): Giant button directly to the left of Jump
        // Diameter ~78-80px for easy thumb roll between jump and slash
        let slash_r = 39.0 * s;
        let slash_center = vec2(w - 161.0 * s, h - 69.0 * s);
        btns.push((TouchButton::X, slash_center, slash_r));

        // 3. Alt Attack: Throw Blade (B): Above Slash
        // Diameter ~62px
        let throw_r = 31.0 * s;
        let throw_center = vec2(w - 161.0 * s, h - 153.0 * s);
        btns.push((TouchButton::B, throw_center, throw_r));

        // 4. Action / Interact: Key E (Y): Above Jump
        // Diameter ~58px
        let use_r = 29.0 * s;
        let use_center = vec2(w - 63.0 * s, h - 149.0 * s);
        btns.push((TouchButton::Y, use_center, use_r));

        // 5. Swap Weapons / Next Toy (Next): Top-center of cluster
        // Diameter ~54px
        let next_r = 27.0 * s;
        let next_center = vec2(w - 109.0 * s, h - 211.0 * s);
        btns.push((TouchButton::Next, next_center, next_r));

        // 6. Pause / Menu (+ / Start): Top-right corner
        let menu_r = 20.0 * s;
        let menu_center = vec2(w - 42.0 * s, 36.0 * s);
        btns.push((TouchButton::Start, menu_center, menu_r));

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

    /// Apply camera look rotation from right-screen touch swipes.
    pub fn apply_look(&self, yaw: &mut f32, pitch: &mut f32) {
        if !self.enabled {
            self.look_delta.set(Vec2::ZERO);
            return;
        }
        let delta = self.look_delta.take();
        if delta.length_squared() > 0.0001 {
            let sens = 0.0034;
            *yaw = (*yaw - delta.x * sens).rem_euclid(std::f32::consts::TAU);
            *pitch = (*pitch - delta.y * sens).clamp(-1.5, 1.5);
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

        // Dark translucent glass base with double ring
        draw_circle(lcenter.x, lcenter.y, stick_radius, Color::new(0.04, 0.05, 0.08, 0.22));
        draw_circle_lines(lcenter.x, lcenter.y, stick_radius, 1.8 * s, Color::new(0.85, 0.88, 0.94, 0.25));
        draw_circle_lines(lcenter.x, lcenter.y, stick_radius * 0.5, 1.0 * s, Color::new(1.0, 1.0, 1.0, 0.10));

        // Direction guide line
        if self.lstick_vector.length_squared() > 0.01 {
            draw_line(lcenter.x, lcenter.y, lknob.x, lknob.y, 2.0 * s, Color::new(1.0, 1.0, 1.0, 0.50));
        }

        // Frosted Gray Shaded Knob
        draw_circle(lknob.x, lknob.y, knob_radius, Color::new(0.85, 0.88, 0.92, 0.45));
        draw_circle_lines(lknob.x, lknob.y, knob_radius, 1.8 * s, Color::new(1.0, 1.0, 1.0, 0.80));
        draw_circle_lines(lknob.x, lknob.y, knob_radius * 0.45, 1.2 * s, Color::new(0.2, 0.2, 0.2, 0.25));

        let l_rect = Rect::new(lknob.x - knob_radius, lknob.y - knob_radius, knob_radius * 2.0, knob_radius * 2.0);
        ui.center("MOVE", l_rect, 10.0 * s, Color::new(0.95, 0.95, 0.98, 0.85));

        // ==========================================
        // 2. Action Buttons (Platformer Layout: Monochromatic Frosted Glass)
        // ==========================================
        let buttons = self.button_layouts(w, h, s);
        for (btn, center, radius) in buttons {
            let is_held = self.held_buttons.contains(&btn);

            let label = match btn {
                TouchButton::A => "JUMP",
                TouchButton::X => "SLASH",
                TouchButton::B => "THROW",
                TouchButton::Y => "USE",
                TouchButton::Next => "SWAP",
                TouchButton::Start => "+",
            };

            let bg_color = if is_held {
                Color::new(0.95, 0.95, 0.98, 0.42)
            } else {
                Color::new(0.06, 0.07, 0.10, 0.22) // Highly translucent dark glass (~78% transparent)
            };

            let border_color = if is_held {
                WHITE
            } else {
                Color::new(0.88, 0.90, 0.95, 0.38) // Sleek frosted silver ring
            };

            let icon_color = if is_held {
                WHITE
            } else {
                Color::new(0.90, 0.92, 0.96, 0.65) // Soft semi-transparent white/silver
            };

            // Soft drop shadow
            draw_circle(center.x + 1.5 * s, center.y + 1.5 * s, radius, Color::new(0.0, 0.0, 0.0, 0.20));

            // Main body
            draw_circle(center.x, center.y, radius, bg_color);
            draw_circle_lines(center.x, center.y, radius, 1.8 * s, border_color);

            // Subtle inner ring
            if !is_held {
                draw_circle_lines(center.x, center.y, radius * 0.82, 1.0 * s, Color::new(1.0, 1.0, 1.0, 0.12));
            }

            // Draw custom vector icon based on action
            match btn {
                TouchButton::A => {
                    // Jump / Climb: Upward leaping chevron / arrow
                    let tip = center + vec2(0.0, -radius * 0.38);
                    let left = center + vec2(-radius * 0.38, -radius * 0.02);
                    let right = center + vec2(radius * 0.38, -radius * 0.02);
                    draw_line(tip.x, tip.y, left.x, left.y, 3.2 * s, icon_color);
                    draw_line(tip.x, tip.y, right.x, right.y, 3.2 * s, icon_color);
                    draw_line(center.x, tip.y + 2.0 * s, center.x, center.y + radius * 0.18, 3.0 * s, icon_color);
                    // Base step bar
                    draw_line(center.x - radius * 0.30, center.y + radius * 0.24, center.x + radius * 0.30, center.y + radius * 0.24, 2.0 * s, icon_color);
                }
                TouchButton::X => {
                    // Primary Attack (Vorpal Blade Slash): Angled razor dagger
                    let tip = center + vec2(radius * 0.38, -radius * 0.38);
                    let hilt = center + vec2(-radius * 0.12, radius * 0.12);
                    let pommel = center + vec2(-radius * 0.34, radius * 0.34);
                    // Pommel / grip
                    draw_line(pommel.x, pommel.y, hilt.x, hilt.y, 3.5 * s, icon_color);
                    // Crossguard
                    let g1 = hilt + vec2(-radius * 0.18, -radius * 0.18);
                    let g2 = hilt + vec2(radius * 0.18, radius * 0.18);
                    draw_line(g1.x, g1.y, g2.x, g2.y, 2.8 * s, icon_color);
                    // Blade spine
                    draw_line(hilt.x, hilt.y, tip.x, tip.y, 4.0 * s, icon_color);
                    // Curved blade belly
                    let belly = hilt + vec2(radius * 0.06, -radius * 0.28);
                    draw_triangle(hilt, tip, belly, icon_color);
                }
                TouchButton::B => {
                    // Alt Attack (Blade Throw): Flying dagger with speed trails
                    let tip = center + vec2(radius * 0.35, -radius * 0.28);
                    let hilt = center + vec2(-radius * 0.15, radius * 0.15);
                    draw_line(hilt.x, hilt.y, tip.x, tip.y, 3.2 * s, icon_color);
                    let guard1 = hilt + vec2(-radius * 0.12, -radius * 0.12);
                    let guard2 = hilt + vec2(radius * 0.12, radius * 0.12);
                    draw_line(guard1.x, guard1.y, guard2.x, guard2.y, 2.2 * s, icon_color);
                    // Speed lines behind
                    draw_line(center.x - radius * 0.40, center.y - radius * 0.08, center.x - radius * 0.18, center.y - radius * 0.08, 1.8 * s, icon_color);
                    draw_line(center.x - radius * 0.35, center.y + radius * 0.12, center.x - radius * 0.14, center.y + radius * 0.12, 1.8 * s, icon_color);
                }
                TouchButton::Y => {
                    // Use / Interact (Key E): Open reaching hand / action spark
                    let palm = center + vec2(0.0, radius * 0.08);
                    draw_circle(palm.x, palm.y, radius * 0.20, icon_color);
                    // 4 fingers
                    draw_line(palm.x - radius * 0.16, palm.y, palm.x - radius * 0.22, palm.y - radius * 0.34, 2.5 * s, icon_color);
                    draw_line(palm.x - radius * 0.06, palm.y, palm.x - radius * 0.06, palm.y - radius * 0.40, 2.5 * s, icon_color);
                    draw_line(palm.x + radius * 0.06, palm.y, palm.x + radius * 0.06, palm.y - radius * 0.38, 2.5 * s, icon_color);
                    draw_line(palm.x + radius * 0.16, palm.y, palm.x + radius * 0.20, palm.y - radius * 0.30, 2.5 * s, icon_color);
                }
                TouchButton::Next => {
                    // Weapon Cycle: Circular swap arrows
                    let arc_r = radius * 0.36;
                    let c = center + vec2(0.0, -radius * 0.08);
                    draw_circle_lines(c.x, c.y, arc_r, 2.2 * s, icon_color);
                    // Arrowhead 1
                    let a1 = c + vec2(arc_r, 0.0);
                    draw_line(a1.x, a1.y, a1.x - 5.0 * s, a1.y - 5.0 * s, 2.2 * s, icon_color);
                    draw_line(a1.x, a1.y, a1.x + 5.0 * s, a1.y - 5.0 * s, 2.2 * s, icon_color);
                }
                TouchButton::Start => {
                    // Pause / Menu: Pause bars
                    let bar_w = 3.2 * s;
                    let bar_h = radius * 0.65;
                    draw_rectangle(center.x - radius * 0.35, center.y - bar_h * 0.5, bar_w, bar_h, icon_color);
                    draw_rectangle(center.x + radius * 0.35 - bar_w, center.y - bar_h * 0.5, bar_w, bar_h, icon_color);
                }
            }

            // High-res Gothic text label at the bottom of the button
            if label != "+" {
                let label_rect = Rect::new(center.x - radius, center.y + radius * 0.28, radius * 2.0, radius * 0.65);
                let font_size = match btn {
                    TouchButton::A | TouchButton::X => 9.5 * s,
                    TouchButton::B | TouchButton::Y => 8.5 * s,
                    TouchButton::Next => 8.0 * s,
                    _ => 9.0 * s,
                };
                let text_color = if is_held {
                    WHITE
                } else {
                    Color::new(0.90, 0.92, 0.96, 0.75)
                };
                ui.center(label, label_rect, font_size, text_color);
            }
        }
    }
}
