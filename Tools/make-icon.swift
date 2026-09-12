// Renders the 1024x1024 App Store icon.
// Usage: swift Tools/make-icon.swift <output.png>

import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

let side = 1024

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("make-icon: \(message)\n".utf8))
    exit(1)
}

guard CommandLine.arguments.count > 1 else {
    fail("usage: swift Tools/make-icon.swift <output.png>")
}
let outputPath = CommandLine.arguments[1]
let colorSpace = CGColorSpaceCreateDeviceRGB()

// noneSkipLast keeps the PNG free of an alpha channel; the App Store and
// TestFlight reject icons that carry one.
guard let ctx = CGContext(data: nil,
                          width: side,
                          height: side,
                          bitsPerComponent: 8,
                          bytesPerRow: 0,
                          space: colorSpace,
                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
    fail("could not create the \(side)x\(side) bitmap context")
}

let indigo = CGColor(srgbRed: 0.29, green: 0.35, blue: 0.95, alpha: 1)
let violet = CGColor(srgbRed: 0.55, green: 0.25, blue: 0.90, alpha: 1)
guard let gradient = CGGradient(colorsSpace: colorSpace,
                                colors: [indigo, violet] as CFArray,
                                locations: [0, 1]) else {
    fail("could not build the background gradient")
}
ctx.drawLinearGradient(gradient,
                       start: .zero,
                       end: CGPoint(x: side, y: side),
                       options: [])

let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 620, nil)
let attributes: [NSAttributedString.Key: Any] = [
    NSAttributedString.Key(kCTFontAttributeName as String): font,
    NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1)
]
let line = CTLineCreateWithAttributedString(NSAttributedString(string: "1", attributes: attributes))

// Optical bounds are relative to the text origin, so the origin offsets have to
// be subtracted back out to land the glyph dead centre on both axes.
let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
ctx.textPosition = CGPoint(x: (CGFloat(side) - bounds.width) / 2 - bounds.minX,
                           y: (CGFloat(side) - bounds.height) / 2 - bounds.minY)
CTLineDraw(line, ctx)

guard let image = ctx.makeImage() else {
    fail("could not snapshot the rendered context")
}

let url = URL(fileURLWithPath: outputPath)
guard let destination = CGImageDestinationCreateWithURL(url as CFURL,
                                                        UTType.png.identifier as CFString,
                                                        1,
                                                        nil) else {
    fail("could not open \(outputPath) for writing")
}
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else {
    fail("could not encode the PNG at \(outputPath)")
}

print(url.path)
