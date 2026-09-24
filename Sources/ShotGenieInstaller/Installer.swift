import AppKit
import ShotGenieCore

/// Copia la ShotGenie.app que lleva dentro a Aplicaciones y la abre.
///
/// Pruebas: `-installDir <carpeta>` instala ahí, sin cerrar ni abrir ShotGenie ni expulsar el
/// disco, para no tocar la copia de verdad.
@MainActor @Observable
final class Installer {
    enum State: Equatable { case working, done, failed(String) }

    private(set) var state = State.working
    private let appID = "com.enderj.screencapture"
    private let testDir = UserDefaults.standard.string(forKey: "installDir")

    func run() async {
        let started = Date()
        do {
            let dest = try await install()
            // Que la barra se vea un momento aunque copiar tarde milisegundos.
            let shown = Date().timeIntervalSince(started)
            if shown < 0.8 { try? await Task.sleep(for: .seconds(0.8 - shown)) }
            if testDir == nil {
                _ = try? await NSWorkspace.shared.openApplication(at: dest, configuration: .init())
            }
            state = .done
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Cierra el instalador y expulsa el DMG.
    func finish() {
        if testDir == nil, let volume = diskImageVolume() {
            // Tras salir el instalador, para que el disco no esté en uso.
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/sh")
            p.arguments = ["-c", "sleep 1; /usr/bin/hdiutil detach \"$0\" -quiet", volume.path]
            try? p.run()
        }
        NSApp.terminate(nil)
    }

    private func install() async throws -> URL {
        let fm = FileManager.default
        guard let source = Bundle.main.url(forResource: "ShotGenie", withExtension: "app") else {
            throw InstallError(String(localized: "The installer is incomplete: ShotGenie.app is missing. Download it again."))
        }
        let dest: URL
        if let testDir {
            dest = URL(fileURLWithPath: testDir).appendingPathComponent(InstallDestination.appName)
        } else {
            let system = URL(fileURLWithPath: "/Applications")
            dest = InstallDestination.choose(systemApplications: system,
                                             userApplications: fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
                                             systemWritable: fm.isWritableFile(atPath: system.path))
        }
        // Nunca pisar otra app que se llame igual.
        if fm.fileExists(atPath: dest.path), Bundle(url: dest)?.bundleIdentifier != appID {
            throw InstallError(String(localized: "There is another app named ShotGenie in \(dest.deletingLastPathComponent().path). Move it away and try again."))
        }
        if testDir == nil { await quitRunningCopies() }

        let folder = dest.deletingLastPathComponent()
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let staging = folder.appendingPathComponent(".ShotGenie.app.installing")
        try? fm.removeItem(at: staging)
        try fm.copyItem(at: source, to: staging)
        // La copia hereda la cuarentena del DMG descargado. Quien abre el instalador ya aceptó
        // abrirlo en Privacidad y seguridad; sin esto macOS volvería a bloquear ShotGenie.
        Self.removeQuarantine(under: staging)
        if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
        try fm.moveItem(at: staging, to: dest)
        return dest
    }

    private func quitRunningCopies() async {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: appID)
        running.forEach { $0.terminate() }
        for _ in 0..<50 where running.contains(where: { !$0.isTerminated }) {
            try? await Task.sleep(for: .milliseconds(100))
        }
        running.filter { !$0.isTerminated }.forEach { $0.forceTerminate() }
    }

    static func removeQuarantine(under root: URL) {
        let name = "com.apple.quarantine"
        removexattr(root.path, name, XATTR_NOFOLLOW)
        let items = FileManager.default.enumerator(atPath: root.path)
        while let relative = items?.nextObject() as? String {
            removexattr(root.appendingPathComponent(relative).path, name, XATTR_NOFOLLOW)
        }
    }

    /// El volumen del DMG desde el que se abrió el instalador (macOS puede ejecutarlo desde una
    /// copia temporal, así que se busca entre los discos montados).
    private func diskImageVolume() -> URL? {
        let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]) ?? []
        return volumes.first { volume in
            let app = volume.appendingPathComponent(Bundle.main.bundleURL.lastPathComponent)
            return Bundle(url: app)?.bundleIdentifier == Bundle.main.bundleIdentifier
        }
    }
}

struct InstallError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}
