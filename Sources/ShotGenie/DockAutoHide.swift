import Foundation

/// Mientras el abanico está abierto, el Dock no debe esconderse (si no, el abanico queda colgando).
/// macOS no ofrece una API pública para esto: se usa CoreDockSetAutoHideEnabled, la misma que usa
/// Ajustes del Sistema, cargada con dlsym. Si la app se cierra de golpe con el Dock fijado, lo
/// restaura al volver a abrirse (`restoreDockAutoHide`).
enum DockAutoHide {
    private typealias SetFn = @convention(c) (Bool) -> Void
    private static let key = "restoreDockAutoHide"

    private static let set: SetFn? = {
        guard let h = dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_NOW),
              let p = dlsym(h, "CoreDockSetAutoHideEnabled") else { return nil }
        return unsafeBitCast(p, to: SetFn.self)
    }()

    /// Lo que dicen las preferencias del Dock (CoreDockGetAutoHideEnabled no siempre está al día).
    private static var isEnabled: Bool {
        CFPreferencesAppSynchronize("com.apple.dock" as CFString)
        return CFPreferencesCopyAppValue("autohide" as CFString, "com.apple.dock" as CFString) as? Bool ?? false
    }

    /// Fija el Dock si estaba en ocultado automático.
    static func suspend() {
        guard let set, !UserDefaults.standard.bool(forKey: key), isEnabled else { return }
        UserDefaults.standard.set(true, forKey: key)
        set(false)
    }

    /// Devuelve el ocultado automático si lo quitó `suspend()`.
    static func resume() {
        guard let set, UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.removeObject(forKey: key)
        set(true)
    }
}
