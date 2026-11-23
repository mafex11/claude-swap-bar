import AppKit
import ServiceManagement
import SwapCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)  // menu bar only, also when run unbundled
    }
}

@main
struct ClaudeSwapMain: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = Model()

    init() {
        // `ClaudeSwap --render status.json out.png` draws the panel to a picture
        // and exits: used for the README screenshot and to check the layout.
        let args = CommandLine.arguments
        if args.count == 4, args[1] == "--render" {
            exit(Self.render(statusFile: args[2], to: args[3]) ? 0 : 1)
        }

        // One icon only, however it was started (login item, Finder, `open`).
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: ClaudeSwapApp.bundleID)
            .filter { $0.processIdentifier != getpid() }
        if !others.isEmpty { exit(0) }

        let settings = Settings()
        if !settings.loginItemInitialized {
            settings.loginItemInitialized = true
            try? SMAppService.mainApp.register()
        }
    }

    @MainActor
    private static func render(statusFile: String, to path: String) -> Bool {
        let model = Model(statusFile: statusFile)
        let view = Panel().environmentObject(model)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return false }
        return (try? png.write(to: URL(fileURLWithPath: path))) != nil
    }

    var body: some Scene {
        MenuBarExtra {
            Panel().environmentObject(model)
        } label: {
            let bar = Presentation.menuBar(model.local.snapshot, now: model.now)
            // Attention = an account is logged out, or claude-swap stopped ticking.
            Image(systemName: bar.attention ? "exclamationmark.arrow.triangle.2.circlepath" : "arrow.triangle.2.circlepath")
            Text(bar.title)
        }
        .menuBarExtraStyle(.window)
    }
}
