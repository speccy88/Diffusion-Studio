import Darwin
import Foundation

struct WorkerStatus: Decodable {
    let mode: String
    let modelLoaded: Bool

    enum CodingKeys: String, CodingKey {
        case mode
        case modelLoaded = "model_loaded"
    }
}

private struct WorkerRequest: Encodable {
    enum Action: String, Encodable {
        case status, generate
    }

    let action: Action
    var prompt: String?
    var seed: Int?
    var resolution: Int?
}

private struct WorkerReply: Decodable {
    let status: WorkerStatus?
    let png: Data?
    let error: String?
}

private enum WorkerError: LocalizedError {
    case pythonMissing
    case scriptMissing
    case disconnected
    case invalidReply
    case generation(String)

    var errorDescription: String? {
        switch self {
        case .pythonMissing: "Run backend/setup-mac.sh in the Diffusion Studio folder to set up Python."
        case .scriptMissing: "The app is missing its Python worker. Rebuild Diffusion Studio."
        case .disconnected: "The Python worker stopped. Try generating again."
        case .invalidReply: "DreamLite received an invalid reply from the Python worker."
        case .generation(let message): message
        }
    }
}

@MainActor
final class DreamLiteWorker {
    private final class Connection {
        let process: Process
        let input: FileHandle
        let output: FileHandle

        init(process: Process, input: FileHandle, output: FileHandle) {
            self.process = process
            self.input = input
            self.output = output
        }
    }

    private let io = DispatchQueue(label: "local.diffusion.studio.worker")
    private var connection: Connection?

    func status() async throws -> WorkerStatus {
        try await request(WorkerRequest(action: .status)).status
    }

    func generate(prompt: String, seed: Int, resolution: Int) async throws -> (status: WorkerStatus, png: Data) {
        let reply = try await request(
            WorkerRequest(action: .generate, prompt: prompt, seed: seed, resolution: resolution)
        )
        guard let png = reply.png else { throw WorkerError.invalidReply }
        return (reply.status, png)
    }

    func stop() {
        if let connection, connection.process.isRunning {
            connection.process.terminate()
        }
        connection = nil
    }

    func stopAndWait() async {
        let process = connection?.process
        stop()
        guard let process else { return }
        await withCheckedContinuation { continuation in
            io.async {
                process.waitUntilExit()
                continuation.resume()
            }
        }
    }

    private func start() throws -> Connection {
        if let connection, connection.process.isRunning { return connection }

        guard let path = Bundle.main.object(forInfoDictionaryKey: "DreamLitePythonPath") as? String else {
            throw WorkerError.pythonMissing
        }
        let pythonURL = URL(fileURLWithPath: path,
                            relativeTo: Bundle.main.bundleURL.deletingLastPathComponent()).standardizedFileURL
        guard FileManager.default.isExecutableFile(atPath: pythonURL.path) else {
            throw WorkerError.pythonMissing
        }
        guard let script = Bundle.main.url(forResource: "server", withExtension: "py") else {
            throw WorkerError.scriptMissing
        }

        let requests = Pipe()
        let replies = Pipe()
        let input = requests.fileHandleForWriting
        guard fcntl(input.fileDescriptor, F_SETNOSIGPIPE, 1) != -1 else {
            throw WorkerError.disconnected
        }

        let process = Process()
        process.executableURL = pythonURL
        process.arguments = ["-u", script.path, "--stdio"]
        let arguments = CommandLine.arguments
        if arguments.contains("--demo") {
            process.arguments?.append("--demo")
        }
        if let index = arguments.firstIndex(of: "--model-path"), index + 1 < arguments.count {
            process.arguments?.append(contentsOf: ["--model-path", arguments[index + 1]])
        }
        process.standardInput = requests
        process.standardOutput = replies
        process.standardError = FileHandle.standardError
        try process.run()

        let connection = Connection(process: process, input: input, output: replies.fileHandleForReading)
        self.connection = connection
        return connection
    }

    private func request(_ request: WorkerRequest) async throws -> (status: WorkerStatus, png: Data?) {
        var payload = try JSONEncoder().encode(request)
        payload.append(0x0A)
        let current = try start()
        let input = current.input
        let output = current.output
        let requestData = payload
        let reply: WorkerReply
        do {
            reply = try await withCheckedThrowingContinuation { continuation in
                io.async {
                    continuation.resume(with: Result {
                        try input.write(contentsOf: requestData)
                        // Each reply begins with its four-byte, big-endian byte count.
                        let header = try Self.readExactly(4, from: output)
                        let length = header.reduce(0) { ($0 << 8) | Int($1) }
                        guard (1...16 * 1024 * 1024).contains(length) else {
                            throw WorkerError.invalidReply
                        }
                        let data = try Self.readExactly(length, from: output)
                        return try JSONDecoder().decode(WorkerReply.self, from: data)
                    })
                }
            }
        } catch {
            if connection === current { stop() }
            if let workerError = error as? WorkerError { throw workerError }
            if error is DecodingError { throw WorkerError.invalidReply }
            throw WorkerError.disconnected
        }

        if let message = reply.error { throw WorkerError.generation(message) }
        guard let status = reply.status else { throw WorkerError.invalidReply }
        return (status, reply.png)
    }

    nonisolated private static func readExactly(_ length: Int, from handle: FileHandle) throws -> Data {
        var data = Data()
        data.reserveCapacity(length)
        while data.count < length {
            guard let chunk = try handle.read(upToCount: length - data.count), !chunk.isEmpty else {
                throw WorkerError.disconnected
            }
            data.append(chunk)
        }
        return data
    }
}
