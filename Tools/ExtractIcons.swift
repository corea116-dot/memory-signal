import AppKit

let args = CommandLine.arguments
guard args.count == 3, let image = NSImage(contentsOfFile: args[1]),
      let tiff = image.tiffRepresentation,
      let source = NSBitmapImageRep(data: tiff) else {
    fatalError("Usage: ExtractIcons source.png output-directory")
}
let directory = URL(fileURLWithPath: args[2], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
let names = ["normal", "warning", "critical"]
var bounds: [CGRect] = []
for index in 0..<3 {
    var minX = source.pixelsWide, minY = source.pixelsHigh, maxX = 0, maxY = 0
    for y in 0..<source.pixelsHigh {
        for x in (index * source.pixelsWide / 3)..<((index + 1) * source.pixelsWide / 3) {
            guard let color = source.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
            let channels = [color.redComponent, color.greenComponent, color.blueComponent]
            if (channels.max() ?? 0) - (channels.min() ?? 0) > 0.12 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
    }
    guard maxX > minX, maxY > minY else { fatalError("Icon missing: \(index)") }
    bounds.append(CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))
}
let side = Int(bounds.map { max($0.width, $0.height) }.max() ?? 224) + 16
for (index, box) in bounds.enumerated() {
    guard let output = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: side * 4, bitsPerPixel: 32),
        let bytes = output.bitmapData else { fatalError("Bitmap allocation failed") }
    memset(bytes, 0, side * side * 4)
    for y in Int(box.minY)..<Int(box.maxY) {
        for x in Int(box.minX)..<Int(box.maxX) {
            guard let c = source.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
            let low = min(c.redComponent, c.greenComponent, c.blueComponent)
            let high = max(c.redComponent, c.greenComponent, c.blueComponent)
            guard high - low > 0.08 else { continue }
            let alpha = 1 - low
            let color = NSColor(deviceRed: (c.redComponent - low) / alpha,
                green: (c.greenComponent - low) / alpha, blue: (c.blueComponent - low) / alpha,
                alpha: alpha)
            output.setColor(color, atX: x - Int(box.minX) + (side - Int(box.width)) / 2,
                y: y - Int(box.minY) + side - 8 - Int(box.height))
        }
    }
    guard let png = output.representation(using: .png, properties: [:]) else { fatalError("PNG encoding failed") }
    try png.write(to: directory.appendingPathComponent(names[index] + ".png"))
    print("\(names[index]): source=\(box), transparent canvas=\(side)x\(side)")
}
