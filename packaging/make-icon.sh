#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Generate AppIcon.icns from one 1024px master drawn in code. No design tool needed.

WORK="$(mktemp -d)"
MASTER="$WORK/icon-1024.png"

cat > "$WORK/render.swift" <<'SWIFT'
import AppKit

let size = 1024
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

// Rounded square with a warm gradient (clay orange -> deep brown).
let rect = CGRect(x: 0, y: 0, width: size, height: size).insetBy(dx: 100, dy: 100)
let radius = rect.width * 0.2237
ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
ctx.clip()
let colors = [
    CGColor(red: 0.85, green: 0.47, blue: 0.34, alpha: 1),
    CGColor(red: 0.36, green: 0.16, blue: 0.10, alpha: 1),
] as CFArray
let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: rect.maxY), end: CGPoint(x: 0, y: rect.minY), options: [])

// White swap arrows: the mark the menu bar shows.
var cfg = NSImage.SymbolConfiguration(pointSize: CGFloat(size) * 0.36, weight: .semibold)
cfg = cfg.applying(.init(paletteColors: [.white]))
if let cup = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil)?
    .withSymbolConfiguration(cfg) {
    cup.isTemplate = false
    let s = cup.size
    cup.draw(at: NSPoint(x: (CGFloat(size) - s.width) / 2, y: (CGFloat(size) - s.height) / 2),
             from: NSRect(origin: .zero, size: s), operation: .sourceOver, fraction: 1)
}
img.unlockFocus()

guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
SWIFT

swift "$WORK/render.swift" "$MASTER"

ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"
gen() { sips -z "$2" "$2" "$MASTER" --out "$ICONSET/$1" >/dev/null; }
gen "icon_16x16.png" 16
gen "icon_16x16@2x.png" 32
gen "icon_32x32.png" 32
gen "icon_32x32@2x.png" 64
gen "icon_128x128.png" 128
gen "icon_128x128@2x.png" 256
gen "icon_256x256.png" 256
gen "icon_256x256@2x.png" 512
gen "icon_512x512.png" 512
gen "icon_512x512@2x.png" 1024

iconutil -c icns "$ICONSET" -o packaging/AppIcon.icns
mkdir -p docs && sips -Z 256 "$MASTER" --out docs/icon.png >/dev/null
rm -rf "$WORK"
echo "Generated packaging/AppIcon.icns"
