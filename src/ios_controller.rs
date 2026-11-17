//! Apple GameController framework bridge for physical gamepads (Xbox, PlayStation, MFi, Backbone, Kishi).
use macroquad::prelude::*;

#[derive(Default, Clone, Copy, Debug)]
pub struct PhysicalPadState {
    pub connected: bool,
    pub move_axis: Vec2,
    pub look_axis: Vec2,
    pub a_pressed: bool,
    pub a_held: bool,
    pub b_pressed: bool,
    pub b_held: bool,
    pub x_pressed: bool,
    pub x_held: bool,
    pub y_pressed: bool,
    pub y_held: bool,
    pub rt_pressed: bool,
    pub rt_held: bool,
    pub lt_pressed: bool,
    pub lt_held: bool,
    pub rb_pressed: bool,
    pub rb_held: bool,
    pub lb_pressed: bool,
    pub lb_held: bool,
    pub start_pressed: bool,
    pub start_held: bool,
}

#[cfg(target_os = "ios")]
#[link(name = "GameController", kind = "framework")]
extern "C" {}

pub struct IosGamepad {
    prev_a: bool,
    prev_b: bool,
    prev_x: bool,
    prev_y: bool,
    prev_rt: bool,
    prev_lt: bool,
    prev_rb: bool,
    prev_lb: bool,
    prev_start: bool,
    pub state: PhysicalPadState,
}

impl Default for IosGamepad {
    fn default() -> Self {
        Self {
            prev_a: false,
            prev_b: false,
            prev_x: false,
            prev_y: false,
            prev_rt: false,
            prev_lt: false,
            prev_rb: false,
            prev_lb: false,
            prev_start: false,
            state: PhysicalPadState::default(),
        }
    }
}

impl IosGamepad {
    #[cfg(target_os = "ios")]
    pub fn update(&mut self) {
        use objc::runtime::Object;
        use objc::{class, msg_send, sel};

        unsafe {
            let controllers: *mut Object = msg_send![class!(GCController), controllers];
            if controllers.is_null() {
                self.state = PhysicalPadState::default();
                return;
            }
            let count: usize = msg_send![controllers, count];

            if count == 0 {
                self.state = PhysicalPadState::default();
                return;
            }

            let controller: *mut Object = msg_send![controllers, objectAtIndex: 0];
            let extended: *mut Object = msg_send![controller, extendedGamepad];

            if extended.is_null() {
                self.state = PhysicalPadState::default();
                return;
            }

            // Left thumbstick (movement: x = strafe, y = forward/back)
            let left_stick: *mut Object = msg_send![extended, leftThumbstick];
            let left_x: *mut Object = msg_send![left_stick, xAxis];
            let lx: f32 = msg_send![left_x, value];
            let left_y: *mut Object = msg_send![left_stick, yAxis];
            let ly: f32 = msg_send![left_y, value];

            // Right thumbstick (look: x = yaw, y = pitch)
            let right_stick: *mut Object = msg_send![extended, rightThumbstick];
            let right_x: *mut Object = msg_send![right_stick, xAxis];
            let rx: f32 = msg_send![right_x, value];
            let right_y: *mut Object = msg_send![right_stick, yAxis];
            let ry: f32 = msg_send![right_y, value];

            // Buttons
            let btn_a: *mut Object = msg_send![extended, buttonA];
            let a_held: bool = msg_send![btn_a, isPressed];

            let btn_b: *mut Object = msg_send![extended, buttonB];
            let b_held: bool = msg_send![btn_b, isPressed];

            let btn_x: *mut Object = msg_send![extended, buttonX];
            let x_held: bool = msg_send![btn_x, isPressed];

            let btn_y: *mut Object = msg_send![extended, buttonY];
            let y_held: bool = msg_send![btn_y, isPressed];

            let r_trig: *mut Object = msg_send![extended, rightTrigger];
            let rt_val: f32 = msg_send![r_trig, value];
            let rt_held = rt_val > 0.45;

            let l_trig: *mut Object = msg_send![extended, leftTrigger];
            let lt_val: f32 = msg_send![l_trig, value];
            let lt_held = lt_val > 0.45;

            let r_shld: *mut Object = msg_send![extended, rightShoulder];
            let rb_held: bool = msg_send![r_shld, isPressed];

            let l_shld: *mut Object = msg_send![extended, leftShoulder];
            let lb_held: bool = msg_send![l_shld, isPressed];

            let menu_btn: *mut Object = msg_send![extended, buttonMenu];
            let start_held: bool = if !menu_btn.is_null() {
                msg_send![menu_btn, isPressed]
            } else {
                false
            };

            self.state = PhysicalPadState {
                connected: true,
                move_axis: vec2(lx, ly),
                look_axis: vec2(rx, ry),
                a_pressed: a_held && !self.prev_a,
                a_held,
                b_pressed: b_held && !self.prev_b,
                b_held,
                x_pressed: x_held && !self.prev_x,
                x_held,
                y_pressed: y_held && !self.prev_y,
                y_held,
                rt_pressed: rt_held && !self.prev_rt,
                rt_held,
                lt_pressed: lt_held && !self.prev_lt,
                lt_held,
                rb_pressed: rb_held && !self.prev_rb,
                rb_held,
                lb_pressed: lb_held && !self.prev_lb,
                lb_held,
                start_pressed: start_held && !self.prev_start,
                start_held,
            };

            self.prev_a = a_held;
            self.prev_b = b_held;
            self.prev_x = x_held;
            self.prev_y = y_held;
            self.prev_rt = rt_held;
            self.prev_lt = lt_held;
            self.prev_rb = rb_held;
            self.prev_lb = lb_held;
            self.prev_start = start_held;
        }
    }

    #[cfg(not(target_os = "ios"))]
    pub fn update(&mut self) {}
}
