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
                Text("Magnifier").font(.system(size: 13, weight: .semibold))
                Text("How much a screenshot grows when the cursor passes over it in the fan.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 12) {
                Image(systemName: "minus.magnifyingglass").foregroundStyle(.secondary)
                Slider(value: $magnification, in: range, step: 0.1)
                    .accessibilityLabel("Magnifier zoom")
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
                    Text("Genie effect on capture").font(.system(size: 13, weight: .semibold))
                    Text("The screenshot appears large and genies into the Dock icon.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: axTrusted ? "checkmark.circle.fill" : "scope")
                    .foregroundStyle(axTrusted ? Color.green : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(axTrusted ? LocalizedStringKey("The genie goes exactly to the Dock icon") : LocalizedStringKey("The genie goes where you last clicked the icon"))
                        .font(.system(size: 12, weight: .medium))
                    if !axTrusted {
                        Text("To always hit the exact spot, allow Accessibility. The app only reads the position of its own icon.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                if !axTrusted {
                    Button("Allow…") { DockLocator.requestAccess() }
                }
            }
            .disabled(!genieEnabled)
            .opacity(genieEnabled ? 1 : 0.5)
            .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
                axTrusted = DockLocator.isTrusted
            }

            HStack {
                Text("The magnifier applies the next time you open the fan.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button("Reset") { magnification = Double(FanLayout.defaultMagnification) }
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
        // A escala: con la lupa al máximo la miniatura real (456 pt) no cabría en la ventana.
        let k = Self.previewScale
        return HStack(alignment: .center, spacing: 18) {
            VStack(spacing: 6) {
                thumb.frame(width: small.width * k, height: small.height * k)
                Text("At rest").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            VStack(spacing: 6) {
                thumb
                    .frame(width: small.width * k * m, height: small.height * k * m)
                    .animation(.spring(response: 0.22, dampingFraction: 0.8), value: m)
                Text("Magnified").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .frame(width: maxBox.width * k, height: maxBox.height * k + 20)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    static let previewScale: CGFloat = 0.62

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

    static func format(_ m: Double) -> String { Texts.magnification(m) }
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
            w.title = String(localized: "ShotGenie Settings")
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
