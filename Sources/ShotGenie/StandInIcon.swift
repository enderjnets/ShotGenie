import AppKit

/// Icono de relevo: en pantalla completa macOS esconde el Dock en cuanto el cursor sube al abanico
/// (no se puede evitar). Mientras el Dock no está, se dibuja una copia del icono en su sitio para
/// que el abanico no quede colgando. Un clic en ella cierra el abanico, como en el icono real.
@MainActor
final class StandInIcon {
    private var window: NSPanel?
    private var timer: Timer?
    private var frame: CGRect = .zero
    private var screen: CGRect = .zero
    var onClick: (() -> Void)?

    /// Empieza a vigilar el Dock. `frame`: el icono al abrir el abanico (coordenadas de AppKit).
    func start(iconFrame: CGRect, screen: CGRect) {
        stop()
        frame = iconFrame
        self.screen = screen
        timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        window?.orderOut(nil)
        window = nil
    }

    private func check() {
        // Con el Dock escondido, sus iconos quedan por debajo del borde inferior de la pantalla.
        let current = DockLocator.iconFrame()
        let hidden = current.map { $0.maxY <= screen.minY + 2 } ?? true
        if hidden { show() } else { hide() }
    }

    private func show() {
        if window == nil {
            let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = .popUpMenu
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
            let view = ClickImageView(frame: CGRect(origin: .zero, size: frame.size))
            view.image = NSApp.applicationIconImage
            view.imageScaling = .scaleProportionallyUpOrDown
            view.onClick = { [weak self] in self?.onClick?() }
            panel.contentView = view
            panel.alphaValue = 0
            window = panel
        }
        guard let window, window.alphaValue < 1 || !window.isVisible else { return }
        window.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.15; window.animator().alphaValue = 1 }
        DebugLog.note("Dock escondido: icono de relevo en \(frame)")
    }

    private func hide() {
        guard let window, window.isVisible else { return }
        window.orderOut(nil)
        window.alphaValue = 0
        DebugLog.note("Dock visible: se quita el icono de relevo")
    }
}

private final class ClickImageView: NSImageView {
    var onClick: (() -> Void)?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onClick?() }
}
