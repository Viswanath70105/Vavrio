#!/bin/sh
set -eu

usage() {
    printf '%s\n' 'Usage: sh Scripts/package-app.sh [--local-manifest-libs]' \
        'Builds the current development app with two jobs and creates a fresh' \
        'ad-hoc-signed Vavrio.app under ignored .build/app-packages output.' \
        'Uses existing Apple tools; does not install, launch, or replace an app.'
}

case "$#" in
    0) ;;
    1)
        case "$1" in
            --local-manifest-libs) ;;
            --help|-h) usage; exit 0 ;;
            *) usage >&2; exit 2 ;;
        esac
        ;;
    *) usage >&2; exit 2 ;;
esac

repository_root=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
cd "$repository_root"

icon_source="$repository_root/Assets/VavrioIcon-minimal-dark.png"
plist_source="$repository_root/Resources/Info.plist"
test -f "$icon_source"
/usr/bin/plutil -lint "$plist_source"

sh "$repository_root/Scripts/build.sh" "$@"

# Each invocation owns a fresh directory: no previous bundle is deleted or merged.
mkdir -p "$repository_root/.build/app-packages"
package_directory=$(mktemp -d "$repository_root/.build/app-packages/package.XXXXXX")
bundle="$package_directory/Vavrio.app"
iconset="$package_directory/Vavrio.iconset"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources" "$iconset"

cp "$plist_source" "$bundle/Contents/Info.plist"
cp "$repository_root/.build/debug/Vavrio" "$bundle/Contents/MacOS/Vavrio"
chmod 755 "$bundle/Contents/MacOS/Vavrio"

# ICNS includes standard and Retina representations, through 512 points at 2x.
for size in 16 32 128 256 512; do
    retina_size=$((size * 2))
    /usr/bin/sips -z "$size" "$size" "$icon_source" \
        --out "$iconset/icon_${size}x${size}.png" >/dev/null
    /usr/bin/sips -z "$retina_size" "$retina_size" "$icon_source" \
        --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
/usr/bin/iconutil -c icns "$iconset" -o "$bundle/Contents/Resources/VavrioFull.icns"

# Local development signature only: no certificate, identity, or notarization.
/usr/bin/codesign --force --sign - --timestamp=none "$bundle"
/usr/bin/codesign --verify --strict --verbose=2 "$bundle"
/usr/bin/plutil -lint "$bundle/Contents/Info.plist"

printf '\nPackaged app: %s\n' "$bundle"
printf 'Launch locally: open "%s"\n' "$bundle"
printf '%s\n' 'For local installation, quit Vavrio and copy this bundle to Applications.' \
    'Review any existing installation before replacing it. This script never installs automatically.'
