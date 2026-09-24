import AppKit
import ShotGenieCore
import SwiftUI

/// Dibuja las imágenes del README con capturas de ejemplo, usando las vistas reales de la app.
/// Uso: `ShotGenie --render-docs <carpeta de capturas> <carpeta de salida>` (ver scripts/docs/render.sh).
@MainActor
enum DocsRenderer {
    static let scene = CGSize(width: 1280, height: 800)

    static func run(captures: URL, output: URL) {
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let store = CaptureStore(folder: captures)
        store.reload()
        let caps = store.captures
        guard caps.count >= 2 else { print("hacen falta al menos 2 capturas en \(captures.path)"); return }

        let newest = caps[0], previous = caps[1]
        let iconNew = DockIcon.render(thumbnail: Thumbnailer.thumbnail(for: newest.url), badge: .camera)
        let iconOld = DockIcon.render(thumbnail: Thumbnailer.thumbnail(for: previous.url), badge: .camera)
        let iconCopied = DockIcon.render(thumbnail: Thumbnailer.thumbnail(for: newest.url), badge: .copied)
        let appIcon = DockIcon.render(thumbnail: nil, badge: .camera)

        // 1. Estados del icono
        save(IconStates(icons: [(appIcon, "No screenshots yet"), (iconNew, "Latest screenshot"), (iconCopied, "Just copied")]),
             scale: 2, to: output.appendingPathComponent("icon-states.png"))

        // 2. Abanico con lupa sobre la segunda captura
        let rows = caps.count + 1
        let m = Settings.magnification
        let fan = CGSize(width: FanLayout.width(rows: rows, magnification: m), height: FanLayout.height(rows: rows, magnification: m))
        let dock = DockLayout(width: scene.width, height: max(scene.height, fan.height + 140))
        let fanOrigin = CGPoint(x: dock.targetCenter.x - FanLayout.anchorX, y: dock.barY - 6 - fan.height)
        // Recorte: el abanico y el Dock, con margen.
        let crop = CGRect(x: min(fanOrigin.x, dock.barX) - 40, y: fanOrigin.y - 30, width: 0, height: 0)
        let cropSize = CGSize(width: max(fanOrigin.x + fan.width, dock.barX + dock.barWidth) + 40 - crop.minX,
                              height: dock.height - crop.minY)
        save(Desktop(dock: dock, icon: iconNew) {
            FanView(store: store, onCopy: { _, _ in }, onOpenFolder: {}, onDismiss: {}, initialHover: 1)
                .frame(width: fan.width, height: fan.height)
                .offset(x: fanOrigin.x, y: fanOrigin.y)
        }
        .offset(x: -crop.minX, y: -crop.minY)
        .frame(width: cropSize.width, height: cropSize.height, alignment: .topLeading)
        .clipped(), scale: 1.25, to: output.appendingPathComponent("fan.png"))

        // 2b. Abanico con la imagen creciendo a la izquierda (icono cerca del borde derecho); no va al README
        save(FanView(store: store, onCopy: { _, _ in }, onOpenFolder: {}, onDismiss: {}, initialHover: 1, growsLeft: true)
                .frame(width: fan.width, height: fan.height)
                .background(Color(white: 0.3)),
             scale: 1, to: output.appendingPathComponent("fan-left.png"))

        // 3. Fotogramas del genio (la captura más nueva entra en el icono)
        guard let image = Thumbnailer.thumbnail(for: newest.url, maxPixel: 1200),
              let pixels = Thumbnailer.pixelSize(of: newest.url) else { return }
        let desk = DockLayout(width: scene.width, height: scene.height)
        let rect = Genie.startRect(imagePoints: CGSize(width: pixels.width / 2, height: pixels.height / 2),
                                   in: CGRect(origin: .zero, size: scene))
        let target = Genie.safeTarget(desk.targetCenter, rect: rect, screen: scene)
        let frames = output.appendingPathComponent("genie-frames")
        try? FileManager.default.removeItem(at: frames)
        try? FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true)
        let fps = 20.0
        let genieCount = Int(Genie.duration * fps)
        var n = 0
        func frame(_ icon: NSImage, progress: Double?) {
            let view = Desktop(dock: desk, icon: icon) {
                if let progress {
                    GenieFrame(image: image, rect: rect, target: target, progress: progress)
                        .frame(width: scene.width, height: scene.height)
                }
            }
            save(view, scale: 0.75, to: frames.appendingPathComponent(String(format: "%03d.png", n)))
            n += 1
        }
        for _ in 0..<8 { frame(iconOld, progress: nil) }
        for i in 0...genieCount { frame(iconOld, progress: Double(i) / Double(genieCount)) }
        for _ in 0..<24 { frame(iconNew, progress: nil) }
        // 4. Ajustes (vista real de la app, en una ventana que no se muestra)
        let host = NSHostingView(rootView: SettingsView(store: store).background(Color(nsColor: .windowBackgroundColor)))
        host.appearance = NSAppearance(named: .darkAqua)
        host.frame = CGRect(origin: .zero, size: host.fittingSize)
        host.layoutSubtreeIfNeeded()
        if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: output.appendingPathComponent("settings.png"))
        }
        print("imágenes en \(output.path) (\(n) fotogramas del genio)")
    }

    private static func save(_ view: some View, scale: CGFloat, to url: URL) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        guard let cg = renderer.cgImage else { print("no se pudo dibujar \(url.lastPathComponent)"); return }
        try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?.write(to: url)
    }
}

/// Un Dock de ejemplo abajo al centro; el icono de ShotGenie va en el 5.º de 7 puestos (no en el medio).
struct DockLayout {
    let width: CGFloat, height: CGFloat
    static let tile: CGFloat = 58, spacing: CGFloat = 12, pad: CGFloat = 14, barHeight: CGFloat = 82
    static let count = 7, target = 4

    var barWidth: CGFloat { CGFloat(Self.count) * Self.tile + CGFloat(Self.count - 1) * Self.spacing + 2 * Self.pad }
    var barX: CGFloat { (width - barWidth) / 2 }
    var barY: CGFloat { height - 10 - Self.barHeight }
    func center(_ i: Int) -> CGPoint {
        CGPoint(x: barX + Self.pad + Self.tile / 2 + CGFloat(i) * (Self.tile + Self.spacing), y: barY + Self.barHeight / 2)
    }
    var targetCenter: CGPoint { center(Self.target) }
}

/// Escritorio de ejemplo: fondo, Dock con apps genéricas y el icono de ShotGenie, y lo que se ponga encima.
private struct Desktop<Overlay: View>: View {
    let dock: DockLayout
    let icon: NSImage
    @ViewBuilder let overlay: () -> Overlay

    static var apps: [(String, Color)] {
        [("folder.fill", Color(red: 0.25, green: 0.55, blue: 0.95)), ("globe", Color(red: 0.18, green: 0.62, blue: 0.85)),
         ("envelope.fill", Color(red: 0.2, green: 0.45, blue: 0.9)), ("terminal.fill", Color(white: 0.18)),
         ("", .clear), ("note.text", Color(red: 0.95, green: 0.75, blue: 0.2)), ("gearshape.fill", Color(white: 0.55))]
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Color(red: 0.17, green: 0.24, blue: 0.34), Color(red: 0.42, green: 0.53, blue: 0.68)],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color.white.opacity(0.18), .clear], center: UnitPoint(x: 0.75, y: 0.2), startRadius: 0, endRadius: 520)

            RoundedRectangle(cornerRadius: 24)
                .fill(Color.white.opacity(0.22))
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.white.opacity(0.35), lineWidth: 1))
                .frame(width: dock.barWidth, height: DockLayout.barHeight)
                .offset(x: dock.barX, y: dock.barY)

            ForEach(0..<DockLayout.count, id: \.self) { i in
                let c = dock.center(i)
                Group {
                    if i == DockLayout.target {
                        Crisp(image: icon, side: DockLayout.tile)
                    } else {
                        RoundedRectangle(cornerRadius: 11)
                            .fill(Self.apps[i].1.gradient)
                            .frame(width: DockLayout.tile * 0.8, height: DockLayout.tile * 0.8)
                            .overlay(Image(systemName: Self.apps[i].0).font(.system(size: 22, weight: .semibold)).foregroundStyle(.white))
                            .frame(width: DockLayout.tile, height: DockLayout.tile)
                    }
                }
                .offset(x: c.x - DockLayout.tile / 2, y: c.y - DockLayout.tile / 2)
            }
            overlay()
        }
        .frame(width: dock.width, height: dock.height, alignment: .topLeading)
        .clipped()
    }
}

private struct IconStates: View {
    let icons: [(NSImage, String)]
    var body: some View {
        HStack(spacing: 36) {
            ForEach(Array(icons.enumerated()), id: \.offset) { _, item in
                VStack(spacing: 10) {
                    Crisp(image: item.0, side: 160)
                    Text(item.1).font(.system(size: 15, weight: .medium)).foregroundStyle(Color(white: 0.25))
                }
            }
        }
        .padding(.horizontal, 36).padding(.vertical, 28)
        .background(Color(red: 0.95, green: 0.96, blue: 0.98))
    }
}

/// Un NSImage de varios tamaños (icns) dibujado con su versión grande, no la primera que encuentre.
private struct Crisp: View {
    let image: NSImage
    let side: CGFloat
    var body: some View {
        var rect = CGRect(x: 0, y: 0, width: 1024, height: 1024)
        if let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) {
            Image(decorative: cg, scale: 1).resizable().interpolation(.high).frame(width: side, height: side)
        } else {
            Image(nsImage: image).resizable().frame(width: side, height: side)
        }
    }
}
