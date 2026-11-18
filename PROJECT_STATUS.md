# LookingMetal — Project Status & Architecture Guide

## 1. About the Project
**LookingMetal** is an open-source Apple Metal port and enhancement of **American McGee's Alice (2000)** based on the **LookingGlass** engine written in **Rust**.
It uses `macroquad` and `miniquad` as low-level graphics backends running natively on **Apple Metal 3** for iOS (iPhone / iPad) and macOS ARM (Apple Silicon).

**Primary Goal:**
Deliver a native, standalone, high-performance port for iOS and macOS featuring full touch controls, physical gamepad support, pre-game configuration launcher, and compatibility with modern sideloading environments (LiveContainer, TrollStore, AltStore, SideStore) with locked 120 FPS ProMotion.

---

## 2. Implemented Features & Technical Architecture

### A. Native Metal 3 Compilation & iOS Compatibility
- Builds natively for target `aarch64-apple-ios`:
  ```bash
  cargo build --release --target aarch64-apple-ios
  ```
- **Mach-O SDK Patch (LiveContainer fix):** By default, the Rust toolchain sets `LC_VERSION_MIN_IPHONEOS` SDK version to `27.2`, which causes dyld assertions on iOS 16/17 and LiveContainer. `build.sh` automatically patches this header to SDK `16.5` (`0x00100500`).
- Configured iOS application manifest (`ios/Info.plist`) with landscape orientations, Metal Performance HUD toggle, GameController profiles, and Document file sharing.

### B. Hardware Pacing & Asynchronous Triple-Buffering (`third_party/miniquad`)
Vendored locally into `third_party/miniquad` and linked via `[patch.crates-io]` in `Cargo.toml`:
1. **CADisplayLink Hardware Pacing:** Render loop runs directly on MTKView's internal CADisplayLink (`paused: NO`, `enableSetNeedsDisplay: NO`) at the physical display refresh rate, eliminating background worker sleep drift and frame interval sawtooth jitter.
2. **Asynchronous Frame Pacing (`AliceFramePacing`):** Managed 3-permit dispatch semaphore with a 500ms safety timeout coordinates CPU encoding with GPU completion. Command buffer commits asynchronously without blocking stalls (`waitUntilCompleted` removed on iOS).
3. **Adaptive Retina Scaling:** High-density 3x displays (iPhone 16 Pro Max 2868x1320) are automatically tuned to 2.0x (`1912x880`, >300 PPI), slashing fragment fillrate load by >50% and reducing GPU frame time to ~4.5ms.
4. **Hardware Multitouch & Pointer Tracking:** `[mtk_view_obj setMultipleTouchEnabled: YES]` with touch IDs derived directly from `UITouch` pointers.
5. **Unlocked 120 FPS ProMotion:** `MTKView` configured with `setPreferredFramesPerSecond: 120`.

### C. Persistent File Logging & In-App Crash Viewer
- **Session File Logging:** Automatically streams stdout and stderr to `Documents/LookingMetal.log`.
- **Signal & Panic Tracer:** Captures fatal signals (`SIGSEGV`, `SIGBUS`, `SIGABRT`) and Rust panics with callstack backtraces written to `Documents/LookingMetal_crash.log`.
- **In-App Viewer:** Accessible via "View Logs & Crash Reports" in the Settings menu with one-tap clipboard copy.

### D. Native Frosted Glass UI (`AliceNativeMenu`)
Clean English native interface with `UIBlurEffect` and `UIImpactFeedbackGenerator`:
- Quick Save, Load Game, Chapter Select, Settings, Difficulty Selection.
- Real-time Audio sliders (Sound, Music, Voice) and Camera Look Sensitivity / Invert Y.
- Metal Performance HUD toggle with live overlay switching.

### E. Ergonomic Mobile Touch Controls (`src/touch_gamepad.rs`)
- **Physically Scaled Thumb Targets:** Automatically adapts to screen dimensions maintaining a constant ~15–16 mm physical size.
- **Left Analog Stick (L):** 360° locomotion with dynamic floating thumb centering. Analog speed control: slight deflection walks quietly, full deflection sprints.
- **Right-Screen Touch Swipe Look:** Entire right screen provides natural, fluid camera rotation (no rigid right stick cluttering the screen).
- **Monochromatic Glass Buttons:** Vector-rendered icons for JUMP, SLASH, THROW, USE, and circular weapon cycle.
- **Frosted Glass Monochromatic Buttons:** Translucent silver glassmorphism with bespoke procedural vector icons:
  - `JUMP` (Boot / Upward Arrow, low-right corner under natural resting thumb).
  - `SLASH` (Vorpal Blade, primary attack beside Jump).
  - `THROW` (Flying Dagger projectile).
  - `USE` (Hand icon: levers, doors, dialogue).
  - `SWAP` (Circular weapon cycling).
  - `+` (Pause / Escape menu).
- **Adaptive Retina & Pro Max Scaling:** Scales dynamically with screen height (`(h / 390.0) * scale_mult`), rendering controls with optimal physical ergonomics on any screen size or density.

### E. Physical Controller Bridge (`src/ios_controller.rs`)
Native Apple `GameController.framework` integration:
- Auto-detects Xbox, PlayStation DualSense/DualShock, Nintendo Switch Pro, Backbone, and Razer Kishi controllers.
- Automatically hides virtual on-screen touch controls when a physical controller is connected.

### F. Smart Cutscene Skipping (`src/movie.rs` & `src/viewer.rs`)
- Accidental screen taps no longer skip cinematic sequences.
- Cutscene skipping strictly requires tapping the prominent `[ SKIP >> ]` on-screen button or holding controller A / Enter.

### G. Stack Safety & Memory Optimization (LiveContainer Resilience)
- **Eliminated Thread 0 Stack Overflow:** In sideloaded environments like LiveContainer, iOS caps Thread 0 at 1008 KB. All massive level and cutscene structs (`Scene`, `Interactions`, `Npcs`, `LevelArt`, `Story`, `Hints`, `Entered`, `NextVisit`) are heap-allocated (`Box<T>`), freeing over 230 KB of main thread stack and preventing `KERN_PROTECTION_FAILURE`.
- **System `zlib` Backend:** Asset decompression switched from `miniz_oxide` to Apple's native `/usr/lib/libz.dylib`, allocating tables dynamically on the heap with hardware acceleration.

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
