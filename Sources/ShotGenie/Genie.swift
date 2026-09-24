import AppKit
import ShotGenieCore
import SwiftUI

/// Dibuja un fotograma del efecto genio. `progress` ∈ [0, 1].
struct GenieFrame: View {
    let image: NSImage
    let rect: CGRect      // imagen de partida, coordenadas locales con y hacia abajo
    let target: CGPoint   // el icono del Dock, mismas coordenadas
    let progress: Double

    /// Franjas finas (~1,5 pt en una captura típica) para que el borde del embudo se vea curvo, no escalonado.
    static let strips = 240

    var body: some View {
        Canvas { gc, size in
            let img = gc.resolve(Image(nsImage: image))
            let p = Genie.phases(progress)
            if p.curve == 0 && p.slide == 0 {
                // Aparece: de 0,92 a tamaño real, con sombra.
                let s = 0.92 + 0.08 * p.appear
                let r = CGRect(x: rect.midX - rect.width * s / 2, y: rect.midY - rect.height * s / 2,
                               width: rect.width * s, height: rect.height * s)
                gc.opacity = p.appear
                var shadowed = gc
                shadowed.addFilter(.shadow(color: .black.opacity(0.35), radius: 18, y: 8))
                shadowed.fill(Path(roundedRect: r, cornerRadius: 6), with: .color(.black))
                gc.clip(to: Path(roundedRect: r, cornerRadius: 6))
                gc.draw(img, in: r)
                return
            }
            // El embudo se calcula siempre «hacia abajo» y se gira hacia donde esté el icono.
            let dir = Genie.direction(rect: rect, target: target)
            let space = Genie.genieSpace(rect: rect, target: target, canvas: size, direction: dir)
            gc.concatenate(Genie.screenTransform(dir, canvas: size))
            let n = Self.strips
            for i in 0..<n {
                guard let s = Genie.strip(v0: CGFloat(i) / CGFloat(n), v1: CGFloat(i + 1) / CGFloat(n), rect: space.rect,
                                          target: space.target, curve: p.curve, slide: p.slide) else { continue }
                var c = gc
                // Medio punto de solape para que no se vean rendijas entre franjas.
                c.clip(to: Path(s.dest.insetBy(dx: 0, dy: -0.5)))
                let (draw, local) = Genie.imageTransform(direction: dir, into: s.image)
                c.concatenate(local)
                c.draw(img, in: draw)
            }
        }
        // Dibujo en la GPU: 240 franjas por fotograma a 60 fps.
        .drawingGroup()
    }
}

private struct GenieAnimation: View {
    let image: NSImage
    let rect: CGRect
    let target: CGPoint
    let start: Date

    var body: some View {
        TimelineView(.animation) { ctx in
            GenieFrame(image: image, rect: rect, target: target,
                       progress: min(ctx.date.timeIntervalSince(start) / Genie.duration, 1))
        }
    }
}

/// Lanza el efecto genio en una ventana transparente que no roba el foco ni los clics.
@MainActor
final class GenieController {
    private var window: NSPanel?
    private var finish: DispatchWorkItem?

    static let dockPointKey = "dockIconPoint"

    /// Guarda dónde está el icono: el cursor está sobre él cuando se hace clic en el Dock.
    static func rememberDockPoint(_ p: CGPoint) {
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(p, $0.frame, false) }),
              p.y - screen.frame.minY < 160 else { return }   // solo si el clic vino del Dock (abajo)
        UserDefaults.standard.set([p.x, p.y], forKey: dockPointKey)
    }

    private static func rememberedPoint() -> CGPoint? {
        guard let xy = UserDefaults.standard.array(forKey: dockPointKey) as? [Double], xy.count == 2 else { return nil }
        return CGPoint(x: xy[0], y: xy[1])
    }

    /// Adónde cae el genio: el icono según el Dock (Accesibilidad), si no el último clic en él,
    /// si no abajo al centro. Con el Dock oculto, al borde inferior de su pantalla.
    static func target() -> (CGPoint, NSScreen) {
        let screens = NSScreen.screens
        if let item = DockLocator.iconRect(),
           let i = DockGeometry.screenIndex(item: item, screens: DockLocator.screenRectsTopLeft()) {
            let s = screens[i]
            let tl = DockLocator.screenRectsTopLeft()[i]
            let centerY = s.frame.maxY - (item.midY - tl.minY)          // a coordenadas de AppKit
            let y = min(max(centerY, s.frame.minY + 4), s.frame.maxY)
            return (CGPoint(x: item.midX, y: y), s)
        }
        if let p = rememberedPoint(), let s = screens.first(where: { NSMouseInRect(p, $0.frame, false) }) {
            return (p, s)
        }
        let s = NSScreen.main ?? screens[0]
        return (CGPoint(x: s.frame.midX, y: s.frame.minY + 4), s)
    }

    func play(url: URL, completion: @escaping () -> Void) {
        guard let image = Thumbnailer.thumbnail(for: url, maxPixel: 1200),
              let pixels = Thumbnailer.pixelSize(of: url) else { completion(); return }

        // El genio se ve en la pantalla de la captura (donde está el cursor al terminarla) y sale
        // hacia el icono: si el Dock está en otra pantalla, hacia el borde de esta más cercano a él.
        let mouse = NSEvent.mouseLocation
        let forced = (UserDefaults.standard.object(forKey: "debugGenieScreen") as? Int)   // solo depuración
            .flatMap { NSScreen.screens.indices.contains($0) ? NSScreen.screens[$0] : nil }
        let screen = forced ?? NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main ?? NSScreen.screens[0]
        let frame = screen.frame
        let icon = Genie.pointOnScreen(Self.target().0, screen: frame)
        let points = CGSize(width: pixels.width / screen.backingScaleFactor, height: pixels.height / screen.backingScaleFactor)
        let rect = Genie.startRect(imagePoints: points, in: CGRect(origin: .zero, size: frame.size))
        let target = Genie.safeTarget(CGPoint(x: icon.x - frame.minX, y: frame.maxY - icon.y), rect: rect, screen: frame.size)

        writeDebugFrames(image: image, rect: rect, target: target, size: frame.size)

        finish?.perform()
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: GenieAnimation(image: image, rect: rect, target: target, start: Date()))
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        window = panel

        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.window?.orderOut(nil)
                self?.window = nil
                self?.finish = nil
                completion()
            }
        }
        finish = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Genie.duration + 0.05, execute: work)
    }

    /// Solo para verificar sin mirar la pantalla: `defaults write com.enderj.screencapture debugGenieDir /carpeta`.
    private func writeDebugFrames(image: NSImage, rect: CGRect, target: CGPoint, size: CGSize) {
        guard let dir = UserDefaults.standard.string(forKey: "debugGenieDir") else { return }
        for t in [0.1, 0.45, 0.6, 0.72, 0.85, 0.95] {
            let renderer = ImageRenderer(content: GenieFrame(image: image, rect: rect, target: target, progress: t)
                .frame(width: size.width, height: size.height)
                .background(Color(white: 0.5)))
            renderer.scale = 0.5
            guard let cg = renderer.cgImage else { continue }
            let rep = NSBitmapImageRep(cgImage: cg)
            try? rep.representation(using: .png, properties: [:])?
                .write(to: URL(fileURLWithPath: dir).appendingPathComponent(String(format: "genie-%.2f.png", t)))
        }
    }
}
