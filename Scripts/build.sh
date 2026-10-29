#!/bin/sh
set -eu

usage() {
    printf '%s\n' 'Usage: sh Scripts/build.sh [--local-manifest-libs]' \
        'Builds Vavrio with two jobs using the selected Apple toolchain.' \
        'The optional workaround copies existing SwiftPM libraries into .build' \
        'and excludes private interfaces from that copy. Nothing is installed.'
}

use_local_libraries=false
case "$#" in
    0) ;;
    1)
        case "$1" in
            --local-manifest-libs) use_local_libraries=true ;;
            --help|-h) usage; exit 0 ;;
            *) usage >&2; exit 2 ;;
        esac
        ;;
    *) usage >&2; exit 2 ;;
esac

repository_root=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
cd "$repository_root"

if [ "$use_local_libraries" = true ]; then
    compiler_path=$(xcrun --find swiftc)
    toolchain_usr=$(dirname "$(dirname "$compiler_path")")
    installed_libraries="$toolchain_usr/lib/swift/pm"
    local_libraries="$repository_root/.build/swiftpm-local-libs"

    for name in ManifestAPI PluginAPI; do
        if [ ! -d "$installed_libraries/$name" ]; then
            printf 'Expected SwiftPM library directory is missing: %s\n' "$installed_libraries/$name" >&2
            exit 1
        fi
        mkdir -p "$local_libraries/$name"
        # Refresh the disposable copy; never edit the installed toolchain.
        /usr/bin/rsync -ac --exclude='*.private.swiftinterface' \
            "$installed_libraries/$name/" "$local_libraries/$name/"
    done

    printf '%s\n' 'Building with a local copy of the installed SwiftPM libraries.'
    SWIFTPM_CUSTOM_LIBS_DIR="$local_libraries" xcrun swift build --jobs 2
else
    xcrun swift build --jobs 2
fi

printf 'Run Vavrio: "%s/.build/debug/Vavrio"\n' "$repository_root"
