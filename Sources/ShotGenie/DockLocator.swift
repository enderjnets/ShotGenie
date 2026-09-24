import AppKit
import ApplicationServices

/// Dónde está el icono de esta app en el Dock, preguntándoselo al Dock por Accesibilidad.
/// Sin permiso de Accesibilidad devuelve `nil` y se usa el último clic en el icono.
@MainActor
enum DockLocator {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Muestra el aviso del sistema para conceder Accesibilidad.
    static func requestAccess() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Rectángulo del icono según el Dock, en coordenadas de Accesibilidad (origen arriba a la izquierda).
    static func iconRect() -> CGRect? {
        guard isTrusted,
              let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first
        else { return nil }
        let app = AXUIElementCreateApplication(dock.processIdentifier)
        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "ShotGenie"
        for list in children(of: app) where string(of: list, kAXRoleAttribute) == kAXListRole as String {
            for item in children(of: list) where string(of: item, kAXTitleAttribute) == name {
                if let pos = point(of: item), let size = size(of: item) { return CGRect(origin: pos, size: size) }
            }
        }
        return nil
    }

    /// Centro horizontal y borde superior del icono, en coordenadas de AppKit, si el Dock lo muestra
    /// donde está el cursor (tras un clic en el icono). Si no, `nil` y se usa el cursor.
    static func iconTop(near mouse: CGPoint) -> CGPoint? {
        guard let item = iconRect(), let primary = NSScreen.screens.first?.frame else { return nil }
        let top = CGPoint(x: item.midX, y: primary.maxY - item.minY)
        let bottom = primary.maxY - item.maxY
        guard abs(top.x - mouse.x) <= max(item.width, 40), mouse.y >= bottom - 20, mouse.y <= top.y + 20 else { return nil }
        return top
    }

    /// Las pantallas en las mismas coordenadas que `iconRect()`.
    static func screenRectsTopLeft() -> [CGRect] {
        guard let primary = NSScreen.screens.first?.frame else { return [] }
        return NSScreen.screens.map {
            CGRect(x: $0.frame.minX, y: primary.maxY - $0.frame.maxY, width: $0.frame.width, height: $0.frame.height)
        }
    }

    private static func children(of el: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }

    private static func string(of el: AXUIElement, _ attr: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func point(of el: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &value) == .success,
              let v = value, CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var p = CGPoint.zero
        return AXValueGetValue(v as! AXValue, .cgPoint, &p) ? p : nil
    }

    private static func size(of el: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &value) == .success,
              let v = value, CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var s = CGSize.zero
        return AXValueGetValue(v as! AXValue, .cgSize, &s) ? s : nil
    }
}
