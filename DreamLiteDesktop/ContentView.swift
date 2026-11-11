import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var generator: DiffusionGenerator
    @AppStorage("selectedDiffusionModel") private var selectedModel = DiffusionModel.dreamLite

    @State private var prompt = "A small wooden cabin beside a mountain lake at sunrise, detailed natural lighting"
    @State private var seed = 42
    @State private var resolution = 512
    @State private var status = "Ready."
    @State private var elapsed: TimeInterval?
    @State private var imageData: Data?
    @State private var displayedImage: NSImage?
    @State private var errorMessage: String?
    @State private var imageModel: DiffusionModel?
    @State private var imageIsDemo = false

    private var generating: Bool { generator.isGenerating }

    var body: some View {
        HSplitView {
            controls
                .frame(minWidth: 330, idealWidth: 370, maxWidth: 440)
            preview
                .frame(minWidth: 480)
        }
        .frame(minWidth: 860, minHeight: 580)
        .onChange(of: selectedModel) {
            status = "Ready."
            elapsed = nil
            errorMessage = nil
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Diffusion Studio")
                    .font(.largeTitle.weight(.semibold))
                Text("Local text-to-image generation")
                    .foregroundStyle(.secondary)
            }

            Divider()

            Picker("Model", selection: $selectedModel) {
                ForEach(DiffusionModel.allCases) { model in
                    Text(model.name).tag(model)
                }
            }
            .pickerStyle(.segmented)
            .disabled(generating)
            .accessibilityLabel("Diffusion model")

            Text("Prompt")
                .font(.headline)
            TextEditor(text: $prompt)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(9)
                .frame(height: 180)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityLabel("Text-to-image prompt")
                .disabled(generating)

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Resolution")
                        .font(.headline)
                    if selectedModel == .sanaSprint {
                        Text("1024 × 1024")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Picker("Resolution", selection: $resolution) {
                            Text("512 × 512").tag(512)
                            Text("768 × 768").tag(768)
                            Text("1024 × 1024").tag(1024)
                        }
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .disabled(generating)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Seed")
                        .font(.headline)
                    TextField("Seed", value: $seed, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .disabled(generating)
                }
            }

            Button {
                Task { await generate() }
            } label: {
                HStack(spacing: 9) {
                    if generating { ProgressView().controlSize(.small) }
                    Text(generating ? "Generating…" : "Generate image")
                        .frame(maxWidth: .infinity)
                }
                .padding(.vertical, 5)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(generating || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .keyboardShortcut(.return, modifiers: .command)

            if generating {
                Text("The first image after switching models includes model loading.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Text(status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            if let elapsed {
                Text(String(format: "Last request: %.1f seconds", elapsed))
                    .font(.caption.monospacedDigit())
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.red.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
            }

            Spacer(minLength: 0)

            Text(selectedModel.details)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(22)
    }

    private var preview: some View {
        VStack(spacing: 14) {
            HStack {
                Text(imageModel.map { imageIsDemo ? "\($0.name) demo image" : "\($0.name) image" } ?? "Generated image")
                    .font(.title3.weight(.semibold))
                Spacer()
                if imageIsDemo && imageData != nil {
                    Text("Demo mode")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Button("Save PNG…") { saveImage() }
                    .disabled(imageData == nil)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.secondary.opacity(0.08))
                if let displayedImage {
                    Image(nsImage: displayedImage)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .padding(18)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "photo.artframe")
                            .font(.system(size: 64, weight: .ultraLight))
                            .foregroundStyle(.secondary)
                        Text("Your image will appear here")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text("Enter a prompt and click Generate image.")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                    }
                }
                if generating {
                    Rectangle()
                        .fill(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.large)
                        Text("Generating image…")
                            .font(.headline)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(22)
    }

    @MainActor
    private func generate() async {
        let model = selectedModel
        errorMessage = nil
        elapsed = nil
        status = "Generating with \(model.name)…"
        let started = Date()

        do {
            let result = try await generator.generate(
                model: model,
                prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines),
                seed: seed,
                resolution: model == .sanaSprint ? 1024 : resolution
            )
            guard let image = NSImage(data: result.png) else {
                throw NSError(domain: "DiffusionStudio", code: -1,
                              userInfo: [NSLocalizedDescriptionKey: "The model returned invalid image data."])
            }
            imageModel = result.model
            imageIsDemo = result.isDemo
            imageData = result.png
            displayedImage = image
            elapsed = Date().timeIntervalSince(started)
            status = "Image generated successfully."
        } catch {
            errorMessage = error.localizedDescription
            status = "Generation failed."
        }
    }

    private func saveImage() {
        guard let imageData else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = (imageModel ?? selectedModel).filename
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try imageData.write(to: url, options: .atomic)
                status = "Saved to \(url.path)"
                errorMessage = nil
            } catch {
                errorMessage = "Unable to save PNG: \(error.localizedDescription)"
            }
        }
    }
}
