import AppKit
import SwiftUI

@MainActor
final class InstallerDelegate: NSObject, NSApplicationDelegate {
    private let installer = Installer()
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let host = NSHostingController(rootView: InstallerView(installer: installer))
        let w = NSWindow(contentViewController: host)
        w.title = String(localized: "Install ShotGenie")
        w.styleMask = [.titled, .closable]
        w.isReleasedWhenClosed = false
        w.center()
        window = w
        NSApp.activate()
        w.makeKeyAndOrderFront(nil)
        Task { await installer.run() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct InstallerView: View {
    let installer: Installer

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 96, height: 96)
            switch installer.state {
            case .working:
                Text("Installing ShotGenie…").font(.system(size: 15, weight: .semibold))
                ProgressView().progressViewStyle(.linear).frame(width: 220)
            case .done:
                Label("ShotGenie is installed", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .symbolRenderingMode(.multicolor)
                Text("It's open in your Dock. To keep it there, right-click its icon → Options → Keep in Dock.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                Button("Done") { installer.finish() }
                    .keyboardShortcut(.defaultAction).controlSize(.large)
            case .failed(let message):
                Label("Couldn't install ShotGenie", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .symbolRenderingMode(.multicolor)
                Text(message)
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                Button("Quit") { NSApp.terminate(nil) }
                    .keyboardShortcut(.defaultAction).controlSize(.large)
            }
        }
        .padding(.horizontal, 32).padding(.vertical, 26)
        .frame(width: 400)
        .animation(.easeOut(duration: 0.2), value: installer.state)
    }
}
