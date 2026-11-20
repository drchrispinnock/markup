// Makes the iOS app icon from the Mac artwork.
//
//   swift scripts/make-icon.swift ../img/Markup.png MarkupGo/Assets.xcassets/AppIcon.appiconset/AppIcon.png
//
// The artwork is a dark rounded square on white. iOS wants a full, opaque
// square that it rounds itself, so the square is cropped to its edges and
// the white left in its corners is painted the colour of the square just
// inside its edge (iOS's own rounding hides those corners anyway).

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let arguments = CommandLine.arguments
guard arguments.count == 3,
      let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: arguments[1]) as CFURL, nil),
      let artwork = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <artwork.png> <output.png>\n".utf8))
    exit(2)
}

let width = artwork.width, height = artwork.height
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let canvas = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                       space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
canvas.draw(artwork, in: CGRect(x: 0, y: 0, width: width, height: height))
let pixels = canvas.data!.bindMemory(to: UInt8.self, capacity: width * height * 4)
func isLight(_ x: Int, _ y: Int) -> Bool {
    let i = (y * width + x) * 4
    return min(pixels[i], pixels[i + 1], pixels[i + 2]) >= 200
}

// The square's edges: the first and last dark pixels through the middle.
let midX = width / 2, midY = height / 2
let left = (0..<width).first { !isLight($0, midY) }!
let right = (0..<width).last { !isLight($0, midY) }!
let top = (0..<height).first { !isLight(midX, $0) }!
let bottom = (0..<height).last { !isLight(midX, $0) }!
// A little inside, past the edge's anti-aliasing.
let inset = 4
let crop = (x: left + inset, y: top + inset, w: right - left - 2 * inset, h: bottom - top - 2 * inset)

// Paint the white in the corners, working in from each side of each row.
for y in crop.y..<(crop.y + crop.h) {
    for range in [Array(crop.x..<midX), Array((midX..<(crop.x + crop.w)).reversed())] {
        var x = range.first!
        for next in range {
            x = next
            // Stop once well inside the square.
            if !isLight(x, y) && !isLight(min(x + 3, width - 1), y) && !isLight(max(x - 3, 0), y) { break }
        }
        let edge = x
        // The square's colour just inside its edge on this row.
        let fill = (y * width + (range.first! < midX ? edge + 12 : edge - 12)) * 4
        for x in range {
            if range.first! < midX ? x > edge + 3 : x < edge - 3 { break }
            let i = (y * width + x) * 4
            for c in 0..<3 { pixels[i + c] = pixels[fill + c] }
        }
    }
}

let image = canvas.makeImage()!.cropping(to: CGRect(x: crop.x, y: crop.y, width: crop.w, height: crop.h))!
let output = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 1024 * 4,
                       space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
output.interpolationQuality = .high
output.draw(image, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: arguments[2]) as CFURL,
                                                  UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, output.makeImage()!, nil)
guard CGImageDestinationFinalize(destination) else { exit(1) }
