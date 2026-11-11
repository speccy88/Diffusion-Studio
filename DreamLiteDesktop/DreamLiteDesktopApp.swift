import AppKit
import SwiftUI

@MainActor
final class DreamLiteAppDelegate: NSObject, NSApplicationDelegate {
    let generator = DiffusionGenerator()
    let gallery = SessionGallery()
    let setup = ModelSetup()

    func applicationDidBecomeActive(_ notification: Notification) {
        setup.refresh()
    }

    func applicationWillTerminate(_ notification: Notification) {
        generator.stop()
        setup.stop()
        gallery.cleanUp()
    }
}

@main
struct DreamLiteDesktopApp: App {
    @NSApplicationDelegateAdaptor(DreamLiteAppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup("Diffusion Studio") {
            ContentView(generator: delegate.generator, gallery: delegate.gallery, setup: delegate.setup)
        }
        .defaultSize(width: 1050, height: 760)
    }
}
