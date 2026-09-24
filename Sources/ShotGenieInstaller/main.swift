import AppKit

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = InstallerDelegate()
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
}
