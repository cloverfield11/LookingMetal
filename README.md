# 🪞 LookingMetal

> **Native Apple Metal port of American McGee's Alice (2000) for iOS and Apple Silicon macOS.**

[![Platform](https://img.shields.io/badge/Platforms-iOS%2015%2B%20%7C%20macOS%20ARM-blue.svg)](https://apple.com)
[![Graphics](https://img.shields.io/badge/Graphics-Apple%20Metal%203-orange.svg)](https://developer.apple.com/metal/)
[![Engine](https://img.shields.io/badge/Language-Rust-red.svg)](https://www.rust-lang.org)
[![Framerate](https://img.shields.io/badge/Display-120%20FPS%20ProMotion-brightgreen.svg)]()

**LookingMetal** is a specialized fork of [LookingGlass](https://github.com/LookingGlass), engineered to bring **American McGee's Alice** natively to modern Apple hardware (iPhone, iPad, and Apple Silicon Macs) using **Apple Metal 3**.

No x86 emulation, UTM virtual machines, or translation layers — this is a pure native `aarch64` port running at a smooth **120 FPS on ProMotion** displays.

---

## ✨ Features

- ⚡️ **Native Metal 3 Graphics:** Direct hardware acceleration on Apple A-series and M-series chips.
- 📱 **Smooth 120 FPS (ProMotion):** Fully supports high-refresh displays (iPhone 13 Pro and newer, iPad Pro, MacBook Pro).
- 🎮 **Full Virtual Controller (Xbox / Nintendo Switch Layout):**
  - **Left Analog Stick (L):** 360° locomotion with a floating/dynamic center under your thumb.
  - **Right Analog Stick (R):** Continuous 360° camera panning with quadratic acceleration curve.
  - **Free Swipe Aiming:** Drag anywhere on the empty right half of the screen for precision view adjustments.
  - **ABXY Diamond:** `A` — Jump / Climb, `X` — Primary Attack, `B` — Alternate Attack, `Y` — Interact / Use (Key `E`).
  - **D-Pad:** Next and previous weapon cycling.
  - **Triggers & Bumpers:** `LT` / `RT` (Attacks), `LB` (Run / Walk toggle), `RB` (Next weapon).
  - **System Buttons:** `+` (Menu / Pause / Esc), `-` (Cheshire Cat hint / C).
  - **Hardware Multitouch:** Independent touch pointer tracking allows moving, aiming, and jumping at the same time.
- 🕹️ **Physical Controller Support:** Native Apple `GameController.framework` bridge. Connecting an Xbox, PS5 DualSense, Switch Pro, Backbone, or Razer Kishi controller automatically hides on-screen touch buttons.
- ⚙️ **Touch-Friendly Pre-Game Launcher:**
  - Target Frame Rate (60 FPS / 120 FPS ProMotion / 30 FPS Power Save).
  - Metal Performance HUD toggle.
  - Aspect Ratio (Fullscreen 19.5:9 / 16:9 Widescreen / 4:3 Classic).
  - Controller Mode (Touch + Physical / Physical Controller Only).
  - On-Screen Button Scale (Large 125% / Standard 100% / Huge 150%).
- 🎬 **Dedicated Cutscene Skip Button:** Accidental screen taps will not skip story sequences. Skipping requires pressing the prominent `[ SKIP >> ]` on-screen button or holding controller A / Enter.
- 📦 **Sideloading Ready:** Mach-O header automatically patched to SDK 16.5, eliminating dyld crashes in **LiveContainer**, **TrollStore**, **AltStore**, and **SideStore**.

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

### 2. Build for iPhone & iPad (IPA)
Run:
```bash
./build.sh ios
```
The script will automatically:
1. Verify and install any missing Rust components (`aarch64-apple-ios`).
2. Compile the release binary.
3. Patch the Mach-O SDK header for LiveContainer compatibility.
4. Generate application icons and `Info.plist`.
5. Package the game data and apply ad-hoc codesigning.
6. Output the signed package:
   - `dist/Alice_LookingMetal_iOS.ipa` (also mirrored to `~/Downloads/`).

Install the generated `.ipa` using **LiveContainer**, **TrollStore**, **AltStore**, or your preferred sideloading method.

---

### 3. macOS Native Build & Testing

- **Run natively on macOS (Keyboard + Mouse):**
  ```bash
  ./build.sh run
  ```
  *Controls: WASD — Move, Mouse — Look around, Space — Jump, Left/Right Click — Attacks, Tab — Level Select, P — Pause/Release Cursor.*

- **Run on macOS in Mobile Touch Simulation Mode:**
  ```bash
  ./build.sh run-touch
  ```
  *Opens the mobile launcher and displays the on-screen Xbox/Switch virtual controls for rapid UI testing on desktop.*

- **Build standalone macOS Application (`.app`):**
  ```bash
  ./build.sh mac
  ```

---

## 📁 Repository Structure

```text
LookingMetal/
├── build.sh                  # All-in-one build and packaging script
├── Cargo.toml                # Rust package definition
├── base/                     # Directory for Alice game data (*.pk3)
├── ios/
│   ├── Info.plist            # iOS Application manifest
│   └── AppIcon.png           # High-resolution application master icon
├── dist/                     # Generated release packages (.ipa / .app)
├── third_party/
│   └── miniquad/             # Patched Miniquad engine (multitouch & 120 FPS fixes)
├── src/
│   ├── launcher.rs           # Pre-game settings launcher
│   ├── touch_gamepad.rs      # Virtual controller subsystem
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

## ❤️ Credits

- The [LookingGlass](https://github.com/LookingGlass) project contributors for the modern Rust port of the Alice engine.
- The Nintendo Switch homebrew port creators for assets and inspiration.
- American McGee and Rogue Entertainment for the gothic masterpiece.
