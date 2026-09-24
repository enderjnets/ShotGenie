import AppKit
import Observation
import ShotGenieCore

struct Capture: Identifiable, Equatable {
    let url: URL
    let created: Date
    var id: URL { url }
}

/// Vigila la carpeta de capturas y expone las 5 más nuevas.
@MainActor @Observable
final class CaptureStore {
    static let limit = 5

    private(set) var captures: [Capture] = []
    /// Cuántas capturas hay en total en la carpeta (para «N más en Finder»).
    private(set) var totalCount = 0
    private(set) var folder: URL

    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private var source: DispatchSourceFileSystemObject?
    @ObservationIgnored private var pendingReload: DispatchWorkItem?

    init() {
        folder = CaptureStore.configuredFolder()
    }

    /// La carpeta que usa macOS para las capturas (`defaults read com.apple.screencapture location`).
    static func configuredFolder() -> URL {
        let raw = CFPreferencesCopyAppValue("location" as CFString, "com.apple.screencapture" as CFString) as? String
        let path = (raw.map { ($0 as NSString).expandingTildeInPath }) ?? (NSHomeDirectory() + "/Desktop")
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    func start() {
        let current = CaptureStore.configuredFolder()
        if current != folder || source == nil {
            folder = current
            watch()
        }
        reload()
    }

    private func watch() {
        source?.cancel()
        let fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else {
            NSLog("ShotGenie: no se puede vigilar \(folder.path)")
            return
        }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        src.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.scheduleReload(after: 0.1) }
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
    }

    private func scheduleReload(after delay: TimeInterval) {
        pendingReload?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.reload() }
        }
        pendingReload = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func reload() {
        let keys: [URLResourceKey] = [.creationDateKey, .fileSizeKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: [])) ?? []
        let entries = urls.compactMap { url -> CaptureListing.Entry? in
            guard CaptureListing.isCapture(url) else { return nil }
            let values = try? url.resourceValues(forKeys: Set(keys))
            return .init(url: url, created: values?.creationDate ?? .distantPast)
        }
        let latest = CaptureListing.latest(entries, limit: CaptureStore.limit)
        totalCount = entries.count

        // Un archivo recién creado puede estar aún vacío: se reintenta en breve.
        if let newest = latest.first,
           ((try? newest.url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0) == 0 {
            scheduleReload(after: 0.15)
            return
        }

        let next = latest.map { Capture(url: $0.url, created: $0.created) }
        if next != captures {
            captures = next
            onChange?()
        }
    }
}
