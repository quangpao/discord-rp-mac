// Renders the app icon (1024×1024 PNG) using AppKit + an SF Symbol.
// Usage: swift scripts/render-icon.swift <output.png>
import AppKit

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
let side: CGFloat = 1024

let image = NSImage(size: NSSize(width: side, height: side))
image.lockFocus()

// Rounded-square plate with a vertical gradient.
let inset = side * 0.06
let plate = NSRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
let radius = plate.width * 0.2237
let platePath = NSBezierPath(roundedRect: plate, xRadius: radius, yRadius: radius)
let gradient = NSGradient(colors: [
    NSColor(srgbRed: 0.13, green: 0.16, blue: 0.26, alpha: 1),
    NSColor(srgbRed: 0.06, green: 0.08, blue: 0.14, alpha: 1),
])
gradient?.draw(in: platePath, angle: -90)

// A thin accent rim so the plate reads on a light background too.
NSColor(srgbRed: 0.36, green: 0.42, blue: 0.98, alpha: 0.55).setStroke()
platePath.lineWidth = side * 0.008
platePath.stroke()

// Tinted SF Symbol.
func tintedSymbol(_ name: String, pointSize: CGFloat, color: NSColor) -> NSImage? {
    guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil),
          let symbol = base.withSymbolConfiguration(
              NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
          ) else { return nil }
    let tinted = NSImage(size: symbol.size)
    tinted.lockFocus()
    symbol.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
    color.set()
    NSRect(origin: .zero, size: symbol.size).fill(using: .sourceAtop)
    tinted.unlockFocus()
    return tinted
}

let accent = NSColor(srgbRed: 0.45, green: 0.53, blue: 1.0, alpha: 1)
if let bolt = tintedSymbol("bolt.horizontal.circle.fill", pointSize: side * 0.52, color: accent) {
    let origin = NSPoint(
        x: (side - bolt.size.width) / 2,
        y: (side - bolt.size.height) / 2
    )
    bolt.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("failed to render icon\n".utf8))
    exit(1)
}
try png.write(to: URL(fileURLWithPath: output))
print("wrote \(output) (\(rep.pixelsWide)×\(rep.pixelsHigh))")
