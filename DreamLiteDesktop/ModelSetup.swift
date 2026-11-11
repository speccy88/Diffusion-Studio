import Combine
import Darwin
import Foundation

enum ModelFiles {
    static let dataDirectory = URL.applicationSupportDirectory.appending(path: "Diffusion Studio", directoryHint: .isDirectory)
    static let demo = CommandLine.arguments.contains("--demo")

    static func bundledPath(_ key: String) -> URL? {
        guard let path = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        return URL(fileURLWithPath: path, relativeTo: Bundle.main.bundleURL.deletingLastPathComponent()).standardizedFileURL
    }

    static var dreamLitePython: URL? {
        let managed = dataDirectory.appending(path: "dreamlite/.venv/bin/python3")
        let managedReady = FileManager.default.fileExists(atPath: dataDirectory.appending(path: "dreamlite/runtime-ready").path)
        return [managedReady ? managed : nil, bundledPath("DreamLitePythonPath")].compactMap { $0 }.first { python in
            let venv = python.deletingLastPathComponent().deletingLastPathComponent()
            let packages = venv.appending(path: "lib/python3.11/site-packages")
            let required = demo ? ["PIL/Image.py"] : [
                "PIL/Image.py", "torch/__init__.py", "torchvision/__init__.py", "transformers/__init__.py",
                "diffusers/pipelines/dreamlite/pipeline_dreamlite_mobile.py"
            ]
            return FileManager.default.isExecutableFile(atPath: python.path) && contains(required, in: packages)
        }
    }

    static var dreamLiteModel: URL? {
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--model-path"), index + 1 < arguments.count {
            return URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        }
        let marker = dataDirectory.appending(path: "dreamlite/model-path")
        if let path = try? String(contentsOf: marker, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           path.hasPrefix("/"), validDreamLite(URL(fileURLWithPath: path)) {
            return URL(fileURLWithPath: path)
        }

        let environment = ProcessInfo.processInfo.environment
        let cache = environment["HF_HUB_CACHE"] ?? environment["HUGGINGFACE_HUB_CACHE"] ??
            environment["HF_HOME"].map { $0 + "/hub" } ??
            (environment["XDG_CACHE_HOME"] ?? URL.homeDirectory.appending(path: ".cache").path) + "/huggingface/hub"
        let repository = URL(fileURLWithPath: cache).appending(path: "models--carlofkl--DreamLite-mobile")
        guard let revision = try? String(contentsOf: repository.appending(path: "refs/diffusers"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), !revision.isEmpty else { return nil }
        let snapshot = repository.appending(path: "snapshots/\(revision)")
        return validDreamLite(snapshot) ? snapshot : nil
    }

    static var sanaModel: URL? {
        let managed = dataDirectory.appending(path: "models/Sana_Sprint_0.6B_1024px_diffusers")
        return [managed, bundledPath("SanaModelPath")].compactMap { $0 }.first {
            contains(["metadata.json", "tokenizer/tokenizer.json", "Transformer.aimodel",
                      "TextEncoder.aimodel", "VAEDecoder.aimodel"], in: $0)
        }
    }

    private static func validDreamLite(_ directory: URL) -> Bool {
        contains(["model_index.json", "text_encoder/model.safetensors", "unet/diffusion_pytorch_model.safetensors",
                  "vae/diffusion_pytorch_model.safetensors", "processor/preprocessor_config.json"], in: directory)
    }

    private static func contains(_ files: [String], in directory: URL) -> Bool {
        files.allSatisfy { FileManager.default.fileExists(atPath: directory.appending(path: $0).path) }
    }
}

@MainActor
final class ModelSetup: ObservableObject {
    struct Activity {
        var stage = "Starting setup…"
        var completed = 0
        var total = 0
    }

    @Published private(set) var activity: Activity?
    @Published private(set) var failures: [DiffusionModel: String] = [:]
    @Published private var ready: Set<DiffusionModel> = []
    private var process: Process?

    init() { refresh() }

    func isReady(_ model: DiffusionModel) -> Bool { ready.contains(model) }

    func refresh() {
        var installed: Set<DiffusionModel> = []
        if ModelFiles.dreamLitePython != nil && (ModelFiles.demo || ModelFiles.dreamLiteModel != nil) {
            installed.insert(.dreamLite)
        }
        if ModelFiles.sanaModel != nil { installed.insert(.sanaSprint) }
        if ready != installed { ready = installed }
    }

    func logURL(for model: DiffusionModel) -> URL {
        ModelFiles.dataDirectory.appending(path: "\(model.rawValue)-setup.log")
    }

    func install(_ model: DiffusionModel) async {
        guard activity == nil, !isReady(model) else { return }
        guard let script = Bundle.main.url(forResource: "setup-model", withExtension: "sh") else {
            failures[model] = "The setup files are missing. Reinstall Diffusion Studio."
            return
        }

        activity = Activity()
        failures[model] = nil
        defer {
            activity = nil
            process = nil
        }

        do {
            let directory = ModelFiles.dataDirectory
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let descriptor = Darwin.open(directory.appending(path: "setup.lock").path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
            guard descriptor >= 0 else { throw CocoaError(.fileWriteUnknown) }
            defer { Darwin.close(descriptor) }
            guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
                failures[model] = "Another Diffusion Studio window or copy is setting up a model. Try again when it finishes."
                return
            }

            try Data().write(to: logURL(for: model), options: .atomic)
            let log = try FileHandle(forWritingTo: logURL(for: model))
            defer { try? log.close() }
            let updates = Pipe()
            let child = Process()
            child.executableURL = URL(fileURLWithPath: "/bin/bash")
            child.arguments = [script.path, model.rawValue, directory.path]
            child.currentDirectoryURL = directory
            child.standardOutput = updates
            child.standardError = log
            child.standardInput = FileHandle.nullDevice
            try child.run()
            process = child

            let exitStatus = await Task.detached { [weak self] in
                var pending = Data()
                let reader = updates.fileHandleForReading
                while true {
                    let chunk = reader.availableData
                    if chunk.isEmpty { break }
                    pending.append(chunk)
                    while let newline = pending.firstIndex(of: 10) {
                        let line = String(decoding: pending[..<newline], as: UTF8.self)
                        pending.removeSubrange(...newline)
                        await self?.receive(line)
                    }
                }
                child.waitUntilExit()
                return child.terminationStatus
            }.value
            refresh()
            if exitStatus != 0 || !isReady(model) {
                failures[model] = "Setup did not finish. Check your connection and available disk space, then retry. The setup log has details."
            }
        } catch {
            failures[model] = "Could not start setup. \(error.localizedDescription)"
        }
    }

    func stop() {
        guard let process, process.isRunning else { return }
        let pid = process.processIdentifier
        if getpgid(pid) == pid {
            kill(-pid, SIGTERM)
        } else {
            process.terminate()
        }
    }

    private func receive(_ line: String) {
        if line.hasPrefix("STUDIO_STAGE:") {
            activity?.stage = String(line.dropFirst("STUDIO_STAGE:".count))
            activity?.total = 0
        } else if line.hasPrefix("STUDIO_FILES:") {
            let counts = line.dropFirst("STUDIO_FILES:".count).split(separator: " ").compactMap { Int($0) }
            if counts.count == 2, counts[1] > 0 {
                activity?.completed = counts[0]
                activity?.total = counts[1]
            }
        }
    }
}
