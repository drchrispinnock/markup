import AppKit
import MachO

/// The app icon for a debug build run without an app bundle, as `swift run`
/// does. Debug builds embed `img/Markup.png` in the executable's
/// `__TEXT,__markup_icon` section. `scripts/build-app.sh` gives the app
/// bundle its icon from the same artwork.
@MainActor
enum DevelopmentIcon {
    /// Sets the Dock and About panel icon, if there is no app bundle and the
    /// executable has the artwork.
    static func install() {
        guard Bundle.main.bundleURL.pathExtension != "app", let icon = make() else { return }
        NSApp.applicationIconImage = icon
    }

    /// The artwork drawn as `make-icon.swift` draws it: the shape, without
    /// its white surround, clipped to the standard 824 x 824 rounded rect
    /// (radius 185) on a 1024 canvas.
    static func make() -> NSImage? {
        guard let artwork = embeddedArtwork(), let shape = shapeBounds(of: artwork),
              let cutOut = artwork.cropping(to: shape) else { return nil }
        let image = NSImage(size: NSSize(width: 1024, height: 1024), flipped: false) { _ in
            NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
                .addClip()
            // Drawn a little larger, so the clip's corners fall inside the
            // artwork's own rounder corners and none of the white shows.
            let scale = 824 * 1.04 / CGFloat(max(cutOut.width, cutOut.height))
            let size = NSSize(width: CGFloat(cutOut.width) * scale, height: CGFloat(cutOut.height) * scale)
            NSGraphicsContext.current?.cgContext.draw(cutOut, in: CGRect(
                x: (1024 - size.width) / 2, y: (1024 - size.height) / 2, width: size.width, height: size.height))
            return true
        }
        return image
    }

    private static func embeddedArtwork() -> CGImage? {
        var size: UInt = 0
        let header = #dsohandle.assumingMemoryBound(to: mach_header_64.self)
        guard let bytes = getsectiondata(header, "__TEXT", "__markup_icon", &size) else { return nil }
        let data = Data(bytes: bytes, count: Int(size))
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// The bounding box of the artwork's non-white pixels, in the image's
    /// top-left-origin coordinates.
    private static func shapeBounds(of image: CGImage) -> CGRect? {
        let width = image.width, height = image.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                guard min(pixels[offset], pixels[offset + 1], pixels[offset + 2]) < 200 else { continue }
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX else { return nil }
        // The context's memory starts with the image's top row, as cropping
        // expects.
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}
