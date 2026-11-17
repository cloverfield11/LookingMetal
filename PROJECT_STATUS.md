# LookingMetal — Project Status & Architecture Guide

## 1. About the Project
**LookingMetal** is an open-source Apple Metal port and enhancement of **American McGee's Alice (2000)** based on the **LookingGlass** engine written in **Rust**.
It uses `macroquad` and `miniquad` as low-level graphics backends running natively on **Apple Metal 3** for iOS (iPhone / iPad) and macOS ARM (Apple Silicon).

**Primary Goal:**
Deliver a native, standalone, high-performance port for iOS and macOS featuring full touch controls, physical gamepad support, pre-game configuration launcher, and compatibility with modern sideloading environments (LiveContainer, TrollStore, AltStore, SideStore).

---

## 2. Implemented Features & Technical Architecture

### A. Native Metal 3 Compilation & iOS Compatibility
- Builds natively for target `aarch64-apple-ios`:
  ```bash
  cargo build --release --target aarch64-apple-ios
  ```
- **Mach-O SDK Patch (LiveContainer fix):** By default, the Rust toolchain sets `LC_VERSION_MIN_IPHONEOS` SDK version to `27.2`, which causes dyld assertions on iOS 16/17 and LiveContainer. `build.sh` automatically patches this header to SDK `16.5` (`0x00100500`).
- Configured iOS application manifest (`ios/Info.plist`) with landscape orientations, Metal Performance HUD toggle, GameController profiles, and Document file sharing.

### B. Vendored & Patched Miniquad (`third_party/miniquad`)
Vendored locally into `third_party/miniquad` and linked via `[patch.crates-io]` in `Cargo.toml`:
1. **Hardware Multitouch Enabled:** Added `[mtk_view_obj setMultipleTouchEnabled: YES]` in `third_party/miniquad/src/native/ios.rs`.
2. **Stable Touch Pointer Tracking:** Touch IDs are derived directly from the `UITouch` pointer (`ios_touch as usize as u64`), with per-touch phase checking via `[ios_touch phase]` instead of broadcasting global cancellations.
3. **Unlocked 120 FPS ProMotion:** `MTKView` configured with `setPreferredFramesPerSecond: 120`.
4. **Resolved Touch-to-Mouse Conflict:** In `src/viewer.rs`, `macroquad::input::simulate_mouse_with_touch(false)` is invoked. Desktop `mouse_look.update()` is bypassed during touch sessions on iOS, preventing synthetic mouse jump issues during multi-finger inputs.

### C. Pre-Game Configuration Launcher (`src/launcher.rs`)
An interactive touch-first launcher rendered before loading Wonderland:
- Target Frame Rate (60 FPS / 120 FPS ProMotion / 30 FPS Power Save).
- Metal Performance HUD (ON / OFF).
- Screen Aspect Ratio (Fullscreen 19.5:9 / 16:9 Widescreen / 4:3 Classic).
- Controller Mode (Touch + Physical / Physical Controller Only).
- On-Screen Controls Size (Large 125% / Standard 100% / Huge 150%).
- Persistent settings storage saved to `ios-launcher.json`.

### D. Full Virtual Controller Layout (`src/touch_gamepad.rs`)
Console-grade Xbox / Nintendo Switch layout:
- **Left Stick (L):** 360° analog locomotion with floating/dynamic thumb centering.
- **Right Stick (R):** 360° continuous camera panning with quadratic acceleration.
- **Free Swipe Look:** Dragging anywhere on the empty right half of the screen controls view rotation.
- **ABXY Diamond:**
  - `A` (Green, Bottom): Jump / Climb (`Space`).
  - `X` (Blue, Left): Primary Attack (`Mouse 1`).
  - `B` (Red, Right): Alternate Attack (`Mouse 2`).
  - `Y` (Yellow, Top): Interact / Action (Key `E`).
- **D-Pad:** Next / Previous weapon cycling.
- **Triggers & Shoulders:** `LT` / `RT` (Attacks), `LB` (Run/Walk toggle), `RB` (Next toy).
- **System Buttons:** `+` (Menu / Pause / Esc), `-` (Cheshire Cat hint / C).
- Retina display responsive scaling (`scale = (h / 390.0) * scale_mult`).

### E. Physical Controller Bridge (`src/ios_controller.rs`)
Native Apple `GameController.framework` integration:
- Auto-detects Xbox, PlayStation DualSense/DualShock, Nintendo Switch Pro, Backbone, and Razer Kishi controllers.
- Automatically hides virtual on-screen touch controls when a physical controller is connected.

### F. Smart Cutscene Skipping (`src/movie.rs` & `src/viewer.rs`)
- Accidental screen taps no longer skip cinematic sequences.
- Cutscene skipping strictly requires tapping the prominent `[ SKIP >> ]` on-screen button or holding controller A / Enter.

---

## 3. Repository Structure

- `build.sh` — Unified build script (setup, compile, patch, icon resize, codesign, package).
- `Cargo.toml` — Package manifest pointing to local patched `third_party/miniquad`.
- `base/` — Game PK3 archive container (`pak0.pk3` through `pak5.pk3`).
- `ios/Info.plist` — iOS Application bundle manifest.
- `ios/AppIcon.png` — Master high-resolution app icon.
- `third_party/miniquad/` — Patched Miniquad engine layer.
- `src/launcher.rs` — Touch settings launcher.
- `src/touch_gamepad.rs` — Virtual gamepad subsystem.
- `src/ios_controller.rs` — GameController.framework bridge.
- `src/viewer.rs` — Core game loop, touch routing, and rendering hooks.
- `src/movie.rs` — Video cutscene player.
- `src/main.rs` — LookingMetal entry point.

---

## 4. Next Development Tasks

1. **Safe Area Insets (Dynamic Island):** Add margin offsets using `safeAreaInsets` on modern iPhone displays.
2. **On-Screen Inventory Wheel:** Quick-select carousel for rapid weapon switching on touch screens.
3. **Gyro Aiming (CoreMotion):** Optional fine-aiming motion controls.
