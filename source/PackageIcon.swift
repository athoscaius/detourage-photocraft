// Native macOS icon template: fully opaque art, transparent exterior only.
import AppKit
import Foundation
guard CommandLine.arguments.count == 3,
      let artwork = NSImage(contentsOfFile: CommandLine.arguments[1]),
      let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
          bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
          colorSpaceName: .deviceRGB, bytesPerRow: 4096, bitsPerPixel: 32),
      let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fputs("Impossible de préparer l’icône.\n", stderr); exit(1)
}
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphics
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let outline = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
outline.addClip()
NSColor(srgbRed: 216.0/255.0, green: 109.0/255.0, blue: 53.0/255.0, alpha: 1).setFill()
outline.fill()
artwork.draw(in: tile, from: .zero, operation: .sourceOver, fraction: 1,
             respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
NSGraphicsContext.restoreGraphicsState()
guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Impossible d’encoder l’icône.\n", stderr); exit(1)
}
do { try png.write(to: URL(fileURLWithPath: CommandLine.arguments[2]), options: .atomic) }
catch { fputs("Écriture de l’icône impossible : \(error.localizedDescription)\n", stderr); exit(1) }
