// Builds a multi-resolution .icns from a square source PNG.
// Usage: makeicon <source.png> <output.icns>
//
// The icns container is a 'icns' header followed by typed chunks, each holding a
// whole PNG. Writing it directly avoids sips/iconutil, which need scratch space
// outside this sandbox.
import CoreGraphics
import Foundation
import ImageIO

struct Variant {
    let type: String
    let pixels: Int
}

/// Chunk types macOS reads today: one per size class, including the @2x renderings.
let variants = [
    Variant(type: "icp4", pixels: 16),
    Variant(type: "icp5", pixels: 32),
    Variant(type: "ic11", pixels: 32),
    Variant(type: "ic12", pixels: 64),
    Variant(type: "ic07", pixels: 128),
    Variant(type: "ic13", pixels: 256),
    Variant(type: "ic08", pixels: 256),
    Variant(type: "ic14", pixels: 512),
    Variant(type: "ic09", pixels: 512),
    Variant(type: "ic10", pixels: 1024),
]

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write("Usage: makeicon <source.png> <output.icns>\n".data(using: .utf8)!)
    exit(1)
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write("\(message)\n".data(using: .utf8)!)
    exit(1)
}

let sourceURL = URL(fileURLWithPath: arguments[1])
let outputURL = URL(fileURLWithPath: arguments[2])

guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
      let original = CGImageSourceCreateImageAtIndex(source, 0, nil)
else {
    fail("Kunde inte läsa \(sourceURL.path)")
}

func resized(_ image: CGImage, to size: Int) -> CGImage? {
    guard let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }

    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
    return context.makeImage()
}

func pngData(_ image: CGImage) -> Data? {
    let buffer = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(
        buffer, "public.png" as CFString, 1, nil)
    else { return nil }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { return nil }
    return buffer as Data
}

func bigEndian(_ value: Int) -> Data {
    withUnsafeBytes(of: UInt32(value).bigEndian) { Data($0) }
}

var body = Data()
for variant in variants {
    guard let image = resized(original, to: variant.pixels),
          let png = pngData(image)
    else {
        fail("Kunde inte rendera \(variant.pixels)px")
    }
    body.append(variant.type.data(using: .ascii)!)
    body.append(bigEndian(png.count + 8))
    body.append(png)
}

var file = Data("icns".utf8)
file.append(bigEndian(body.count + 8))
file.append(body)

do {
    try file.write(to: outputURL)
} catch {
    fail("Kunde inte skriva \(outputURL.path): \(error.localizedDescription)")
}

print("Ikon byggd: \(outputURL.path) (\(variants.count) storlekar, \(file.count / 1024) KB)")
