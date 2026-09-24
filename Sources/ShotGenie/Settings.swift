import AppKit
import ShotGenieCore
import SwiftUI

/// Preferencias guardadas en `com.enderj.screencapture`.
enum Settings {
    static let magnificationKey = "magnification"
    static let genieKey = "genieEnabled"

    /// Efecto genio al capturar (activado si nunca se tocó).
    static var genieEnabled: Bool {
        UserDefaults.standard.object(forKey: genieKey) as? Bool ?? true
    }

    static var magnification: CGFloat {
        let stored = UserDefaults.standard.object(forKey: magnificationKey) as? Double
        return FanLayout.clampMagnification(stored.map { CGFloat($0) } ?? FanLayout.defaultMagnification)
    }
}

struct SettingsView: View {
    let store: CaptureStore

    @AppStorage(Settings.magnificationKey) private var magnification = Double(FanLayout.defaultMagnification)
    @AppStorage(Settings.genieKey) private var genieEnabled = true
    @State private var axTrusted = DockLocator.isTrusted

    private var range: ClosedRange<Double> {
        Double(FanLayout.magnificationRange.lowerBound)...Double(FanLayout.magnificationRange.upperBound)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Efecto lupa").font(.system(size: 13, weight: .semibold))
                Text("Cuánto se amplía una captura al pasar el cursor por el abanico.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Image(systemName: "minus.magnifyingglass").foregroundStyle(.secondary)
                Slider(value: $magnification, in: range, step: 0.1)
                    .accessibilityLabel("Ampliación de la lupa")
                    .accessibilityValue(Self.format(magnification))
                Image(systemName: "plus.magnifyingglass").foregroundStyle(.secondary)
                Text(Self.format(magnification))
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .frame(width: 44, alignment: .trailing)
            }

            preview

            Divider()

            Toggle(isOn: $genieEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Efecto genio al capturar").font(.system(size: 13, weight: .semibold))
                    Text("La captura aparece en grande y se mete en el icono del Dock.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: axTrusted ? "checkmark.circle.fill" : "scope")
                    .foregroundStyle(axTrusted ? Color.green : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(axTrusted ? "El genio va exacto al icono del Dock" : "El genio va a donde hiciste clic en el icono")
                        .font(.system(size: 12, weight: .medium))
                    if !axTrusted {
                        Text("Para ir siempre al sitio exacto, permite Accesibilidad: la app solo lee la posición de su icono.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                if !axTrusted {
                    Button("Permitir…") { DockLocator.requestAccess() }
                }
            }
            .disabled(!genieEnabled)
            .opacity(genieEnabled ? 1 : 0.5)
            .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
                axTrusted = DockLocator.isTrusted
            }

            HStack {
                Text("La lupa se aplica la próxima vez que abras el abanico.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button("Restablecer") { magnification = Double(FanLayout.defaultMagnification) }
                    .disabled(abs(magnification - Double(FanLayout.defaultMagnification)) < 0.05)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    /// Vista previa con la última captura: en reposo y ampliada al valor elegido.
    private var preview: some View {
        let m = CGFloat(FanLayout.clampMagnification(CGFloat(magnification)))
        let small = FanLayout.thumb
        let maxBox = CGSize(width: small.width * FanLayout.magnificationRange.upperBound,
                            height: small.height * FanLayout.magnificationRange.upperBound)
        return HStack(alignment: .center, spacing: 18) {
            VStack(spacing: 6) {
                thumb.frame(width: small.width, height: small.height)
                Text("En reposo").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            VStack(spacing: 6) {
                thumb
                    .frame(width: small.width, height: small.height)
                    .scaleEffect(m)
                    .frame(width: small.width * m, height: small.height * m)
                    .animation(.spring(response: 0.22, dampingFraction: 0.8), value: m)
                Text("Con la lupa").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .frame(width: maxBox.width * 0.62, height: maxBox.height * 0.62 + 20)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder private var thumb: some View {
        if let url = store.captures.first?.url, let image = Thumbnailer.thumbnail(for: url) {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(.white.opacity(0.9), lineWidth: 1.5))
                .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
        } else {
            RoundedRectangle(cornerRadius: 4).fill(.gray.opacity(0.35))
        }
    }

    static func format(_ m: Double) -> String {
        "×" + String(format: "%.1f", m).replacingOccurrences(of: ".", with: ",")
    }
}

@MainActor
final class SettingsWindowController {
    private let store: CaptureStore
    private var window: NSWindow?

    init(store: CaptureStore) {
        self.store = store
    }

    func show() {
        if window == nil {
            let host = NSHostingController(rootView: SettingsView(store: store))
            let w = NSWindow(contentViewController: host)
            w.title = "Ajustes de ShotGenie"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
