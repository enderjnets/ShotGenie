import CoreGraphics
import Foundation

/// Ruta escapada con `\`, igual que al arrastrar un archivo a la terminal.
public enum ShellPath {
    static let special: Set<Character> = [
        " ", "\t", "(", ")", "[", "]", "{", "}", "<", ">", "&", ";", "|", "'", "\"",
        "`", "$", "*", "?", "!", "#", "\\", "~", "=", "%", "^",
    ]

    public static func escaped(_ path: String) -> String {
        var out = ""
        for ch in path {
            if special.contains(ch) { out.append("\\") }
            out.append(ch)
        }
        return out
    }
}

/// Qué archivos de la carpeta cuentan como capturas y en qué orden.
public enum CaptureListing {
    public struct Entry: Equatable, Sendable {
        public let url: URL
        public let created: Date
        public init(url: URL, created: Date) {
            self.url = url
            self.created = created
        }
    }

    public static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff", "tif"]

    public static func isCapture(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        // screencapture escribe primero `.Screenshot…` y luego lo renombra.
        guard !name.hasPrefix(".") else { return false }
        return imageExtensions.contains(url.pathExtension.lowercased())
    }

    public static func latest(_ entries: [Entry], limit: Int) -> [Entry] {
        Array(entries.filter { isCapture($0.url) }
            .sorted { $0.created > $1.created }
            .prefix(limit))
    }
}

/// Lupa estilo menú: filas compactas y la fila bajo el cursor ampliada.
/// Índice 0 = la captura más nueva (abajo del todo).
public enum Fisheye {
    public static let big = CGSize(width: 308, height: 176)
    public static let row = CGSize(width: 308, height: 36)
    public static let spacing: CGFloat = 4

    public static func size(distance: Int) -> CGSize {
        distance == 0 ? big : row
    }

    public static func sizes(count: Int, hovered: Int) -> [CGSize] {
        (0..<count).map { size(distance: abs($0 - hovered)) }
    }

    /// Siempre una ampliada y el resto filas: el alto no cambia al mover la lupa.
    public static func containerHeight(count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        return big.height + CGFloat(count - 1) * (row.height + spacing)
    }

    /// Qué captura queda bajo `y` con la disposición actual (`hovered` ampliada).
    /// `y` crece hacia abajo; arriba la más antigua. Ampliar la elegida deja el cursor sobre ella.
    public static func index(forY y: CGFloat, hovered: Int, count: Int) -> Int {
        guard count > 1 else { return 0 }
        var top: CGFloat = 0
        for idx in (0..<count).reversed() {
            let h = size(distance: abs(idx - hovered)).height
            if y < top + h + spacing / 2 { return idx }
            top += h + spacing
        }
        return 0
    }
}

/// Dónde abrir el panel: centrado en el cursor (que está sobre el icono del Dock) y por encima del Dock.
public enum PanelPlacement {
    public static let margin: CGFloat = 8
    /// Distancia sobre el cursor para no tapar el icono aunque el Dock lo esté ampliando.
    public static let aboveCursor: CGFloat = 72

    public static func origin(mouse: CGPoint, panel: CGSize, screen: CGRect, visible: CGRect) -> CGPoint {
        origin(mouse: mouse, panel: panel, anchorX: panel.width / 2, screen: screen, visible: visible)
    }

    /// `anchorX`: el punto del panel (desde su borde izquierdo) que debe quedar sobre el cursor.
    public static func origin(mouse: CGPoint, panel: CGSize, anchorX: CGFloat, screen: CGRect, visible: CGRect) -> CGPoint {
        var x = mouse.x - anchorX
        x = min(max(x, screen.minX + margin), screen.maxX - panel.width - margin)
        var y = max(visible.minY + margin, mouse.y + aboveCursor)
        y = min(y, visible.maxY - panel.height)
        return CGPoint(x: x, y: max(y, screen.minY))
    }
}

/// Abanico como el de las pilas del Dock: las filas suben desde el icono en un arco
/// que se abre hacia la derecha y se inclina. Fila 0 = la captura más nueva (abajo).
public enum FanLayout {
    public static let step: CGFloat = 68
    public static let thumb = CGSize(width: 76, height: 56)
    public static let radius: CGFloat = 1_000
    /// Cuánto se amplía la miniatura bajo el cursor. Se gradúa en Ajustes.
    public static let defaultMagnification: CGFloat = 4.2
    public static let magnificationRange: ClosedRange<CGFloat> = 1.5...6.0

    public static func clampMagnification(_ m: CGFloat) -> CGFloat {
        guard m.isFinite else { return defaultMagnification }
        return min(max(m, magnificationRange.lowerBound), magnificationRange.upperBound)
    }
    public static let labelWidth: CGFloat = 300
    public static let gap: CGFloat = 12
    /// Margen para la sombra y para la miniatura ampliada, que sobresale arriba y abajo.
    public static let padding: CGFloat = 20
    /// Lo que sobresale la miniatura ampliada por arriba y por abajo, más aire para la sombra.
    public static func overflow(magnification m: CGFloat = defaultMagnification) -> CGFloat {
        thumb.height * (m - 1) / 2 + 12
    }

    public struct Placement: Equatable {
        public let rise: CGFloat
        public let dx: CGFloat
        public let degrees: Double
    }

    public static func placement(row k: Int) -> Placement {
        let rise = CGFloat(k) * step
        let dx = radius - (radius * radius - rise * rise).squareRoot()
        let degrees = asin(Double(rise / radius)) * 180 / .pi
        return Placement(rise: rise, dx: dx, degrees: degrees)
    }

    /// Centro horizontal de la columna de miniaturas en la fila 0 (lo que va sobre el icono del Dock).
    public static var anchorX: CGFloat { padding + labelWidth + gap + thumb.width / 2 }

    public static func width(rows: Int, magnification m: CGFloat = defaultMagnification) -> CGFloat {
        let top = placement(row: max(rows - 1, 0))
        return padding * 2 + labelWidth + gap + thumb.width * m + top.dx
    }

    public static func height(rows: Int, magnification m: CGFloat = defaultMagnification) -> CGFloat {
        overflow(magnification: m) * 2 + CGFloat(max(rows - 1, 0)) * step + thumb.height
    }

    /// Centro vertical de la fila `k`, con `y` creciendo hacia abajo (SwiftUI).
    public static func centerY(row k: Int, height: CGFloat, magnification m: CGFloat = defaultMagnification) -> CGFloat {
        height - overflow(magnification: m) - thumb.height / 2 - CGFloat(k) * step
    }

    /// Fila de captura bajo el cursor por franjas fijas (la ampliación no las mueve, así no oscila).
    /// `nil` sobre la fila de la carpeta o más arriba.
    public static func index(forY y: CGFloat, height: CGFloat, count: Int,
                             magnification m: CGFloat = defaultMagnification) -> Int? {
        guard count > 0 else { return nil }
        let fromBottom = (centerY(row: 0, height: height, magnification: m) - y) / step
        let k = Int(fromBottom.rounded())
        if k >= count { return nil }
        return max(k, 0)
    }
}

/// Efecto genio al capturar: la imagen, en grande, se estrecha en un embudo y cae en el icono.
/// Se dibuja por franjas horizontales; cada franja es la imagen escalada en horizontal y recortada.
/// Coordenadas con `y` hacia abajo (las de SwiftUI).
public enum Genie {
    /// Ancho del «cuello» del embudo al llegar al icono.
    public static let targetWidth: CGFloat = 44
    /// La imagen de partida ocupa como mucho esta fracción de la pantalla.
    public static let maxScreenFraction: CGFloat = 0.55
    public static let duration: Double = 1.4

    public struct Strip: Equatable {
        /// Dónde se ve la franja.
        public let dest: CGRect
        /// Dónde se dibuja la imagen completa para que, recortada a `dest`, se vea la franja correcta.
        public let image: CGRect
    }

    /// Progreso de cada fase para `t` ∈ [0, 1]: aparecer, curvarse y caer.
    public static func phases(_ t: Double) -> (appear: Double, curve: Double, slide: Double) {
        func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }
        func smooth(_ x: Double) -> Double { x * x * (3 - 2 * x) }
        let appear = clamp(t / 0.18)
        let curve = smooth(clamp((t - 0.34) / 0.26))
        let slide = pow(clamp((t - 0.5) / 0.5), 1.6)
        return (appear, curve, slide)
    }

    /// Rectángulo inicial: la captura a su tamaño en puntos, reducida si no cabe, centrada.
    public static func startRect(imagePoints size: CGSize, in screen: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return .zero }
        let scale = min(1, screen.width * maxScreenFraction / size.width, screen.height * maxScreenFraction / size.height)
        let w = size.width * scale, h = size.height * scale
        return CGRect(x: screen.midX - w / 2, y: screen.midY - h / 2, width: w, height: h)
    }

    /// Si el icono quedara dentro de la imagen, el embudo no tendría hacia dónde salir:
    /// se usa el borde inferior de la pantalla en la misma x.
    public static func safeTarget(_ target: CGPoint, rect: CGRect, screen: CGSize) -> CGPoint {
        rect.insetBy(dx: -8, dy: -8).contains(target) ? CGPoint(x: target.x, y: screen.height - 4) : target
    }

    /// Hacia dónde cae el embudo, según en qué lado de la imagen está el icono.
    public enum Direction: Hashable, Sendable { case down, up, right, left }

    public static func direction(rect: CGRect, target: CGPoint) -> Direction {
        if target.y >= rect.maxY { return .down }
        if target.y <= rect.minY { return .up }
        return target.x >= rect.midX ? .right : .left
    }

    /// Transformación del «espacio genio» (donde el icono siempre está abajo) a la pantalla.
    public static func screenTransform(_ d: Direction, canvas: CGSize) -> CGAffineTransform {
        switch d {
        case .down: .identity
        case .up: CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: canvas.height)
        case .right: CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: 0, ty: 0)
        case .left: CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: canvas.width, ty: 0)
        }
    }

    /// Imagen e icono pasados al espacio genio.
    public static func genieSpace(rect: CGRect, target: CGPoint, canvas: CGSize,
                                  direction d: Direction) -> (rect: CGRect, target: CGPoint) {
        let inv = screenTransform(d, canvas: canvas).inverted()
        return (rect.applying(inv), target.applying(inv))
    }

    /// Cómo dibujar la imagen dentro de `rect` (espacio genio) para que en pantalla se vea derecha:
    /// se dibuja en `draw` con la transformación `local`, que deshace el giro o espejo del espacio genio.
    public static func imageTransform(direction d: Direction, into rect: CGRect) -> (draw: CGRect, local: CGAffineTransform) {
        let t = screenTransform(d, canvas: .zero)
        let linear = CGAffineTransform(a: t.a, b: t.b, c: t.c, d: t.d, tx: 0, ty: 0).inverted()
        let swaps = t.a == 0
        let draw = CGRect(x: 0, y: 0, width: swaps ? rect.height : rect.width, height: swaps ? rect.width : rect.height)
        let box = draw.applying(linear)
        return (draw, linear.concatenating(CGAffineTransform(translationX: rect.minX - box.minX, y: rect.minY - box.minY)))
    }

    /// El icono llevado dentro de la pantalla de la captura: si está en otra pantalla,
    /// el punto del borde de esta más cercano a él (coordenadas de AppKit).
    public static func pointOnScreen(_ p: CGPoint, screen: CGRect, inset: CGFloat = 4) -> CGPoint {
        CGPoint(x: min(max(p.x, screen.minX + inset), screen.maxX - inset),
                y: min(max(p.y, screen.minY + inset), screen.maxY - inset))
    }

    /// Franja de la imagen entre las alturas relativas `v0` y `v1`, o `nil` si ya entró en el icono.
    public static func strip(v0: CGFloat, v1: CGFloat, rect: CGRect, target: CGPoint,
                             curve: CGFloat, slide: CGFloat) -> Strip? {
        let travel = target.y - rect.minY
        guard travel > 0, rect.height > 0 else { return nil }
        let offset = slide * travel
        let y0 = rect.minY + v0 * rect.height + offset
        let y1 = min(rect.minY + v1 * rect.height + offset, target.y)
        guard y1 > y0 else { return nil }

        let u = min(max(((y0 + y1) / 2 - rect.minY) / travel, 0), 1)
        let k = curve * u * u * (3 - 2 * u)
        let left = rect.minX + (target.x - targetWidth / 2 - rect.minX) * k
        let right = rect.maxX + (target.x + targetWidth / 2 - rect.maxX) * k
        return Strip(
            dest: CGRect(x: left, y: y0, width: right - left, height: y1 - y0),
            image: CGRect(x: left, y: rect.minY + offset, width: right - left, height: rect.height)
        )
    }
}

/// En qué pantalla está el Dock, a partir del rectángulo de un icono según Accesibilidad
/// (origen arriba a la izquierda de la pantalla principal, igual que `screens`).
public enum DockGeometry {
    public static func screenIndex(item: CGRect, screens: [CGRect]) -> Int? {
        let x = item.midX
        let byX = screens.indices.filter { x >= screens[$0].minX && x <= screens[$0].maxX }
        // Dock visible: el icono está dentro de la pantalla (y no pegado a su borde superior).
        if let i = byX.first(where: { screens[$0].contains(CGPoint(x: x, y: item.midY)) && item.minY > screens[$0].minY + 1 }) {
            return i
        }
        // Dock oculto: el icono cuelga justo por debajo del borde inferior de su pantalla.
        return byX.min(by: { abs(screens[$0].maxY - item.minY) < abs(screens[$1].maxY - item.minY) })
            .flatMap { abs(screens[$0].maxY - item.minY) < 120 ? $0 : nil }
    }
}

public enum RelativeTime {
    public static func format(_ date: Date, now: Date = Date()) -> String {
        let s = Int(now.timeIntervalSince(date))
        switch s {
        case ..<1: return "ahora"
        case ..<60: return "hace \(s) s"
        case ..<3_600: return "hace \(s / 60) min"
        case ..<86_400: return "hace \(s / 3_600) h"
        default: return "hace \(s / 86_400) d"
        }
    }
}
