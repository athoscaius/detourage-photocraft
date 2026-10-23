// Package user-supplied artwork unchanged, preserving its transparency.
import AppKit
import Foundation
guard CommandLine.arguments.count == 3,
      let artwork = NSImage(contentsOfFile: CommandLine.arguments[1]),
      let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
          bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
          colorSpaceName: .deviceRGB, bytesPerRow: 4096, bitsPerPixel: 32),
      let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else { exit(1) }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphics
graphics.cgContext.clear(CGRect(x:0,y:0,width:1024,height:1024))
let tile = NSRect(x:100,y:100,width:824,height:824)
artwork.draw(in:tile,from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,
             hints:[.interpolation:NSImageInterpolation.high])
NSGraphicsContext.restoreGraphicsState()
guard let png=bitmap.representation(using:.png,properties:[:]) else {exit(1)}
try png.write(to:URL(fileURLWithPath:CommandLine.arguments[2]),options:.atomic)
