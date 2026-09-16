#!/bin/bash
#
# Build a .deb package for Wordwise on Linux.
#
# Usage:
#   ./build_deb.sh
#
# Output:
#   build/wordwise_0.1.0_amd64.deb

set -e

# --- Paths ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
APP_DIR="$PROJECT_ROOT/app"
BUNDLE_DIR="$APP_DIR/build/linux/x64/release/bundle"
BUILD_DIR="$SCRIPT_DIR/build"
PKG_NAME="wordwise"
VERSION="0.1.0"
ARCH="amd64"
PKG_DIR="$BUILD_DIR/${PKG_NAME}_${VERSION}_${ARCH}"

echo "[1/7] Building flutter release..."
cd "$APP_DIR"
flutter build linux --release

echo "[2/7] Cleaning build dir..."
rm -rf "$BUILD_DIR"

echo "[3/7] Creating package structure..."
mkdir -p "$PKG_DIR/DEBIAN"
mkdir -p "$PKG_DIR/usr/bin"
mkdir -p "$PKG_DIR/usr/lib/$PKG_NAME"
mkdir -p "$PKG_DIR/usr/share/applications"
mkdir -p "$PKG_DIR/usr/share/icons/hicolor/256x256/apps"
mkdir -p "$PKG_DIR/usr/share/icons/hicolor/512x512/apps"

echo "[4/7] Copying app bundle..."
cp -r "$BUNDLE_DIR/"* "$PKG_DIR/usr/lib/$PKG_NAME/"

echo "[5/7] Creating launcher and copying files..."
# launcher script
cat > "$PKG_DIR/usr/bin/$PKG_NAME" <<EOF
#!/bin/sh
exec /usr/lib/$PKG_NAME/$PKG_NAME "\$@"
EOF
chmod +x "$PKG_DIR/usr/bin/$PKG_NAME"

# control and desktop entry
cp "$SCRIPT_DIR/control" "$PKG_DIR/DEBIAN/control"
cp "$SCRIPT_DIR/wordwise.desktop" "$PKG_DIR/usr/share/applications/"

echo "[6/7] Generating icons..."
ICON_SRC="$APP_DIR/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png"
magick "$ICON_SRC" -resize 256x256 "$PKG_DIR/usr/share/icons/hicolor/256x256/apps/$PKG_NAME.png"
magick "$ICON_SRC" -resize 512x512 "$PKG_DIR/usr/share/icons/hicolor/512x512/apps/$PKG_NAME.png"

echo "[7/7] Building .deb..."
cd "$BUILD_DIR"
dpkg-deb --build --root-owner-group "$PKG_DIR"

echo
echo "Done!"
echo "Package: $BUILD_DIR/${PKG_NAME}_${VERSION}_${ARCH}.deb"
echo
echo "To install:"
echo "  sudo dpkg -i $BUILD_DIR/${PKG_NAME}_${VERSION}_${ARCH}.deb"
echo
echo "To remove:"
echo "  sudo dpkg -r $PKG_NAME"
