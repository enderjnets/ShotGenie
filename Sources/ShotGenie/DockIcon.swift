import AppKit

/// Pinta el icono del Dock: marco azul del icono de la app + miniatura de la última captura + insignia dorada.
/// Sin capturas se usa el icono de la app (Resources/AppIcon.svg).
@MainActor
enum DockIcon {
    enum Badge { case camera, copied }

    // Los colores de Resources/AppIcon.svg.
    static let frameTop = NSColor(srgbRed: 0x2a / 255, green: 0x86 / 255, blue: 0xf5 / 255, alpha: 1)
    static let frameBottom = NSColor(srgbRed: 0x0a / 255, green: 0x4d / 255, blue: 0xb3 / 255, alpha: 1)
    static let goldTop = NSColor(srgbRed: 0xff / 255, green: 0xe7 / 255, blue: 0xa3 / 255, alpha: 1)
    static let goldBottom = NSColor(srgbRed: 0xf2 / 255, green: 0xa5 / 255, blue: 0x2a / 255, alpha: 1)
    static let navy = NSColor(srgbRed: 0x0b / 255, green: 0x1a / 255, blue: 0x33 / 255, alpha: 1)
    static let copiedGreen = NSColor(srgbRed: 0x1e / 255, green: 0x7a / 255, blue: 0x3c / 255, alpha: 1)
    static let emptyStroke = NSColor(srgbRed: 0x5d / 255, green: 0x71 / 255, blue: 0x87 / 255, alpha: 1)

    static func render(thumbnail: NSImage?, badge: Badge) -> NSImage {
        if thumbnail == nil, let appIcon = Bundle.main.image(forResource: "AppIcon") { return appIcon }
        let side: CGFloat = 512
        return NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            // Rejilla de iconos de macOS: el cuerpo ocupa ~80 % del lienzo.
            let body = NSRect(x: 50, y: 50, width: 412, height: 412)
            NSGradient(starting: frameTop, ending: frameBottom)?
                .draw(in: NSBezierPath(roundedRect: body, xRadius: 92, yRadius: 92), angle: -90)

            let inner = body.insetBy(dx: 44, dy: 44)
            if let thumb = thumbnail {
                let clip = NSBezierPath(roundedRect: inner, xRadius: 40, yRadius: 40)
                NSGraphicsContext.saveGraphicsState()
                clip.addClip()
                NSColor.black.setFill()
                inner.fill()
                thumb.draw(in: aspectFill(thumb.size, in: inner), from: .zero, operation: .sourceOver, fraction: 1)
                NSGraphicsContext.restoreGraphicsState()
            } else {
                let dashed = NSBezierPath(roundedRect: inner.insetBy(dx: 6, dy: 6), xRadius: 36, yRadius: 36)
                dashed.lineWidth = 10
                dashed.setLineDash([26, 18], count: 2, phase: 0)
                emptyStroke.setStroke()
                dashed.stroke()
                drawSymbol("camera", in: inner.insetBy(dx: 100, dy: 100), color: emptyStroke.blended(withFraction: 0.3, of: .white) ?? emptyStroke)
            }

            if thumbnail != nil {
                let d: CGFloat = 150
                let circle = NSRect(x: body.maxX - d + 24, y: body.minY - 24, width: d, height: d)
                NSColor(srgbRed: 0.95, green: 0.95, blue: 0.93, alpha: 1).setFill()
                NSBezierPath(ovalIn: circle).fill()
                let dot = NSBezierPath(ovalIn: circle.insetBy(dx: 12, dy: 12))
                if badge == .copied {
                    copiedGreen.setFill()
                    dot.fill()
                    drawSymbol("checkmark", in: circle.insetBy(dx: 40, dy: 40), color: .white)
                } else {
                    NSGradient(starting: goldTop, ending: goldBottom)?.draw(in: dot, angle: -90)
                    drawSymbol("camera.fill", in: circle.insetBy(dx: 40, dy: 40), color: navy)
                }
            }
            return true
        }
    }

    private static func aspectFill(_ size: NSSize, in rect: NSRect) -> NSRect {
        guard size.width > 0, size.height > 0 else { return rect }
        let scale = max(rect.width / size.width, rect.height / size.height)
        let w = size.width * scale, h = size.height * scale
        // Alineado arriba: en una captura lo reconocible suele estar arriba.
        return NSRect(x: rect.midX - w / 2, y: rect.maxY - h, width: w, height: h)
    }

    private static func drawSymbol(_ name: String, in rect: NSRect, color: NSColor) {
        let config = NSImage.SymbolConfiguration(pointSize: rect.height, weight: .bold)
            .applying(.init(paletteColors: [color]))
        guard let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config) else { return }
        let s = img.size
        let scale = min(rect.width / s.width, rect.height / s.height)
        let target = NSRect(x: rect.midX - s.width * scale / 2, y: rect.midY - s.height * scale / 2,
                            width: s.width * scale, height: s.height * scale)
        img.draw(in: target)
    }

    /// Solo para verificar sin ver el Dock (está oculto): `defaults write com.enderj.screencapture debugIconPath /ruta.png`.
    static func writeDebugCopy(_ image: NSImage) {
        guard let path = UserDefaults.standard.string(forKey: "debugIconPath"),
              let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }
}
