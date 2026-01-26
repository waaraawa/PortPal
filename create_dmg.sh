#!/bin/bash

# Configuration
APP_NAME="PortPal"
SCHEME_NAME="PortPal"
BUILD_DIR="build"
# Check for version argument
if [ -z "$1" ]; then
    read -p "Enter version (e.g., 1.2.0): " VERSION
else
    VERSION=$1
fi

if [ -z "$VERSION" ]; then
    echo "Version is required!"
    exit 1
fi

DMG_NAME="${APP_NAME}.${VERSION}.dmg"
APP_PATH="${BUILD_DIR}/Build/Products/Release/${APP_NAME}.app"

# Clean build directory
rm -rf "${BUILD_DIR}"
rm -f "${DMG_NAME}"

# Build the application
echo "Building ${APP_NAME}..."
xcodebuild -scheme "${SCHEME_NAME}" \
    -configuration Release \
    -derivedDataPath "${BUILD_DIR}" \
    -destination 'platform=macOS' \
    clean build

if [ $? -ne 0 ]; then
    echo "Build failed"
    exit 1
fi

# Create a temporary folder for DMG content
DMG_SOURCE="dmg_source"
rm -rf "${DMG_SOURCE}"
mkdir -p "${DMG_SOURCE}"

# Copy app to source folder
echo "Copying app to DMG source..."
cp -R "${APP_PATH}" "${DMG_SOURCE}/"

# Create link to Applications folder
ln -s /Applications "${DMG_SOURCE}/Applications"

# Create DMG
echo "Creating DMG..."
hdiutil create -volname "${APP_NAME}" \
    -srcfolder "${DMG_SOURCE}" \
    -ov -format UDZO \
    "${DMG_NAME}"

# Clean up
rm -rf "${DMG_SOURCE}"
# rm -rf "${BUILD_DIR}"

echo "Done! Created ${DMG_NAME}"
