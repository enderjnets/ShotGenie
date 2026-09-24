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
        let fanOrigin = fanTopLeft(dock: dock, fan: fan, magnification: m)
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
        var n = 0

        // Demo completa: ⌘⇧4 sobre una ventana → genio → clic en el icono → abanico → lupa → copiar.
        let deskFan = fanTopLeft(dock: desk, fan: fan, magnification: m)
        let iconC = desk.targetCenter
        func thumbCenter(_ k: Int) -> CGPoint {
            CGPoint(x: deskFan.x + FanLayout.anchorX + FanLayout.placement(row: k).dx,
                    y: deskFan.y + FanLayout.centerY(row: k, height: fan.height, magnification: m))
        }
        var scales = [CGFloat](repeating: 1, count: caps.count)
        var hovered: Int?
        // La ventana que se captura: la página de la captura más nueva, con su proporción.
        let content = CGRect(x: 270, y: 204, width: 600, height: 600 * pixels.height / pixels.width)

        func frame(_ icon: NSImage, genie: Double? = nil, fanOpen: Bool = false, cursor: CGPoint? = nil,
                   pressed: Bool = false, copied: URL? = nil,
                   crosshair: CGPoint? = nil, selection: CGRect? = nil, keys: Bool = false) {
            // La lupa se acerca a su tamaño poco a poco, como el muelle de la app.
            for k in scales.indices {
                let goal: CGFloat = fanOpen && hovered == k ? m : 1
                scales[k] += (goal - scales[k]) * 0.5
            }
            let view = Desktop(dock: desk, icon: icon, pressed: pressed) {
                AppWindow(image: image, content: content)
                if let selection {
                    Rectangle().fill(Color.white.opacity(0.22))
                        .overlay(Rectangle().stroke(Color(white: 0.35).opacity(0.7), lineWidth: 1))
                        .frame(width: selection.width, height: selection.height)
                        .offset(x: selection.minX, y: selection.minY)
                }
                if keys { KeyCaps().frame(width: scene.width).offset(y: 128) }
                if let genie {
                    GenieFrame(image: image, rect: rect, target: target, progress: genie)
                        .frame(width: scene.width, height: scene.height)
                }
                if fanOpen {
                    FanView(store: store, onCopy: { _, _ in }, onOpenFolder: {}, onDismiss: {},
                            initialHover: hovered, magnification: m, rowScales: scales, initialCopied: copied)
                        .frame(width: fan.width, height: fan.height)
                        .offset(x: deskFan.x, y: deskFan.y)
                }
                if let crosshair {
                    // Como macOS: al arrastrar, junto a la cruz van el ancho y el alto en píxeles de la captura.
                    let w = Int(((selection?.width ?? 0) / content.width * pixels.width / 2).rounded())
                    let h = Int(((selection?.height ?? 0) / content.height * pixels.height / 2).rounded())
                    Crosshair(label: selection == nil ? nil : "\(w)\n\(h)").offset(x: crosshair.x, y: crosshair.y)
                }
                if let cursor { Cursor().offset(x: cursor.x, y: cursor.y) }
            }
            // Recorte sin el escritorio vacío de los lados, para que el abanico se lea en el README.
            let crop = CGRect(x: 230, y: 110, width: 940, height: scene.height - 110)
            save(view.offset(x: -crop.minX, y: -crop.minY)
                     .frame(width: crop.width, height: crop.height, alignment: .topLeading)
                     .clipped(),
                 scale: 0.85, to: frames.appendingPathComponent(String(format: "%03d.png", n)))
            n += 1
        }
        func ease(_ t: Double) -> CGFloat { CGFloat(t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2) }
        func move(from a: CGPoint, to b: CGPoint, frames count: Int, icon: NSImage, fanOpen: Bool) {
            for i in 1...count {
                let t = ease(Double(i) / Double(count))
                let p = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
                if fanOpen {
                    hovered = FanLayout.index(forY: p.y - deskFan.y, height: fan.height, count: caps.count, magnification: m)
                }
                frame(icon, fanOpen: fanOpen, cursor: p)
            }
        }

        // 1. ⌘⇧4: el cursor se vuelve una cruz y arrastra sobre la ventana.
        let corner = CGPoint(x: content.minX, y: content.minY)
        let end = CGPoint(x: content.maxX, y: content.maxY)
        let begin = CGPoint(x: 820, y: 640)
        for _ in 0..<8 { frame(iconOld, cursor: begin) }
        move(from: begin, to: CGPoint(x: corner.x + 30, y: corner.y + 24), frames: 12, icon: iconOld, fanOpen: false)
        for _ in 0..<5 { frame(iconOld, cursor: CGPoint(x: corner.x + 30, y: corner.y + 24), keys: true) }
        for i in 1...6 {
            let t = ease(Double(i) / 6)
            frame(iconOld, crosshair: CGPoint(x: corner.x + 30 * (1 - t), y: corner.y + 24 * (1 - t)), keys: true)
        }
        for i in 1...24 {
            let t = ease(Double(i) / 24)
            let p = CGPoint(x: corner.x + (end.x - corner.x) * t, y: corner.y + (end.y - corner.y) * t)
            frame(iconOld, crosshair: p, selection: CGRect(x: corner.x, y: corner.y, width: p.x - corner.x, height: p.y - corner.y),
                  keys: i < 10)
        }
        for _ in 0..<6 { frame(iconOld, crosshair: end, selection: CGRect(origin: corner, size: content.size)) }
        // 2. Al soltar, la captura entra en el icono.
        let genieCount = Int(Genie.duration * fps)
        for i in 0...genieCount { frame(iconOld, genie: Double(i) / Double(genieCount), cursor: end) }
        for _ in 0..<10 { frame(iconNew, cursor: end) }
        // 3. El cursor va al icono y hace clic.
        move(from: end, to: iconC, frames: 16, icon: iconNew, fanOpen: false)
        for _ in 0..<3 { frame(iconNew, cursor: iconC, pressed: true) }
        // 4. Sale el abanico y el cursor sube por las capturas; la lupa sigue al cursor.
        for _ in 0..<6 { frame(iconNew, fanOpen: true, cursor: iconC) }
        var at = iconC
        for k in 0..<min(3, caps.count) {
            let target = thumbCenter(k)
            move(from: at, to: target, frames: 8, icon: iconNew, fanOpen: true)
            for _ in 0..<12 { frame(iconNew, fanOpen: true, cursor: target) }
            at = target
        }
        // 5. Clic en la ampliada: se copia, el icono se pone verde y el abanico se cierra.
        let chosen = caps[min(2, caps.count - 1)].url
        for _ in 0..<14 { frame(iconCopied, fanOpen: true, cursor: at, copied: chosen) }
        hovered = nil
        for _ in 0..<24 { frame(iconCopied, cursor: at) }
        for _ in 0..<10 { frame(iconNew, cursor: at) }

        // 6. Ajustes (vista real de la app, en una ventana que no se muestra)
        let host = NSHostingView(rootView: SettingsView(store: store).background(Color(nsColor: .windowBackgroundColor)))
        host.appearance = NSAppearance(named: .darkAqua)
        host.frame = CGRect(origin: .zero, size: host.fittingSize)
        host.layoutSubtreeIfNeeded()
        if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: output.appendingPathComponent("settings.png"))
        }
        print("imágenes en \(output.path) (\(n) fotogramas de la demo)")
    }

    /// Esquina superior izquierda del abanico en la escena (y hacia abajo), como lo coloca la app:
    /// miniaturas centradas en el icono y la fila de abajo `FanPlacement.gap` sobre él.
    private static func fanTopLeft(dock: DockLayout, fan: CGSize, magnification m: CGFloat) -> CGPoint {
        let iconTop = dock.targetCenter.y - DockLayout.tile / 2
        let bottom = iconTop - FanPlacement.gap + FanLayout.overflow(magnification: m)
        return CGPoint(x: dock.targetCenter.x - FanLayout.anchorX, y: bottom - fan.height)
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
    var pressed = false
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
                        Crisp(image: icon, side: DockLayout.tile).brightness(pressed ? -0.3 : 0)
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

/// Una ventana de ejemplo (barra de título con los tres botones) que muestra la página capturada.
private struct AppWindow: View {
    let image: NSImage
    let content: CGRect
    static let titleBar: CGFloat = 28

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ForEach([Color(red: 1, green: 0.37, blue: 0.34), Color(red: 1, green: 0.74, blue: 0.18),
                         Color(red: 0.16, green: 0.78, blue: 0.25)], id: \.self) { c in
                    Circle().fill(c).frame(width: 12, height: 12)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(width: content.width, height: Self.titleBar)
            .background(Color(white: 0.93))
            Image(nsImage: image).resizable().interpolation(.high)
                .frame(width: content.width, height: content.height)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 22, y: 12)
        .offset(x: content.minX, y: content.minY - Self.titleBar)
    }
}

/// La cruz de ⌘⇧4 (centro en (0, 0)) con el tamaño de la selección al lado.
private struct Crosshair: View {
    let label: String?
    var body: some View {
        ZStack(alignment: .topLeading) {
            let cross = Path { p in
                p.move(to: CGPoint(x: -14, y: 0)); p.addLine(to: CGPoint(x: 14, y: 0))
                p.move(to: CGPoint(x: 0, y: -14)); p.addLine(to: CGPoint(x: 0, y: 14))
            }
            cross.stroke(.white, lineWidth: 3.2)
            cross.stroke(.black, lineWidth: 1.2)
            if let label {
                Text(label)
                    .font(.system(size: 14, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.black)
                    .shadow(color: .white, radius: 0.8)
                    .shadow(color: .white, radius: 0.8)
                    .fixedSize()
                    .offset(x: 10, y: 8)
            }
        }
        .frame(width: 0, height: 0, alignment: .topLeading)
    }
}

/// Las teclas pulsadas, para que se entienda de dónde sale la cruz.
private struct KeyCaps: View {
    var body: some View {
        HStack(spacing: 6) {
            ForEach(["⌘", "⇧", "4"], id: \.self) { k in
                Text(k).font(.system(size: 20, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.white.opacity(0.25), lineWidth: 1))
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// La flecha del cursor de macOS (negra con borde blanco); su punta está en (0, 0).
private struct Cursor: View {
    var body: some View {
        let arrow = Path { p in
            p.move(to: .zero)
            p.addLine(to: CGPoint(x: 0, y: 22)); p.addLine(to: CGPoint(x: 5.5, y: 17))
            p.addLine(to: CGPoint(x: 9, y: 25)); p.addLine(to: CGPoint(x: 12.5, y: 23.5))
            p.addLine(to: CGPoint(x: 9, y: 16)); p.addLine(to: CGPoint(x: 16, y: 16))
            p.closeSubpath()
        }
        ZStack(alignment: .topLeading) {
            arrow.fill(.black)
            arrow.stroke(.white, style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
        }
        .frame(width: 18, height: 27, alignment: .topLeading)
        .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
    }
}
