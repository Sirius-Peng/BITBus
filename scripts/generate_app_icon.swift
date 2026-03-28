import AppKit

struct IconVariant {
    let filename: String
    let pixels: Int
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? FileManager.default.currentDirectoryPath)
let variants: [IconVariant] = [
    .init(filename: "Icon-20.png", pixels: 20),
    .init(filename: "Icon-20@2x.png", pixels: 40),
    .init(filename: "Icon-20@2x-ipad.png", pixels: 40),
    .init(filename: "Icon-20@3x.png", pixels: 60),
    .init(filename: "Icon-29.png", pixels: 29),
    .init(filename: "Icon-29@2x.png", pixels: 58),
    .init(filename: "Icon-29@2x-ipad.png", pixels: 58),
    .init(filename: "Icon-29@3x.png", pixels: 87),
    .init(filename: "Icon-40.png", pixels: 40),
    .init(filename: "Icon-40@2x.png", pixels: 80),
    .init(filename: "Icon-40@2x-ipad.png", pixels: 80),
    .init(filename: "Icon-40@3x.png", pixels: 120),
    .init(filename: "Icon-60@2x.png", pixels: 120),
    .init(filename: "Icon-60@3x.png", pixels: 180),
    .init(filename: "Icon-76@2x.png", pixels: 152),
    .init(filename: "Icon-83.5@2x.png", pixels: 167),
    .init(filename: "Icon-1024.png", pixels: 1024)
]

try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

for variant in variants {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: variant.pixels,
        pixelsHigh: variant.pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!

    rep.size = NSSize(width: variant.pixels, height: variant.pixels)

    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    context.imageInterpolation = .high
    NSGraphicsContext.current = context

    let cg = context.cgContext
    cg.setAllowsAntialiasing(true)
    cg.setShouldAntialias(true)

    let size = CGFloat(variant.pixels)
    drawIcon(in: cg, size: size)

    NSGraphicsContext.restoreGraphicsState()

    let url = outputDirectory.appendingPathComponent(variant.filename)
    let data = rep.representation(using: .png, properties: [:])!
    try data.write(to: url)
}

func drawIcon(in context: CGContext, size: CGFloat) {
    let base: CGFloat = size / 1024.0
    let rect = CGRect(x: 0, y: 0, width: size, height: size)

    let bgPath = NSBezierPath(roundedRect: rect, xRadius: 224 * base, yRadius: 224 * base)
    bgPath.addClip()

    let bgGradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.05, green: 0.17, blue: 0.27, alpha: 1.0),
        NSColor(calibratedRed: 0.09, green: 0.45, blue: 0.53, alpha: 1.0),
        NSColor(calibratedRed: 0.98, green: 0.55, blue: 0.23, alpha: 1.0)
    ])!
    bgGradient.draw(in: bgPath, angle: -55)

    let haloRect = CGRect(x: 120 * base, y: 160 * base, width: 780 * base, height: 780 * base)
    let haloPath = NSBezierPath(ovalIn: haloRect)
    let haloGradient = NSGradient(colors: [
        NSColor(calibratedWhite: 1.0, alpha: 0.20),
        NSColor(calibratedWhite: 1.0, alpha: 0.02)
    ])!
    haloGradient.draw(in: haloPath, relativeCenterPosition: NSPoint(x: -0.18, y: 0.24))

    let ticketPath = NSBezierPath()
    ticketPath.move(to: CGPoint(x: 246 * base, y: 724 * base))
    ticketPath.line(to: CGPoint(x: 560 * base, y: 724 * base))
    ticketPath.curve(to: CGPoint(x: 630 * base, y: 662 * base),
                     controlPoint1: CGPoint(x: 595 * base, y: 724 * base),
                     controlPoint2: CGPoint(x: 630 * base, y: 694 * base))
    ticketPath.line(to: CGPoint(x: 630 * base, y: 602 * base))
    ticketPath.line(to: CGPoint(x: 792 * base, y: 602 * base))
    ticketPath.line(to: CGPoint(x: 554 * base, y: 304 * base))
    ticketPath.line(to: CGPoint(x: 554 * base, y: 430 * base))
    ticketPath.line(to: CGPoint(x: 246 * base, y: 430 * base))
    ticketPath.close()
    NSColor(calibratedRed: 0.64, green: 0.95, blue: 0.92, alpha: 0.96).setFill()
    ticketPath.fill()

    let ticketCut = NSBezierPath(ovalIn: CGRect(x: 298 * base, y: 544 * base, width: 78 * base, height: 78 * base))
    NSColor(calibratedRed: 0.10, green: 0.38, blue: 0.44, alpha: 0.95).setFill()
    ticketCut.fill()

    let busBody = NSBezierPath(roundedRect: CGRect(x: 226 * base, y: 198 * base, width: 572 * base, height: 420 * base),
                               xRadius: 118 * base,
                               yRadius: 118 * base)
    NSColor(calibratedWhite: 0.98, alpha: 1.0).setFill()
    busBody.fill()

    let windshield = NSBezierPath(roundedRect: CGRect(x: 284 * base, y: 378 * base, width: 456 * base, height: 176 * base),
                                  xRadius: 62 * base,
                                  yRadius: 62 * base)
    NSColor(calibratedRed: 0.11, green: 0.25, blue: 0.35, alpha: 0.96).setFill()
    windshield.fill()

    let centerDivider = NSBezierPath(roundedRect: CGRect(x: 494 * base, y: 390 * base, width: 28 * base, height: 152 * base),
                                     xRadius: 14 * base,
                                     yRadius: 14 * base)
    NSColor(calibratedWhite: 0.92, alpha: 0.95).setFill()
    centerDivider.fill()

    for x in [332.0, 650.0] {
        let light = NSBezierPath(ovalIn: CGRect(x: CGFloat(x) * base, y: 276 * base, width: 58 * base, height: 58 * base))
        NSColor(calibratedRed: 0.98, green: 0.67, blue: 0.24, alpha: 1.0).setFill()
        light.fill()
    }

    let grille = NSBezierPath(roundedRect: CGRect(x: 386 * base, y: 282 * base, width: 252 * base, height: 34 * base),
                              xRadius: 17 * base,
                              yRadius: 17 * base)
    NSColor(calibratedRed: 0.19, green: 0.32, blue: 0.40, alpha: 0.95).setFill()
    grille.fill()

    let bumper = NSBezierPath(roundedRect: CGRect(x: 336 * base, y: 228 * base, width: 352 * base, height: 28 * base),
                              xRadius: 14 * base,
                              yRadius: 14 * base)
    NSColor(calibratedRed: 0.10, green: 0.23, blue: 0.30, alpha: 0.88).setFill()
    bumper.fill()

    for x in [348.0, 676.0] {
        let wheel = NSBezierPath(ovalIn: CGRect(x: CGFloat(x) * base, y: 144 * base, width: 96 * base, height: 96 * base))
        NSColor(calibratedRed: 0.10, green: 0.13, blue: 0.18, alpha: 1.0).setFill()
        wheel.fill()

        let hub = NSBezierPath(ovalIn: CGRect(x: (CGFloat(x) + 26) * base, y: 170 * base, width: 44 * base, height: 44 * base))
        NSColor(calibratedWhite: 0.95, alpha: 1.0).setFill()
        hub.fill()
    }

    let shinePath = NSBezierPath()
    shinePath.move(to: CGPoint(x: 258 * base, y: 836 * base))
    shinePath.curve(to: CGPoint(x: 514 * base, y: 948 * base),
                    controlPoint1: CGPoint(x: 320 * base, y: 922 * base),
                    controlPoint2: CGPoint(x: 424 * base, y: 968 * base))
    shinePath.line(to: CGPoint(x: 356 * base, y: 1018 * base))
    shinePath.curve(to: CGPoint(x: 174 * base, y: 906 * base),
                    controlPoint1: CGPoint(x: 286 * base, y: 1004 * base),
                    controlPoint2: CGPoint(x: 202 * base, y: 964 * base))
    shinePath.close()
    NSColor(calibratedWhite: 1.0, alpha: 0.14).setFill()
    shinePath.fill()

    context.resetClip()
}
