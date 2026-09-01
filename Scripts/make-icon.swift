import AppKit

// Renders AppIcon.iconset from code so the repo carries no binary assets.
// Dark squircle + the same SF Symbol used in the menu bar.

let sizes: [(px: Int, name: String)] = [
    (16, "icon_16x16"), (32, "icon_16x16@2x"),
    (32, "icon_32x32"), (64, "icon_32x32@2x"),
    (128, "icon_128x128"), (256, "icon_128x128@2x"),
    (256, "icon_256x256"), (512, "icon_256x256@2x"),
    (512, "icon_512x512"), (1024, "icon_512x512@2x")
]

let symbolName = ["powerplug.portrait.fill", "powerplug.fill", "network"]
    .first { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil } ?? "network"

let outputDirectory = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "./AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outputDirectory, withIntermediateDirectories: true)

for size in sizes {
    let side = CGFloat(size.px)
    let image = NSImage(size: NSSize(width: side, height: side))
    image.lockFocus()

    let inset = side * 0.055
    let rect = NSRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
    let squircle = NSBezierPath(roundedRect: rect, xRadius: side * 0.225, yRadius: side * 0.225)

    NSGradient(colors: [
        NSColor(calibratedRed: 0.16, green: 0.19, blue: 0.25, alpha: 1),
        NSColor(calibratedRed: 0.06, green: 0.07, blue: 0.10, alpha: 1)
    ])?.draw(in: squircle, angle: -90)

    squircle.lineWidth = max(1, side * 0.006)
    NSColor(calibratedWhite: 1, alpha: 0.10).setStroke()
    squircle.stroke()

    let glyphSide = side * 0.50
    let configuration = NSImage.SymbolConfiguration(pointSize: glyphSide, weight: .medium)
    if let glyph = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
        .withSymbolConfiguration(configuration) {
        let tinted = NSImage(size: glyph.size)
        tinted.lockFocus()
        NSColor(calibratedRed: 0.62, green: 0.88, blue: 0.72, alpha: 1).set()
        NSRect(origin: .zero, size: glyph.size).fill(using: .sourceOver)
        glyph.draw(at: .zero, from: NSRect(origin: .zero, size: glyph.size),
                   operation: .destinationIn, fraction: 1)
        tinted.unlockFocus()

        let target = NSRect(
            x: (side - tinted.size.width) / 2,
            y: (side - tinted.size.height) / 2,
            width: tinted.size.width,
            height: tinted.size.height
        )
        tinted.draw(in: target)
    }

    image.unlockFocus()

    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else { continue }
    bitmap.size = NSSize(width: side, height: side)
    try? png.write(to: URL(fileURLWithPath: "\(outputDirectory)/\(size.name).png"))
}
