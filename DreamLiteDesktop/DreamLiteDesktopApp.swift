import AppKit
import SwiftUI

@MainActor
final class DreamLiteAppDelegate: NSObject, NSApplicationDelegate {
    let generator = DiffusionGenerator()
    let gallery = SessionGallery()

    func applicationWillTerminate(_ notification: Notification) {
        generator.stop()
        gallery.cleanUp()
    }
}

@main
struct DreamLiteDesktopApp: App {
    @NSApplicationDelegateAdaptor(DreamLiteAppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup("Diffusion Studio") {
            ContentView(generator: delegate.generator, gallery: delegate.gallery)
        }
        .defaultSize(width: 1050, height: 760)
    }
}
