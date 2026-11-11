import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var generator: DiffusionGenerator
    @ObservedObject var gallery: SessionGallery
    @ObservedObject var setup: ModelSetup
    @AppStorage("selectedDiffusionModel") private var selectedModel = DiffusionModel.dreamLite

    @State private var prompt = "A small wooden cabin beside a mountain lake at sunrise, detailed natural lighting"
    @State private var seed = 42
    @State private var resolution = 512
    @State private var status = "Ready."
    @State private var elapsed: TimeInterval?
    @State private var selectedImage: SessionImage?
    @State private var displayedImage: NSImage?
    @State private var errorMessage: String?
    @FocusState private var historyFocused: Bool

    private var generating: Bool { generator.isGenerating }
    private var selectedIndex: Int? { gallery.images.firstIndex { $0.id == selectedImage?.id } }

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
        .onChange(of: gallery.images.last?.id) {
            if let image = gallery.images.last { selectImage(image) }
        }
        .onAppear {
            if let image = gallery.images.last { selectImage(image) }
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
            .disabled(generating || setup.activity != nil)
            .accessibilityLabel("Diffusion model")

            if setup.activity == nil, setup.isReady(selectedModel) {
                generationControls
            } else {
                downloadControls
            }

            Spacer(minLength: 0)

            Text(selectedModel.details)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(22)
    }

    @ViewBuilder
    private var generationControls: some View {
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
        .disabled(generating || setup.activity != nil || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
    }

    private var downloadControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let activity = setup.activity {
                Text(activity.stage)
                    .font(.headline)
                if activity.total > 0 {
                    ProgressView(value: Double(activity.completed), total: Double(activity.total)) {
                        Text("\(activity.completed) of \(activity.total) files")
                    }
                } else {
                    ProgressView().progressViewStyle(.linear)
                }
            } else {
                Text("Download \(selectedModel.name) to start generating images.")
                    .font(.headline)
                Text("Setup uses several gigabytes of storage.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let failure = setup.failures[selectedModel] {
                    Text(failure)
                        .font(.caption)
                        .foregroundStyle(.red)
                    let log = setup.logURL(for: selectedModel)
                    if FileManager.default.fileExists(atPath: log.path) {
                        Button("View setup log") { NSWorkspace.shared.open(log) }
                    }
                }
                Button {
                    let model = selectedModel
                    Task { await setup.install(model) }
                } label: {
                    Label(setup.failures[selectedModel] == nil ? "Download \(selectedModel.name)" : "Retry download",
                          systemImage: "arrow.down.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(generating)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private var preview: some View {
        VStack(spacing: 14) {
            HStack {
                Text(selectedImage.map { "\($0.modelName) image" } ?? "Generated image")
                    .font(.title3.weight(.semibold))
                Spacer()
                if selectedImage?.isDemo == true {
                    Text("Demo mode")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Button("Save PNG…") { saveImage() }
                    .disabled(selectedImage == nil)
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
                } else if setup.isReady(selectedModel) {
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
                } else {
                    Image(systemName: "photo.artframe")
                        .font(.system(size: 64, weight: .ultraLight))
                        .foregroundStyle(.secondary)
                }
                if generating && displayedImage == nil {
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

            if !gallery.images.isEmpty {
                history
            }
        }
        .padding(22)
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            HStack {
                Text("Session images")
                    .font(.headline)
                Spacer()
                Button { moveSelection(by: -1) } label: {
                    Image(systemName: "chevron.left")
                }
                .accessibilityLabel("Previous image")
                .disabled((selectedIndex ?? 0) == 0)
                Text("\((selectedIndex ?? 0) + 1) of \(gallery.images.count)")
                    .font(.caption.monospacedDigit())
                Button { moveSelection(by: 1) } label: {
                    Image(systemName: "chevron.right")
                }
                .accessibilityLabel("Next image")
                .disabled((selectedIndex ?? 0) >= gallery.images.count - 1)
            }

            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 10) {
                        ForEach(gallery.images) { image in
                            Button {
                                selectImage(image)
                                historyFocused = true
                            } label: {
                                VStack(spacing: 4) {
                                    Image(nsImage: image.thumbnail)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 80, height: 80)
                                        .background(Color.secondary.opacity(0.08))
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(image.id == selectedImage?.id ? Color.accentColor : .clear, lineWidth: 3)
                                        }
                                    Text(image.modelName)
                                        .font(.caption2)
                                }
                                .padding(3)
                            }
                            .buttonStyle(.plain)
                            .id(image.id)
                            .accessibilityLabel("\(image.modelName), seed \(image.seed), \(image.prompt)")
                            .accessibilityAddTraits(image.id == selectedImage?.id ? .isSelected : [])
                            .help("\(image.prompt)\nSeed \(image.seed) · \(image.resolution) × \(image.resolution)")
                        }
                    }
                    .padding(3)
                }
                .frame(height: 116)
                .onChange(of: selectedImage?.id) {
                    if let id = selectedImage?.id { proxy.scrollTo(id) }
                }
            }
            Text("Cleared when you quit. Save PNG to keep an image.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .focusable()
        .focused($historyFocused)
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) { moveSelection(by: -1); return .handled }
        .onKeyPress(.rightArrow) { moveSelection(by: 1); return .handled }
    }

    private func moveSelection(by offset: Int) {
        guard let index = selectedIndex, gallery.images.indices.contains(index + offset) else { return }
        selectImage(gallery.images[index + offset])
    }

    private func selectImage(_ image: SessionImage) {
        do {
            guard let preview = NSImage(data: try image.pngData()) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            displayedImage = preview
            selectedImage = image
        } catch {
            errorMessage = "Unable to open this session image: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func generate() async {
        guard setup.activity == nil, setup.isReady(selectedModel) else { return }
        let model = selectedModel
        let requestPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestSeed = seed
        let requestResolution = model == .sanaSprint ? 1024 : resolution
        errorMessage = nil
        elapsed = nil
        status = "Generating with \(model.name)…"
        let started = Date()

        do {
            let result = try await generator.generate(
                model: model,
                prompt: requestPrompt,
                seed: requestSeed,
                resolution: requestResolution
            )
            try gallery.append(png: result.png, modelName: result.model.name,
                               filename: result.model.filename, isDemo: result.isDemo,
                               prompt: requestPrompt, seed: requestSeed, resolution: requestResolution)
            errorMessage = gallery.storageWarning
            elapsed = Date().timeIntervalSince(started)
            status = "Image generated successfully."
        } catch {
            errorMessage = error.localizedDescription
            status = "Generation failed."
        }
    }

    private func saveImage() {
        guard let selectedImage else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = selectedImage.filename
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try selectedImage.pngData().write(to: url, options: .atomic)
                status = "Saved to \(url.path)"
                errorMessage = nil
            } catch {
                errorMessage = "Unable to save PNG: \(error.localizedDescription)"
            }
        }
    }
}
