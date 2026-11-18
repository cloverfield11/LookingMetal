# 🪞 LookingMetal

> **Native Apple Metal port of American McGee's Alice (2000) for iOS and Apple Silicon macOS.**

[![Platform](https://img.shields.io/badge/Platforms-iOS%2015%2B%20%7C%20macOS%20ARM-blue.svg)](https://apple.com)
[![Status](https://img.shields.io/badge/Status-Fully%20Playable%20on%20Metal%20(22--40%20FPS)-success.svg)]()
[![Graphics](https://img.shields.io/badge/Graphics-Pure%20Apple%20Metal%20%26%20MetalKit-orange.svg)](https://developer.apple.com/metal/)
[![Engine](https://img.shields.io/badge/Language-Rust-red.svg)](https://www.rust-lang.org)
[![Sideloading](https://img.shields.io/badge/Sideloading-LiveContainer%20%7C%20SideStore%20%7C%20TrollStore-brightgreen.svg)]()

**LookingMetal** is a specialized fork of [LookingGlass](https://github.com/looking-glass-project/LookingGlass), engineered to bring **American McGee's Alice** natively to modern Apple hardware (iPhone, iPad, and Apple Silicon Macs) using **pure Apple Metal & MetalKit**.

No x86 emulation, UTM virtual machines, or translation layers — this is a pure native `aarch64` port running directly on the Metal hardware pipeline.

---

## 🎮 Current Project Status

- **Status:** **Fully Playable** on pure Apple Metal (`aarch64-apple-ios` and `aarch64-apple-darwin`).
- **Framerate:** ~22–40 FPS on iPhone (playable on device via LiveContainer).
- **Branching Model:** Unified single `main` branch. Active ongoing optimizations for draw-call batching and pipeline pacing.

---

## ✨ Features

- ⚡️ **Pure Apple Metal Graphics:**
  - Complete Metal rendering pipeline with MSL (Metal Shading Language) shaders.
  - Hardware Z-buffer depth testing, alpha blending, and texture samplers.
  - Full edge-to-edge fullscreen Retina rendering without cropping or black bars across all aspect ratios (19.5:9 on modern iPhones, 4:3 on iPad).
  - Native Apple Metal 3 Performance HUD overlay toggle for real-time GPU/FPS telemetry.
- 📱 **Native Frosted Glass UIKit UI (`AliceNativeMenu`):**
  - Modern iOS design language with `UIBlurEffect` and haptic feedback (`UIImpactFeedbackGenerator`).
  - Chapter selector with previews, difficulty selection (Easy / Medium / Hard).
  - Full save and load slot management with timestamps and chapter metadata.
  - Real-time Audio sliders (Sound, Music, Voice) and Look Sensitivity / Invert Y toggles.
- 🛡️ **LiveContainer & Sideloading Optimized:**
  - **No JIT Required:** Runs seamlessly in restricted environments like LiveContainer and SideStore.
  - **Mach-O SDK 16.5 Patching:** Built-in automatic SDK header patch eliminating dyld version rejections.
  - **Zero Stack Overflow Guarantees:** Massive game world structures (`Scene`, `Interactions`, `Npcs`, `LevelArt`) are safely heap-allocated (`Box<T>`), avoiding iOS's strict Thread 0 stack limit.
  - **Leak-Free VRAM Lifecycle:** Synchronous buffer rotation and proper Metal reference lifecycle prevent memory bloat and iOS Jetsam OOM kills.
- 🎮 **Ergonomic Adaptive Mobile Controls:**
  - **Physically Proportional Scaling:** Touch gamepad scales to physical millimeters (~15–16 mm primary thumb targets), remaining comfortable on both compact screens and large displays without obscuring the action.
  - **Left Analog Stick (MOVE):** Floating thumb base with dynamic deadzones; gentle tilt walks calmly, full push sprints.
  - **Right-Screen Look Swipe:** Fluid camera navigation across the entire right screen half with touch discrimination.
  - **Monochromatic Glass Buttons:** Vector-rendered icons for JUMP, SLASH (Vorpal Blade), THROW, USE, and circular weapon cycle.
  - **MFi & Console Gamepad Bridge:** Seamlessly switches to physical controllers (Xbox, DualSense, Switch Pro, Backbone, Razer Kishi) via `GameController.framework`.
- 🔊 **Independent Modern Audio:**
  - Pure Rust audio engine powered by Rodio and Symphonia (WAV/MP3 decoding).
  - Full support for original English audio and official SoftClub Russian voice acting (`pak6_RuSound.pk3`).

---

## 🚀 Quick Start (One-Click Build)

### 1. Game Data Setup
Place your original American McGee's Alice `.pk3` files into the `base/` directory:
- `pak0.pk3`
- `pak1_large.pk3` (or `pak1.pk3`)
- `pak2.pk3`
- `pak3.pk3`
- `pak4_english.pk3`
- `pak5_mod.pk3`

#### Optional: Russian Localization (SoftClub) / Русская озвучка
If you want to play with the classic Russian voice acting and text:
- Add `pak6_RuSound.pk3`, `pak6_RuText.pk3`, and `pak6_RuTextures.pk3` into `base/`.
- LookingMetal will automatically detect and load them.

### 2. Build for iPhone & iPad (IPA)
Run:
```bash
./build.sh ios
```
The script will automatically:
1. Verify and configure Rust target `aarch64-apple-ios`.
2. Compile the release binary with ThinLTO optimizations.
3. Patch the Mach-O SDK header for LiveContainer compatibility.
4. Bundle PK3 assets, icons, and `Info.plist`.
5. Apply ad-hoc codesigning.
6. Output the signed IPA package:
   - `dist/Alice_LookingMetal_iOS.ipa` (and mirrored to `~/Downloads/`).

Install using **LiveContainer**, **SideStore**, **TrollStore**, or **AltStore**.

---

### 3. macOS Native Build & Testing

- **Run natively on macOS (Keyboard + Mouse):**
  ```bash
  ./build.sh run
  ```

- **Run on macOS in Mobile Touch Simulation Mode:**
  ```bash
  ./build.sh run-touch
  ```

- **Build standalone macOS Application (`.app`):**
  ```bash
  ./build.sh mac
  ```

---

## 📁 Repository Structure

```text
LookingMetal/
├── build.sh                  # All-in-one build and packaging script
├── Cargo.toml                # Rust dependencies & package configuration
├── base/                     # Directory for Alice game data (*.pk3)
├── ios/
│   ├── AliceNativeMenu.h     # Native UIKit frosted glass menu interface
│   ├── AliceNativeMenu.m     # Native UIKit launcher & pause screen implementation
│   ├── Info.plist            # iOS Application manifest
│   └── AppIcon.png           # Master application icon
├── dist/                     # Generated release packages (.ipa / .app)
├── third_party/
│   └── miniquad/             # Custom pure Apple Metal backend & iOS event loop
├── src/
│   ├── touch_gamepad.rs      # Adaptive virtual gamepad subsystem
│   ├── ios_menu.rs           # Rust bridge to native UIKit menu
│   ├── ios_controller.rs     # Apple GameController.framework bridge
│   ├── viewer.rs             # Rendering loop and input dispatcher
│   ├── movie.rs              # Cinematic video playback
│   └── main.rs               # LookingMetal entry point
└── PROJECT_STATUS.md         # Technical architecture documentation
```

---

## 🛠 `build.sh` Command Reference

| Command | Description |
|---|---|
| `./build.sh ios` | Build and package standalone `.ipa` for iOS |
| `./build.sh mac` | Build native `.app` bundle for macOS (Apple Silicon) |
| `./build.sh run` | Run game natively on macOS (Keyboard + Mouse) |
| `./build.sh run-touch` | Run on macOS simulating mobile touch gamepad & launcher |
| `./build.sh setup` | Verify toolchains and download missing targets |
| `./build.sh clean` | Clean build artifacts and temporary cache |

---

## 👨‍💻 Author & Maintainer

- **Igor Gaponenko** ([@cloverfield11](https://github.com/cloverfield11)) — Creator and lead developer of **LookingMetal** (iOS & macOS pure Apple Metal port, adaptive touch controls architecture, native UIKit menus, LiveContainer optimization, and packaging).

## ❤️ Credits & Acknowledgements

- The [LookingGlass](https://github.com/looking-glass-project/LookingGlass) project contributors for the modern Rust port of the Alice engine.
- American McGee and Rogue Entertainment for the gothic masterpiece.
