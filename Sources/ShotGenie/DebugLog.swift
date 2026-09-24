import AppKit

/// Solo depuración: `defaults write com.enderj.screencapture debugLogPath /ruta.log` anota eventos del abanico.
enum DebugLog {
    static func note(_ text: @autoclosure () -> String) {
        guard let path = UserDefaults.standard.string(forKey: "debugLogPath") else { return }
        let line = "\(Date().formatted(.dateTime.hour().minute().second().secondFraction(.fractional(3)))) \(text())\n"
        if let h = FileHandle(forWritingAtPath: path) {
            h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close()
        } else {
            try? line.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }
}
