import AppKit
import ShotGenieCore

@MainActor
enum Clipboard {
    /// Copia la imagen como PNG + TIFF. Sin URL de archivo: si no, la terminal pegaría la ruta en vez de la imagen.
    @discardableResult
    static func copyImage(_ url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url), let rep = NSBitmapImageRep(data: data) else {
            NSLog("ShotGenie: no se pudo leer \(url.path)")
            return false
        }
        let png = url.pathExtension.lowercased() == "png" ? data : rep.representation(using: .png, properties: [:])
        let pb = NSPasteboard.general
        pb.clearContents()
        var ok = false
        if let png { ok = pb.setData(png, forType: .png) }
        if let tiff = rep.tiffRepresentation { ok = pb.setData(tiff, forType: .tiff) || ok }
        return ok
    }

    /// Copia la ruta escapada, igual que al arrastrar el archivo a la terminal.
    @discardableResult
    static func copyPath(_ url: URL) -> Bool {
        let pb = NSPasteboard.general
        pb.clearContents()
        return pb.setString(ShellPath.escaped(url.path), forType: .string)
    }
}
