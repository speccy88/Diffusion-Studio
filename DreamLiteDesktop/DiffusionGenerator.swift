import Combine
import CoreAIDiffusionPipeline
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum DiffusionModel: String, CaseIterable, Identifiable {
    case dreamLite
    case sanaSprint

    var id: String { rawValue }

    var name: String {
        switch self {
        case .dreamLite: "DreamLite"
        case .sanaSprint: "SANA Sprint"
        }
    }

    var details: String {
        switch self {
        case .dreamLite: "DreamLite-Mobile · MPS · 4 steps"
        case .sanaSprint: "SANA Sprint 0.6B · Core AI · 2 steps"
        }
    }

    var filename: String {
        switch self {
        case .dreamLite: "dreamlite-image.png"
        case .sanaSprint: "sana-sprint-image.png"
        }
    }
}

struct GeneratedImage {
    let png: Data
    let model: DiffusionModel
    let isDemo: Bool
}

private enum GenerationError: LocalizedError {
    case busy
    case invalidPrompt
    case invalidSeed
    case missingSana
    case missingImage

    var errorDescription: String? {
        switch self {
        case .busy: "An image is already being generated."
        case .invalidPrompt: "Prompt must be between 1 and 2000 characters."
        case .invalidSeed: "Seed must be an integer between 0 and 4294967295."
        case .missingSana: "Run setup-sana.sh in the Diffusion Studio folder to prepare SANA Sprint."
        case .missingImage: "The model could not produce a PNG image."
        }
    }
}

private actor SanaGenerator {
    private var pipeline: FlowTransformerPipeline?
    private let modelURL: URL?

    init() {
        modelURL = (Bundle.main.object(forInfoDictionaryKey: "SanaModelPath") as? String)
            .map {
                URL(fileURLWithPath: $0, isDirectory: true,
                    relativeTo: Bundle.main.bundleURL.deletingLastPathComponent()).standardizedFileURL
            }
    }

    func unload() async {
        await pipeline?.unloadResources()
        pipeline = nil
    }

    func generate(prompt: String, seed: UInt32) async throws -> Data {
        if pipeline == nil {
            guard let modelURL,
                  FileManager.default.fileExists(atPath: modelURL.appendingPathComponent("metadata.json").path) else {
                throw GenerationError.missingSana
            }
            pipeline = try await FlowTransformerPipeline(from: modelURL, mode: .full)
        }
        guard let pipeline else { throw GenerationError.missingSana }

        do {
            let configuration = PipelineConfiguration(
                prompt: prompt,
                seed: seed,
                stepCount: 2,
                guidanceScale: 4.5,
                schedulerType: .discreteFlow
            )
            let result = try await pipeline.generateImages(configuration: configuration)
            guard let image = result.images.first else { throw GenerationError.missingImage }
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(
                data, UTType.png.identifier as CFString, 1, nil
            ) else { throw GenerationError.missingImage }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else { throw GenerationError.missingImage }
            return data as Data
        } catch {
            await unload()
            throw error
        }
    }
}

@MainActor
final class DiffusionGenerator: ObservableObject {
    @Published private(set) var isGenerating = false
    private let dreamLite = DreamLiteWorker()
    private let sana = SanaGenerator()

    func stop() {
        dreamLite.stop()
    }

    func generate(model: DiffusionModel, prompt: String, seed: Int, resolution: Int) async throws -> GeneratedImage {
        guard !isGenerating else { throw GenerationError.busy }
        guard (1...2000).contains(prompt.count) else { throw GenerationError.invalidPrompt }
        guard let seedValue = UInt32(exactly: seed) else { throw GenerationError.invalidSeed }
        isGenerating = true
        defer { isGenerating = false }

        switch model {
        case .dreamLite:
            await sana.unload()
            let result = try await dreamLite.generate(prompt: prompt, seed: seed, resolution: resolution)
            return GeneratedImage(png: result.png, model: model, isDemo: result.status.mode == "demo")
        case .sanaSprint:
            await dreamLite.stopAndWait()
            let png = try await sana.generate(prompt: prompt, seed: seedValue)
            return GeneratedImage(png: png, model: model, isDemo: false)
        }
    }
}
