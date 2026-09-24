import AppKit

/// Abre la captura en Vista Previa con las herramientas de marcado ya a la vista.
@MainActor
enum Editor {
    private static let previewID = "com.apple.Preview"

    static func open(_ url: URL) {
        showMarkupToolbar()
        guard let preview = NSWorkspace.shared.urlForApplication(withBundleIdentifier: previewID) else {
            NSWorkspace.shared.open(url)
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.open([url], withApplicationAt: preview, configuration: config) { _, error in
            if let error { NSLog("ShotGenie: no se pudo abrir en Vista Previa: \(error.localizedDescription)") }
        }
    }

    /// Vista Previa recuerda si la barra de marcado estaba abierta (`PVMarkupToolbarVisibleForImages`)
    /// y la respeta al abrir cada imagen, aunque ya esté en marcha. Vive en su contenedor: por el
    /// dominio `com.apple.Preview` a secas se lee vacío. Solo se toca si estaba apagada.
    private static func showMarkupToolbar() {
        let domain = (NSHomeDirectory() + "/Library/Containers/\(previewID)/Data/Library/Preferences/\(previewID)") as CFString
        let key = "PVMarkupToolbarVisibleForImages" as CFString
        CFPreferencesAppSynchronize(domain)
        guard CFPreferencesCopyAppValue(key, domain) as? Bool != true else { return }
        CFPreferencesSetAppValue(key, kCFBooleanTrue, domain)
        CFPreferencesAppSynchronize(domain)
    }
}
