// Zeichnet das App-Symbol (Bildschirm mit </> auf einem Stativ) als 1024×1024-PNG.
// Aufruf: swift App/make-icon.swift <ziel.png>
import AppKit

let canvas: CGFloat = 1024
let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "AppIcon-1024.png")

let image = NSImage(size: NSSize(width: canvas, height: canvas), flipped: true) { _ in
    guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

    // Grundform nach Apples Raster: 824 px Kachel mit 100 px Rand.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let unit = tile.width / 290   // Maße unten stammen aus der 290 px breiten Vorlage
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: tile.minX + x * unit, y: tile.minY + y * unit) }

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 10), blur: 24, color: NSColor.black.withAlphaComponent(0.3).cgColor)
    let shape = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.addPath(shape)
    ctx.setFillColor(NSColor(red: 0.12, green: 0.16, blue: 0.40, alpha: 1).cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    // Leichter Verlauf von oben, damit die Fläche nicht stumpf wirkt.
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
        NSColor(red: 0.17, green: 0.22, blue: 0.50, alpha: 1).cgColor,
        NSColor(red: 0.10, green: 0.13, blue: 0.36, alpha: 1).cgColor
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: tile.minY), end: CGPoint(x: 0, y: tile.maxY), options: [])
    ctx.restoreGState()

    let white = NSColor.white.cgColor
    let teal = NSColor(red: 0.33, green: 0.78, blue: 0.80, alpha: 1).cgColor
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)

    // Bildschirm
    let screen = CGRect(origin: p(50, 70), size: CGSize(width: 180 * unit, height: 124 * unit))
    ctx.addPath(CGPath(roundedRect: screen, cornerWidth: 15 * unit, cornerHeight: 15 * unit, transform: nil))
    ctx.setStrokeColor(white)
    ctx.setLineWidth(12 * unit)
    ctx.strokePath()

    // < und >
    ctx.setLineWidth(17 * unit)
    ctx.setStrokeColor(white)
    ctx.addLines(between: [p(119, 108), p(92, 132), p(119, 156)])
    ctx.strokePath()
    ctx.setStrokeColor(teal)
    ctx.addLines(between: [p(161, 108), p(188, 132), p(161, 156)])
    ctx.strokePath()

    // Stativ
    ctx.setStrokeColor(white)
    ctx.setLineWidth(10 * unit)
    ctx.addLines(between: [p(140, 194), p(140, 238)])
    ctx.addLines(between: [p(140, 214), p(112, 238)])
    ctx.addLines(between: [p(140, 214), p(168, 238)])
    ctx.strokePath()
    return true
}

guard let tiff = image.tiffRepresentation,
      let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
    fatalError("PNG konnte nicht erzeugt werden")
}
try png.write(to: output)
print("Geschrieben: \(output.path)")
