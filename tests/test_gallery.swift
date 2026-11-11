import AppKit
import ImageIO
import UniformTypeIdentifiers

@main
struct GalleryTests {
    @MainActor
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let firstPNG = makePNG(red: 1, blue: 0)
        let secondPNG = makePNG(red: 0, blue: 1)
        let session = root.appendingPathComponent("session")
        let gallery = SessionGallery(directory: session)
        try gallery.append(png: firstPNG, modelName: "DreamLite", filename: "dreamlite.png",
                           isDemo: true, prompt: "First image", seed: 42, resolution: 512)
        try gallery.append(png: secondPNG, modelName: "SANA Sprint", filename: "sana.png",
                           isDemo: false, prompt: "Second image", seed: 43, resolution: 1024)
        precondition(gallery.images.count == 2)
        let restoredFirst = try gallery.images[0].pngData()
        let restoredSecond = try gallery.images[1].pngData()
        precondition(restoredFirst == firstPNG)
        precondition(restoredSecond == secondPNG)
        precondition(gallery.images[0].fallbackPNG == nil)
        precondition(gallery.images[1].modelName == "SANA Sprint")
        precondition(gallery.images[0].thumbnail.size.width <= 176)
        precondition(gallery.storageWarning == nil)
        // Generating the same bytes again must still produce a separate history entry.
        try gallery.append(png: firstPNG, modelName: "DreamLite", filename: "dreamlite.png",
                           isDemo: true, prompt: "First image", seed: 42, resolution: 512)
        precondition(Set(gallery.images.map(\.id)).count == 3)
        do {
            try gallery.append(png: Data(), modelName: "DreamLite", filename: "bad.png",
                               isDemo: true, prompt: "Invalid", seed: 0, resolution: 512)
            fatalError("Invalid image was accepted")
        } catch { }
        precondition(gallery.images.count == 3)

        let exported = root.appendingPathComponent("saved.png")
        try gallery.images[0].pngData().write(to: exported)
        gallery.cleanUp()
        gallery.cleanUp()
        precondition(!FileManager.default.fileExists(atPath: session.path))
        let savedPNG = try Data(contentsOf: exported)
        precondition(savedPNG == firstPNG)

        // A file in place of the directory simulates unavailable storage reliably.
        let blocked = root.appendingPathComponent("blocked")
        try Data("existing file".utf8).write(to: blocked)
        let fallback = SessionGallery(directory: blocked.appendingPathComponent("session"))
        try fallback.append(png: secondPNG, modelName: "SANA Sprint", filename: "sana.png",
                            isDemo: false, prompt: "Fallback", seed: 43, resolution: 1024)
        precondition(fallback.images.count == 1)
        precondition(fallback.images[0].fileURL == nil)
        let recoveredPNG = try fallback.images[0].pngData()
        precondition(recoveredPNG == secondPNG)
        precondition(fallback.storageWarning != nil)
        print("Gallery checks passed: retention, mixed models, thumbnails, duplicates, invalid input, export, cleanup, and disk failure recovery.")
    }

    static func makePNG(red: CGFloat, blue: CGFloat) -> Data {
        let context = CGContext(data: nil, width: 512, height: 512, bitsPerComponent: 8,
                                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(red: red, green: 0, blue: blue, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 512, height: 512))
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        precondition(CGImageDestinationFinalize(destination))
        return data as Data
    }
}
