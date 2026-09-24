import AppKit

MainActor.assumeIsolated {
    let app = NSApplication.shared
    // Imágenes del README: ShotGenie --render-docs <capturas> <salida>
    let args = CommandLine.arguments
    if let i = args.firstIndex(of: "--render-docs"), args.count > i + 2 {
        DocsRenderer.run(captures: URL(fileURLWithPath: args[i + 1]), output: URL(fileURLWithPath: args[i + 2]))
        exit(0)
    }
    let delegate = AppDelegate()
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
}
