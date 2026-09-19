// Compose PNG frames into an animated GIF (ImageIO) — no external tools needed.
// Usage: swift scripts/frames-to-gif.swift <frames-dir> <out.gif> [fps]
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count > 2 else {
    FileHandle.standardError.write(Data("usage: frames-to-gif.swift <frames-dir> <out.gif> [fps]\n".utf8))
    exit(1)
}
let directory = URL(fileURLWithPath: args[1])
let output = URL(fileURLWithPath: args[2])
let fps = args.count > 3 ? Double(args[3]) ?? 15 : 15

let frames = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
    .filter { $0.lastPathComponent.hasPrefix("frame-") && $0.pathExtension == "png" }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }

guard let first = frames.first,
      let source = CGImageSourceCreateWithURL(first as CFURL, nil),
      let firstImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    FileHandle.standardError.write(Data("no frames found in \(directory.path)\n".utf8))
    exit(1)
}

try? FileManager.default.removeItem(at: output)
guard let destination = CGImageDestinationCreateWithURL(
    output as CFURL, UTType.gif.identifier as CFString, frames.count, nil
) else {
    FileHandle.standardError.write(Data("cannot create GIF destination\n".utf8))
    exit(1)
}

CGImageDestinationSetProperties(destination, [
    kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0],  // 0 = loop forever
] as CFDictionary)

let frameDelay = 1.0 / fps
for frame in frames {
    guard let frameSource = CGImageSourceCreateWithURL(frame as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(frameSource, 0, nil) else { continue }
    CGImageDestinationAddImage(destination, image, [
        kCGImagePropertyGIFDictionary: [
            kCGImagePropertyGIFDelayTime: frameDelay,
            kCGImagePropertyGIFUnclampedDelayTime: frameDelay,
        ],
    ] as CFDictionary)
}

guard CGImageDestinationFinalize(destination) else {
    FileHandle.standardError.write(Data("failed to write GIF\n".utf8))
    exit(1)
}

let size = (try? FileManager.default.attributesOfItem(atPath: output.path)[.size] as? Int) ?? 0
print("wrote \(output.path): \(frames.count) frames, \(Int(firstImage.width))×\(Int(firstImage.height)), \((size ?? 0) / 1024) KB, \(fps) fps")
