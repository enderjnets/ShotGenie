import Foundation

/// Dónde deja el instalador del DMG la app.
public enum InstallDestination {
    public static let appName = "ShotGenie.app"

    /// Siempre en Aplicaciones (/Applications), reemplazando la copia que haya. Solo si macOS no
    /// deja escribir ahí (usuario estándar, no administrador) va a ~/Applications.
    public static func choose(systemApplications: URL, userApplications: URL, systemWritable: Bool) -> URL {
        (systemWritable ? systemApplications : userApplications).appendingPathComponent(appName)
    }
}
