#!/usr/bin/env bash
# ==============================================================================
#  LookingMetal — Native American McGee's Alice Port for iOS & macOS ARM
#  Unified Build & Packaging Script
# ==============================================================================

set -e

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

DIST_DIR="$ROOT_DIR/dist"
BASE_DIR="$ROOT_DIR/base"
IOS_DIR="$ROOT_DIR/ios"

# Colors
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

print_banner() {
    echo -e "${CYAN}"
    echo "======================================================================="
    echo "  LookingMetal — American McGee's Alice (Apple Metal Port)"
    echo "  Platforms: iOS (iPhone / iPad) & macOS ARM (Apple Silicon)"
    echo "======================================================================="
    echo -e "${NC}"
}

check_dependencies() {
    echo -e "${YELLOW}[*] Checking toolchain dependencies...${NC}"
    
    # 1. Check Rust / Cargo
    if ! command -v cargo &> /dev/null; then
        echo -e "${RED}[ERROR] Rust/Cargo is not installed!${NC}"
        echo "Please install Rust via: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
        exit 1
    fi

    # 2. Check Xcode Command Line Tools
    if ! command -v codesign &> /dev/null || ! command -v sips &> /dev/null; then
        echo -e "${RED}[ERROR] Xcode Command Line Tools not found!${NC}"
        echo "Please run: xcode-select --install"
        exit 1
    fi

    # 3. Check Python 3
    if ! command -v python3 &> /dev/null; then
        echo -e "${RED}[ERROR] Python 3 is required for Mach-O binary patching.${NC}"
        exit 1
    fi

    # 4. Check iOS ARM64 target
    if ! rustup target list --installed | grep -q "aarch64-apple-ios"; then
        echo -e "${YELLOW}[+] Adding missing Rust target: aarch64-apple-ios...${NC}"
        rustup target add aarch64-apple-ios
    fi

    echo -e "${GREEN}[✓] Toolchain dependencies are ready!${NC}"
}

check_assets() {
    echo -e "${YELLOW}[*] Checking game assets in $BASE_DIR...${NC}"
    mkdir -p "$BASE_DIR"

    PK3_COUNT=$(ls -1 "$BASE_DIR"/*.pk3 2>/dev/null | wc -l | tr -d ' ')
    if [ "$PK3_COUNT" -eq "0" ]; then
        echo -e "${YELLOW}[!] No .pk3 files found in $BASE_DIR.${NC}"
        
        # Check standard Downloads folder as fallback
        FALLBACK_DIR="/Users/igor/Downloads/American McGee's Alice (LookingGlass port) for Nintendo Switch [NSP]"
        if [ -d "$FALLBACK_DIR" ]; then
            echo -e "${GREEN}[+] Found assets in Downloads! Importing into base/...${NC}"
            cp "$FALLBACK_DIR/switch/LookingGlass/base/"*.pk3 "$BASE_DIR/" 2>/dev/null || true
            cp "$FALLBACK_DIR/Russian Language Mod/switch/LookingGlass/base/"*.pk3 "$BASE_DIR/" 2>/dev/null || true
        else
            echo -e "${RED}[ERROR] Game assets are missing!${NC}"
            echo "Please place pak0.pk3 .. pak5.pk3 (and optional pak6_Ru*.pk3) into:"
            echo "  $BASE_DIR/"
            exit 1
        fi
    fi

    echo -e "${GREEN}[✓] Found $(ls -1 "$BASE_DIR"/*.pk3 | wc -l | tr -d ' ') PK3 archive(s) in base/${NC}"
}

build_ios() {
    check_dependencies
    check_assets
    mkdir -p "$DIST_DIR"

    OUTPUT_IPA="$DIST_DIR/Alice_LookingMetal_iOS.ipa"
    DOWNLOADS_IPA="$HOME/Downloads/Alice_LookingMetal_iOS.ipa"

    echo -e "${CYAN}[+] Compiling release binary for aarch64-apple-ios (with 16MB stack)...${NC}"
    RUSTFLAGS="-C link-arg=-Wl,-stack_size,0x1000000" cargo build --release --target aarch64-apple-ios

    BIN_PATH="$ROOT_DIR/target/aarch64-apple-ios/release/looking-metal"
    if [ ! -f "$BIN_PATH" ]; then
        echo -e "${RED}[ERROR] Build failed, binary not found at $BIN_PATH${NC}"
        exit 1
    fi

    echo -e "${CYAN}[+] Patching Mach-O SDK version to 16.5 (LiveContainer compatibility)...${NC}"
    python3 -c "
with open('$BIN_PATH', 'rb') as f:
    data = bytearray(f.read())
import struct
idx = data.find(b'\x25\x00\x00\x00\x10\x00\x00\x00')
if idx != -1:
    ver, sdk = struct.unpack_from('<II', data, idx + 8)
    struct.pack_into('<II', data, idx + 8, ver, 0x00100500)
    with open('$BIN_PATH', 'wb') as f:
        f.write(data)
    print('    [✓] Patched LC_VERSION_MIN_IPHONEOS SDK -> 0x00100500 (iOS 16.5)')
else:
    print('    [i] Mach-O load command already valid.')
"

    echo -e "${CYAN}[+] Assembling iOS App Bundle (Payload/Alice.app)...${NC}"
    STAGING="$ROOT_DIR/target/ipa_staging"
    APP_DIR="$STAGING/Payload/Alice.app"
    rm -rf "$STAGING"
    mkdir -p "$APP_DIR/base"

    cp "$BIN_PATH" "$APP_DIR/Alice"
    chmod +x "$APP_DIR/Alice"
    cp "$IOS_DIR/Info.plist" "$APP_DIR/Info.plist"

    # App icons
    if [ -f "$IOS_DIR/AppIcon.png" ]; then
        sips -z 120 120 "$IOS_DIR/AppIcon.png" --out "$APP_DIR/AppIcon60x60@2x.png" >/dev/null 2>&1
        sips -z 180 180 "$IOS_DIR/AppIcon.png" --out "$APP_DIR/AppIcon60x60@3x.png" >/dev/null 2>&1
        sips -z 167 167 "$IOS_DIR/AppIcon.png" --out "$APP_DIR/AppIcon83.5x83.5@2x.png" >/dev/null 2>&1
        sips -z 152 152 "$IOS_DIR/AppIcon.png" --out "$APP_DIR/AppIcon76x76@2x.png" >/dev/null 2>&1
        cp "$IOS_DIR/AppIcon.png" "$APP_DIR/iTunesArtwork.png"
    fi

    echo -e "${CYAN}[+] Bundling PK3 archives into Alice.app/base/...${NC}"
    cp -v "$BASE_DIR"/*.pk3 "$APP_DIR/base/"

    echo -e "${CYAN}[+] Codesigning Payload/Alice.app (ad-hoc)...${NC}"
    codesign -s - --force --deep "$APP_DIR"

    echo -e "${CYAN}[+] Packaging IPA archive...${NC}"
    rm -f "$OUTPUT_IPA" "$DOWNLOADS_IPA"
    (cd "$STAGING" && zip -9 -q -r "$OUTPUT_IPA" Payload)
    cp "$OUTPUT_IPA" "$DOWNLOADS_IPA"
    rm -rf "$STAGING"

    echo -e "${GREEN}"
    echo "======================================================================="
    echo "  [SUCCESS] iOS IPA successfully packaged!"
    echo "  Artifact 1: $OUTPUT_IPA"
    echo "  Artifact 2: $DOWNLOADS_IPA"
    ls -lh "$OUTPUT_IPA"
    echo "======================================================================="
    echo -e "${NC}"
}

build_mac() {
    check_dependencies
    check_assets
    mkdir -p "$DIST_DIR"

    echo -e "${CYAN}[+] Compiling release binary for macOS Apple Silicon...${NC}"
    cargo build --release

    MAC_BIN="$ROOT_DIR/target/release/looking-metal"
    MAC_APP="$DIST_DIR/Alice_LookingMetal.app"
    rm -rf "$MAC_APP"
    mkdir -p "$MAC_APP/Contents/MacOS"
    mkdir -p "$MAC_APP/Contents/Resources/base"

    cp "$MAC_BIN" "$MAC_APP/Contents/MacOS/Alice"
    chmod +x "$MAC_APP/Contents/MacOS/Alice"
    cp -v "$BASE_DIR"/*.pk3 "$MAC_APP/Contents/Resources/base/"

    cat << 'EOF' > "$MAC_APP/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>American McGee's Alice</string>
    <key>CFBundleExecutable</key>
    <string>Alice</string>
    <key>CFBundleIdentifier</key>
    <string>org.lookingmetal.alice</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

    codesign -s - --force --deep "$MAC_APP"

    echo -e "${GREEN}"
    echo "======================================================================="
    echo "  [SUCCESS] macOS App Bundle created!"
    echo "  Path: $MAC_APP"
    echo "  Launch via: open '$MAC_APP'"
    echo "======================================================================="
    echo -e "${NC}"
}

run_mac() {
    check_assets
    echo -e "${CYAN}[+] Launching LookingMetal natively on macOS...${NC}"
    cargo run -- --data "$BASE_DIR"
}

run_touch() {
    check_assets
    echo -e "${CYAN}[+] Launching LookingMetal in Mobile Touch Simulation Mode...${NC}"
    cargo run -- --data "$BASE_DIR" --touch
}

clean() {
    echo -e "${YELLOW}[*] Cleaning build cache and targets...${NC}"
    cargo clean
    rm -rf "$DIST_DIR" "$ROOT_DIR/target/ipa_staging"
    echo -e "${GREEN}[✓] Clean completed!${NC}"
}

# --- Main CLI Router ---
print_banner

case "$1" in
    ios|ipa)
        build_ios
        ;;
    mac|app)
        build_mac
        ;;
    run)
        run_mac
        ;;
    run-touch|mobile)
        run_touch
        ;;
    setup)
        check_dependencies
        check_assets
        ;;
    clean)
        clean
        ;;
    *)
        echo "Usage: ./build.sh <command>"
        echo ""
        echo "Commands:"
        echo "  ./build.sh ios         Build and package iOS IPA (Alice_LookingMetal_iOS.ipa)"
        echo "  ./build.sh mac         Build macOS Apple Silicon App Bundle (Alice_LookingMetal.app)"
        echo "  ./build.sh run         Run game natively on macOS (Keyboard + Mouse)"
        echo "  ./build.sh run-touch   Run game on macOS simulating Mobile Touch Gamepad & Launcher"
        echo "  ./build.sh setup       Verify and install required build toolchains"
        echo "  ./build.sh clean       Clean build artifacts and caches"
        echo ""
        ;;
esac
