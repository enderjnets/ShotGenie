import AppKit
import ShotGenieCore
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = CaptureStore()
    private lazy var panel = PanelController(store: store)
    private lazy var settings = SettingsWindowController(store: store)
    private let genie = GenieController()
    /// La captura más nueva ya vista: una distinta y reciente dispara el efecto genio.
    private var lastNewest: URL?
    private var badge: DockIcon.Badge = .camera
    private var badgeReset: DispatchWorkItem?
    /// La última app activa que no es esta: a ella se devuelve el foco tras copiar.
    private var lastOtherApp: NSRunningApplication?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Solo depuración: `defaults write com.enderj.screencapture debugStatusPath /ruta.txt`.
        if let path = UserDefaults.standard.string(forKey: "debugStatusPath") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                let status = "accesibilidad=\(DockLocator.isTrusted) icono=\(String(describing: DockLocator.iconRect()))\n"
                try? status.write(toFile: path, atomically: true, encoding: .utf8)
            }
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.mainMenu = buildMainMenu()
        store.onChange = { [weak self] in self?.capturesChanged() }
        store.start()
        lastNewest = store.captures.first?.url
        refreshIcon()

        panel.onCopied = { [weak self] _, _ in self?.flashCopied() }
        panel.onOpenFolder = { [weak self] in self?.openFolder() }
        panel.returnFocus = { [weak self] in self?.returnFocus() }

        lastOtherApp = NSWorkspace.shared.frontmostApplication.flatMap { $0 == .current ? nil : $0 }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app != .current else { return }
            MainActor.assumeIsolated { self?.lastOtherApp = app }
        }
    }

    func applicationDidResignActive(_ notification: Notification) {
        panel.appDidResignActive()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Por si se cambió la carpeta de capturas en Ajustes mientras la app estaba abierta.
        store.start()
    }

    /// Clic en el icono del Dock con la app ya abierta.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        GenieController.rememberDockPoint(NSEvent.mouseLocation)
        panel.toggle()
        return false
    }

    // MARK: - Icono

    private func capturesChanged() {
        let newest = store.captures.first
        defer { lastNewest = newest?.url }
        // Captura nueva de verdad (no la carga inicial ni un archivo viejo movido a la carpeta):
        // la miniatura del icono cambia cuando el genio termina de «entrar» en él.
        if let newest, newest.url != lastNewest, Date().timeIntervalSince(newest.created) < 10, Settings.genieEnabled {
            genie.play(url: newest.url) { [weak self] in self?.refreshIcon() }
        } else {
            refreshIcon()
        }
    }

    private func refreshIcon() {
        let thumb = store.captures.first.flatMap { Thumbnailer.thumbnail(for: $0.url, maxPixel: 512) }
        let image = DockIcon.render(thumbnail: thumb, badge: badge)
        NSApp.applicationIconImage = image
        DockIcon.writeDebugCopy(image)
    }

    private func flashCopied() {
        badge = .copied
        refreshIcon()
        badgeReset?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.badge = .camera
                self?.refreshIcon()
            }
        }
        badgeReset = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }

    private func returnFocus() {
        if let app = lastOtherApp, !app.isTerminated, app.activate() { return }
        NSApp.hide(nil)
    }

    // MARK: - Menú de clic derecho

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        store.reload()
        let menu = NSMenu()
        menu.addItem(NSMenuItem.sectionHeader(title: "Últimas capturas"))

        if store.captures.isEmpty {
            let empty = NSMenuItem(title: "Aún no hay capturas", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        for capture in store.captures {
            let ago = RelativeTime.format(capture.created)
            let item = NSMenuItem(title: "Captura · \(ago)", action: #selector(menuCopyImage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = capture.url
            if let thumb = Thumbnailer.thumbnail(for: capture.url) {
                let small = NSImage(size: NSSize(width: 32, height: 20), flipped: false) { rect in
                    thumb.draw(in: rect)
                    return true
                }
                item.image = small
            }
            menu.addItem(item)

            let alt = NSMenuItem(title: "Copiar ruta · \(ago)", action: #selector(menuCopyPath(_:)), keyEquivalent: "")
            alt.target = self
            alt.representedObject = capture.url
            alt.isAlternate = true
            alt.keyEquivalentModifierMask = .option
            alt.image = item.image
            menu.addItem(alt)
        }
        if !store.captures.isEmpty {
            let hint = NSMenuItem(title: "Clic: copia la imagen · con ⌥: la ruta", action: nil, keyEquivalent: "")
            hint.isEnabled = false
            menu.addItem(hint)
        }

        menu.addItem(.separator())
        let lastPath = NSMenuItem(title: "Copiar ruta de la última", action: #selector(menuCopyLatestPath), keyEquivalent: "")
        lastPath.target = self
        lastPath.isEnabled = !store.captures.isEmpty
        menu.addItem(lastPath)
        let folder = NSMenuItem(title: "Abrir carpeta de capturas", action: #selector(openFolder), keyEquivalent: "")
        folder.target = self
        menu.addItem(folder)
        let prefs = NSMenuItem(title: "Ajustes…", action: #selector(openSettings), keyEquivalent: "")
        prefs.target = self
        menu.addItem(prefs)

        menu.addItem(.separator())
        let login = NSMenuItem(title: "Abrir al iniciar sesión", action: #selector(toggleLoginItem), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        return menu
    }

    @objc private func menuCopyImage(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        if Clipboard.copyImage(url) { flashCopied() }
    }

    @objc private func menuCopyPath(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        if Clipboard.copyPath(url) { flashCopied() }
    }

    @objc private func menuCopyLatestPath() {
        guard let url = store.captures.first?.url else { return }
        if Clipboard.copyPath(url) { flashCopied() }
    }

    /// Menú de la app en la barra superior: Ajustes (⌘,) y Salir (⌘Q).
    private func buildMainMenu() -> NSMenu {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu(title: "ShotGenie")
        let prefs = NSMenuItem(title: "Ajustes…", action: #selector(openSettings), keyEquivalent: ",")
        prefs.target = self
        appMenu.addItem(prefs)
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Salir de ShotGenie", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        return main
    }

    @objc private func openSettings() {
        panel.close(returnFocus: false)
        settings.show()
    }

    @objc private func openFolder() {
        NSWorkspace.shared.open(store.folder)
    }

    @objc private func toggleLoginItem() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("ShotGenie: inicio de sesión falló: \(error.localizedDescription)")
        }
    }
}
