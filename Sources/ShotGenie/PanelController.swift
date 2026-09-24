import AppKit
import ShotGenieCore
import SwiftUI

/// Ventana transparente del abanico, sin borde; acepta teclado (para Esc) y se cierra al perder el foco.
final class KeyPanel: NSPanel {
    var onEscape: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onEscape?() }
}

@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private let store: CaptureStore
    private var panel: KeyPanel?
    /// Se llama tras copiar desde el panel (el icono se pone verde y se devuelve el foco).
    var onCopied: ((Capture, FanView.CopyKind) -> Void)?
    var onOpenFolder: (() -> Void)?
    var returnFocus: (() -> Void)?

    init(store: CaptureStore) {
        self.store = store
    }

    var isVisible: Bool { panel?.isVisible == true }

    func toggle() {
        if isVisible { close(returnFocus: true) } else { show() }
    }

    func show() {
        store.reload()
        let view = FanView(
            store: store,
            onCopy: { [weak self] capture, kind in self?.didCopy(capture, kind) },
            onOpenFolder: { [weak self] in
                self?.close(returnFocus: false)
                self?.onOpenFolder?()
            },
            onDismiss: { [weak self] in self?.close(returnFocus: true) },
            initialHover: UserDefaults.standard.object(forKey: "debugHover") as? Int
        )
        let host = NSHostingView(rootView: view)
        let rows = store.captures.count + 1
        let m = Settings.magnification
        let size = CGSize(width: FanLayout.width(rows: rows, magnification: m), height: FanLayout.height(rows: rows, magnification: m))

        let panel = KeyPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false  // la sombra la llevan las píldoras y miniaturas
        panel.isReleasedWhenClosed = false
        panel.contentView = host
        panel.delegate = self
        panel.onEscape = { [weak self] in self?.close(returnFocus: true) }

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        if let screen {
            let origin = PanelPlacement.origin(mouse: mouse, panel: size, anchorX: FanLayout.anchorX, screen: screen.frame, visible: screen.visibleFrame)
            panel.setFrameOrigin(origin)
        }

        self.panel?.orderOut(nil)
        self.panel = panel
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        writeDebugSnapshot(of: host)
    }

    /// Solo para verificar el aspecto: `defaults write com.enderj.screencapture debugPanelPath /ruta.png`.
    private func writeDebugSnapshot(of view: NSView) {
        guard let path = UserDefaults.standard.string(forKey: "debugPanelPath") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        }
    }

    func close(returnFocus shouldReturn: Bool) {
        guard let panel else { return }
        panel.delegate = nil
        panel.orderOut(nil)
        self.panel = nil
        if shouldReturn { returnFocus?() }
    }

    private func didCopy(_ capture: Capture, _ kind: FanView.CopyKind) {
        let ok = kind == .image ? Clipboard.copyImage(capture.url) : Clipboard.copyPath(capture.url)
        guard ok else { return }
        onCopied?(capture, kind)
        // Deja ver la confirmación y devuelve el foco a la app anterior (la terminal) para pegar ya.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            MainActor.assumeIsolated { self?.close(returnFocus: true) }
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        // Clic en otra app: el foco ya va adonde el usuario hizo clic.
        // Si la que toma el foco es otra ventana de esta app (Ajustes), el abanico sigue abierto.
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                if !NSApp.isActive { self?.close(returnFocus: false) }
            }
        }
    }

    /// Se llama cuando esta app deja de estar activa (clic en otra app, ⌘Tab…).
    func appDidResignActive() {
        close(returnFocus: false)
    }
}
