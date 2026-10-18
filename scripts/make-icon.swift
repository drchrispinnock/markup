// Makes a macOS .iconset from a square artwork PNG.
//
//   swift scripts/make-icon.swift <artwork.png> <output.iconset>
//
// The artwork is an opaque rounded square on a white background. The white
// that surrounds the shape is made transparent (edges are un-blended from
// white so they stay smooth), and the shape is fitted to the 824 x 824 icon
// outline that macOS uses on a 1024 x 1024 canvas.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <artwork.png> <output.iconset>\n".utf8))
    exit(2)
}
let inputURL = URL(fileURLWithPath: arguments[1])
let outputURL = URL(fileURLWithPath: arguments[2])

guard let source = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
      let artwork = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    FileHandle.standardError.write(Data("cannot read \(inputURL.path)\n".utf8))
    exit(1)
}

let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

func makeContext(width: Int, height: Int) -> CGContext {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                            space: colorSpace, bitmapInfo: bitmapInfo)!
    context.interpolationQuality = .high
    return context
}

// MARK: - Remove the white surround

let width = artwork.width, height = artwork.height
let canvas = makeContext(width: width, height: height)
canvas.draw(artwork, in: CGRect(x: 0, y: 0, width: width, height: height))
let pixels = canvas.data!.bindMemory(to: UInt8.self, capacity: width * height * 4)

func minChannel(_ index: Int) -> Int {
    min(Int(pixels[index * 4]), Int(pixels[index * 4 + 1]), Int(pixels[index * 4 + 2]))
}

// The background is the near-white region connected to the image's edges.
var isBackground = [Bool](repeating: false, count: width * height)
var stack: [Int] = []
for x in 0..<width { stack += [x, (height - 1) * width + x] }
for y in 0..<height { stack += [y * width, y * width + width - 1] }
while let index = stack.popLast() {
    guard !isBackground[index], minChannel(index) >= 200 else { continue }
    isBackground[index] = true
    let x = index % width, y = index / width
    if x > 0 { stack.append(index - 1) }
    if x < width - 1 { stack.append(index + 1) }
    if y > 0 { stack.append(index - width) }
    if y < height - 1 { stack.append(index + width) }
}

// Pixels near the background are the shape's anti-aliased edge: a blend of
// the shape's dark colour over white. Work out how much white each holds and
// take it out, leaving the shape's colour with partial alpha.
var isEdge = isBackground
for _ in 0..<4 {
    var grown = isEdge
    for index in 0..<(width * height) where !isEdge[index] {
        let x = index % width, y = index / width
        if (x > 0 && isEdge[index - 1]) || (x < width - 1 && isEdge[index + 1])
            || (y > 0 && isEdge[index - width]) || (y < height - 1 && isEdge[index + width]) {
            grown[index] = true
        }
    }
    isEdge = grown
}

let shapeDarkest = 24.0
for index in 0..<(width * height) {
    let offset = index * 4
    if isBackground[index] {
        for channel in 0..<4 { pixels[offset + channel] = 0 }
    } else if isEdge[index] {
        let white = max(0, min(1, (Double(minChannel(index)) - shapeDarkest) / (255 - shapeDarkest)))
        // observed = alpha * colour + white * 255, with alpha = 1 - white, and
        // premultiplied colour is alpha * colour.
        for channel in 0..<3 {
            pixels[offset + channel] = UInt8(max(0, Double(pixels[offset + channel]) - white * 255).rounded())
        }
        pixels[offset + 3] = UInt8(((1 - white) * 255).rounded())
    }
}

// MARK: - Fit the shape into the icon grid

var minX = width, minY = height, maxX = -1, maxY = -1
for index in 0..<(width * height) where pixels[index * 4 + 3] > 8 {
    let x = index % width, y = index / width
    minX = min(minX, x); maxX = max(maxX, x)
    minY = min(minY, y); maxY = max(maxY, y)
}
let cutOut = canvas.makeImage()!.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))!

// macOS 26 shows an icon as is only if its outline is the standard rounded
// rectangle: 824 x 824 at (100, 100) with a 185 corner radius. Any other
// outline is shrunk onto a grey plate. So clip to exactly that, drawing the
// artwork a little larger so the clip's corners fall inside the artwork's
// own rounder corners.
let grid = CGRect(x: 100, y: 100, width: 824, height: 824)
let master = makeContext(width: 1024, height: 1024)
master.addPath(CGPath(roundedRect: grid, cornerWidth: 185, cornerHeight: 185, transform: nil))
master.clip()
let scale = 824.0 * 1.04 / Double(max(cutOut.width, cutOut.height))
let fitted = CGSize(width: Double(cutOut.width) * scale, height: Double(cutOut.height) * scale)
master.draw(cutOut, in: CGRect(x: (1024 - fitted.width) / 2, y: (1024 - fitted.height) / 2,
                               width: fitted.width, height: fitted.height))
let masterImage = master.makeImage()!

// MARK: - Write the iconset

try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scaleFactor in [1, 2] {
        let pixelsAcross = points * scaleFactor
        let context = makeContext(width: pixelsAcross, height: pixelsAcross)
        context.draw(masterImage, in: CGRect(x: 0, y: 0, width: pixelsAcross, height: pixelsAcross))
        let name = "icon_\(points)x\(points)" + (scaleFactor == 2 ? "@2x" : "") + ".png"
        let destination = CGImageDestinationCreateWithURL(outputURL.appendingPathComponent(name) as CFURL,
                                                          UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        guard CGImageDestinationFinalize(destination) else {
            FileHandle.standardError.write(Data("cannot write \(name)\n".utf8))
            exit(1)
        }
    }
}
