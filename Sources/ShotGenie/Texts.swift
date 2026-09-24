import Foundation
import ShotGenieCore

/// Textos que dependen de datos. Las claves están en inglés; las traducciones viven en
/// Resources/<idioma>.lproj/Localizable.strings y macOS elige según el idioma del sistema.
enum Texts {
    static func ago(_ date: Date, now: Date = Date()) -> String {
        guard let (n, unit) = RelativeTime.ago(date, now: now) else { return String(localized: "now") }
        switch unit {
        case .seconds: return String(localized: "\(n) s ago")
        case .minutes: return String(localized: "\(n) min ago")
        case .hours: return String(localized: "\(n) h ago")
        case .days: return String(localized: "\(n) d ago")
        }
    }

    static func number(_ n: Int) -> String {
        n.formatted(.number.grouping(.automatic))
    }

    /// «×4.2» o «×4,2» según el idioma.
    static func magnification(_ m: Double) -> String {
        "×" + m.formatted(.number.precision(.fractionLength(1)))
    }
}
