# 🪞 LookingMetal

> **Native Apple Metal port of American McGee's Alice (2000) for iOS and Apple Silicon macOS.**

[![Platform](https://img.shields.io/badge/Platforms-iOS%2015%2B%20%7C%20macOS%20ARM-blue.svg)](https://apple.com)
[![Status](https://img.shields.io/badge/Status-Fully%20Playable%20%26%20Rock%20Solid-success.svg)]()
[![Graphics](https://img.shields.io/badge/Graphics-Apple%20Metal%20%26%20MetalKit-orange.svg)](https://developer.apple.com/metal/)
[![Engine](https://img.shields.io/badge/Language-Rust-red.svg)](https://www.rust-lang.org)
[![Framerate](https://img.shields.io/badge/Display-120%20FPS%20ProMotion-brightgreen.svg)]()

**LookingMetal** is a specialized fork of [LookingGlass](https://github.com/looking-glass-project/LookingGlass), engineered to bring **American McGee's Alice** natively to modern Apple hardware (iPhone, iPad, and Apple Silicon Macs) using **Native Apple Metal & MetalKit**.

No x86 emulation, UTM virtual machines, or translation layers — this is a pure native `aarch64` port running at a buttery-smooth **120 FPS on ProMotion** displays with 100% stability.

---

## ✨ Features

- ⚡️ **Native Apple Metal Graphics:** Direct hardware acceleration via Apple MetalKit on A-series and M-series chips.
- 📱 **Smooth 120 FPS (ProMotion):** Fully supports high-refresh displays (iPhone 13 Pro through iPhone 16 Pro Max, iPad Pro, MacBook Pro).
- 🛡️ **Rock-Solid Stability (LiveContainer & Sideloading Optimized):**
  - **Zero Stack Overflow Guarantees:** All massive world and level structs (`Scene`, `Interactions`, `Npcs`, `LevelArt`, `Story`, `Hints`) are safely heap-allocated (`Box<T>`), completely bypassing iOS's strict 1008 KB Thread 0 stack guard limit. Dialogue choices, cutscenes, and level transitions run flawlessly without crashing.
  - **Apple System `zlib` Acceleration:** Fast, hardware-accelerated asset decompression via Apple's native `/usr/lib/libz.dylib`, freeing stack memory and maximizing performance.
- 🎮 **Polished Mobile Controls (Ergonomic Platformer HUD):**
  - **Left Analog Stick (MOVE):** 360° locomotion with a dynamic floating center under your thumb. Natural analog speed control: gentle tilt walks calmly at classic pace, firm tilt sprints forward.
  - **Right-Screen Camera Swipes:** The entire right side of the screen is open for natural, fluid camera rotation (no rigid right stick cluttering the screen).
  - **Adaptive Screen Scaling:** Perfectly sized buttons on all display densities, from standard screens to iPhone 16 Pro Max Retina displays.
  - **Monochromatic Frosted Glass Buttons:** Highly translucent, elegant minimalist glass controls with bespoke vector icons:
    - 🥾 **JUMP:** Large button positioned low in the bottom-right corner directly under the resting thumb for effortless platforming.
    - 🗡️ **SLASH:** Vorpal Blade primary attack placed right beside Jump for seamless thumb rolling.
    - 🎯 **THROW:** Flying dagger projectile attack.
    - ✋ **USE:** Action / Interact (Key `E`: levers, doors, dialogue).
    - 🔄 **SWAP:** Circular weapon cycling placed at the top arc.
  - **Zero Accidental Actions:** Clean touch discrimination prevents false attacks or jumps while panning the camera.
- 🖱️ **Full Touchpad Menu Navigation:**
  - Swipe anywhere on the screen like a laptop trackpad to glide the Alice cursor across menus with natural momentum.
  - Tap anywhere to click hovered items, or tap directly on menu buttons.
  - In-game escape menu includes a prominent one-touch `[ << RESUME GAME ]` return button.
- 🕹️ **Physical Controller Support:** Native Apple `GameController.framework` bridge. Connecting an Xbox, PS5 DualSense, Switch Pro, Backbone, or Razer Kishi controller automatically hides on-screen touch buttons.
- 🎬 **Prominent Bottom-Center Cutscene Skip Button:** Accidental screen taps will not skip story sequences. A large, convenient `[ SKIP >> ]` button is placed at the bottom center of the display.
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

#### Optional: Russian Localization (SoftClub) / Русская озвучка
If you want to play with the legendary Russian voice acting and translated text from SoftClub:
- Simply also add `pak6_RuSound.pk3`, `pak6_RuText.pk3`, and `pak6_RuTextures.pk3` into `base/`.
- LookingMetal will automatically detect and load them. You can switch or confirm language directly in the launcher!

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

## 👨‍💻 Author & Maintainer

- **Igor Gaponenko** ([@cloverfield11](https://github.com/cloverfield11)) — Creator and lead developer of **LookingMetal** (iOS & macOS ARM Apple Metal port, touch controls architecture, 120 FPS ProMotion integration, and standalone packaging).

## ❤️ Credits & Acknowledgements

- The [LookingGlass](https://github.com/looking-glass-project/LookingGlass) project contributors for the modern Rust port of the Alice engine.
- The Nintendo Switch homebrew port creators for assets and inspiration.
- American McGee and Rogue Entertainment for the gothic masterpiece.
