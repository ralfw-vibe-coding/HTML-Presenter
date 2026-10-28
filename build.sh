#!/bin/zsh
# Baut "HTML Presenter.app" ohne Xcode-Projekt: swift build + App-Bündel von Hand.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/HTMLPresenter"
APP="build/HTML Presenter.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/HTMLPresenter"
cp App/Info.plist "$APP/Contents/Info.plist"
cp runtime/presentation.js "$APP/Contents/Resources/presentation.js"
# Das Symbol wird mit App/make-icon.swift gezeichnet; neu erzeugen nur, wenn es fehlt.
[[ -f App/AppIcon.icns ]] || {
    swift App/make-icon.swift App/AppIcon-1024.png
    rm -rf App/AppIcon.iconset && mkdir App/AppIcon.iconset
    for s in 16 32 128 256 512; do
        sips -z $s $s App/AppIcon-1024.png --out App/AppIcon.iconset/icon_${s}x${s}.png >/dev/null
        sips -z $((s*2)) $((s*2)) App/AppIcon-1024.png --out App/AppIcon.iconset/icon_${s}x${s}@2x.png >/dev/null
    done
    iconutil -c icns App/AppIcon.iconset -o App/AppIcon.icns && rm -rf App/AppIcon.iconset
}
cp App/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP" >/dev/null

echo "Fertig: $APP"
