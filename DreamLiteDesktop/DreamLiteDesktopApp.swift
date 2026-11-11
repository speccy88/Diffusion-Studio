import AppKit
import SwiftUI

@MainActor
final class DreamLiteAppDelegate: NSObject, NSApplicationDelegate {
    let generator = DiffusionGenerator()

    func applicationWillTerminate(_ notification: Notification) {
        generator.stop()
    }
}

@main
struct DreamLiteDesktopApp: App {
    @NSApplicationDelegateAdaptor(DreamLiteAppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup("Diffusion Studio") {
            ContentView(generator: delegate.generator)
        }
        .defaultSize(width: 1050, height: 760)
    }
}
