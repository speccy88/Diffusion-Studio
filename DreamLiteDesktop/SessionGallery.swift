import AppKit
import Combine
import ImageIO

struct SessionImage: Identifiable {
    let id: UUID
    let modelName: String
    let filename: String
    let isDemo: Bool
    let prompt: String
    let seed: Int
    let resolution: Int
    let thumbnail: NSImage
    let fileURL: URL?
    // Preserve the result even if the temporary disk is full or unavailable.
    let fallbackPNG: Data?

    func pngData() throws -> Data {
        if let fallbackPNG { return fallbackPNG }
        guard let fileURL else { throw CocoaError(.fileNoSuchFile) }
        return try Data(contentsOf: fileURL)
    }
}

@MainActor
final class SessionGallery: ObservableObject {
    @Published private(set) var images: [SessionImage] = []
    @Published private(set) var storageWarning: String?
    private let directory: URL

    init(directory: URL = FileManager.default.temporaryDirectory
        .appendingPathComponent("DiffusionStudio-\(UUID().uuidString)", isDirectory: true)) {
        self.directory = directory
    }

    func append(png: Data, modelName: String, filename: String, isDemo: Bool,
                prompt: String, seed: Int, resolution: Int) throws {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 176,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let id = UUID()
        let destination = directory.appendingPathComponent("\(id.uuidString).png")
        var fileURL: URL? = destination
        var fallbackPNG: Data?
        storageWarning = nil
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try png.write(to: destination, options: .atomic)
        } catch {
            fileURL = nil
            fallbackPNG = png
            storageWarning = "Temporary storage is unavailable. This image is kept in memory and can still be saved. \(error.localizedDescription)"
        }
        images.append(SessionImage(
            id: id, modelName: modelName, filename: filename, isDemo: isDemo,
            prompt: prompt, seed: seed, resolution: resolution,
            thumbnail: NSImage(cgImage: thumbnail, size: .zero),
            fileURL: fileURL, fallbackPNG: fallbackPNG
        ))
    }

    func cleanUp() {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        do {
            try FileManager.default.removeItem(at: directory)
        } catch {
            NSLog("Could not remove session images: %@", error.localizedDescription)
        }
    }
}
