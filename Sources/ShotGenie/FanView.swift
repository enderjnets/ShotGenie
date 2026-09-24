import ShotGenieCore
import SwiftUI

/// Abanico como el de las pilas del Dock: píldora a la izquierda, miniatura a la derecha,
/// arco que se abre hacia arriba. La captura bajo el cursor se amplía (lupa).
struct FanView: View {
    enum CopyKind { case image, path }

    let store: CaptureStore
    let onCopy: (Capture, CopyKind) -> Void
    let onOpenFolder: () -> Void
    let onDismiss: () -> Void

    @State private var hovered: Int?
    /// Lo que se amplía la miniatura bajo el cursor (Ajustes).
    private var magnification: CGFloat { Settings.magnification }

    init(store: CaptureStore, onCopy: @escaping (Capture, CopyKind) -> Void, onOpenFolder: @escaping () -> Void,
         onDismiss: @escaping () -> Void, initialHover: Int? = nil) {
        self.store = store
        self.onCopy = onCopy
        self.onOpenFolder = onOpenFolder
        self.onDismiss = onDismiss
        _hovered = State(initialValue: initialHover)
    }
    @State private var copied: (url: URL, kind: CopyKind)?

    static let accent = Color(red: 0, green: 0x64 / 255, blue: 0xd2 / 255)
    static let copiedGreen = Color(red: 0x1e / 255, green: 0x7a / 255, blue: 0x3c / 255)
    static let pillFill = Color(white: 0.12, opacity: 0.82)

    var body: some View {
        let caps = store.captures
        let rows = caps.count + 1
        let size = CGSize(width: FanLayout.width(rows: rows, magnification: magnification), height: FanLayout.height(rows: rows, magnification: magnification))

        ZStack(alignment: .bottomLeading) {
            // Fondo casi invisible: recibe el cursor entre filas y un clic en vacío cierra.
            Color.black.opacity(0.001)
                .onTapGesture(perform: onDismiss)

            ForEach(Array(caps.enumerated()), id: \.element.id) { k, capture in
                placed(row: k) { captureRow(capture, row: k) }
                    .zIndex(hovered == k ? 10 : Double(-k))
            }
            placed(row: caps.count) { folderRow(hidden: store.totalCount - caps.count) }
                .zIndex(Double(-rows))
        }
        .frame(width: size.width, height: size.height)
        .onContinuousHover { phase in
            let next: Int?
            switch phase {
            case .active(let p): next = FanLayout.index(forY: p.y, height: size.height, count: caps.count, magnification: magnification)
            case .ended: next = nil
            }
            if next != hovered {
                withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) { hovered = next }
            }
        }
    }

    /// Coloca una fila en el arco: sube, se desplaza a la derecha y se inclina alrededor de su miniatura.
    private func placed(row k: Int, @ViewBuilder _ content: () -> some View) -> some View {
        let p = FanLayout.placement(row: k)
        let rowWidth = FanLayout.labelWidth + FanLayout.gap + FanLayout.thumb.width
        let pivot = UnitPoint(x: (rowWidth - FanLayout.thumb.width / 2) / rowWidth, y: 0.5)
        return content()
            .frame(width: rowWidth, height: FanLayout.thumb.height)
            .rotationEffect(.degrees(p.degrees), anchor: pivot)
            .offset(x: FanLayout.padding + p.dx, y: -(FanLayout.overflow(magnification: magnification) + p.rise))
    }

    private func captureRow(_ capture: Capture, row k: Int) -> some View {
        let active = hovered == k
        return HStack(spacing: FanLayout.gap) {
            HStack(spacing: 6) {
                if active {
                    pill(String(localized: "Path"), systemImage: "link", fill: Self.pillFill) { copy(capture, .path) }
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    pill(label(capture, now: ctx.date), systemImage: nil, fill: pillColor(capture, active: active)) {
                        copy(capture, .image)
                    }
                }
            }
            .frame(width: FanLayout.labelWidth, alignment: .trailing)

            // La ampliación cambia el tamaño real (no un scaleEffect), para que el clic
            // funcione en toda la imagen ampliada y no solo en su hueco original.
            let scale = active ? magnification : 1
            Button { copy(capture, .image) } label: {
                thumbnail(capture)
                    .frame(width: FanLayout.thumb.width * scale, height: FanLayout.thumb.height * scale)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(width: FanLayout.thumb.width, height: FanLayout.thumb.height, alignment: .leading)
            .accessibilityLabel(String(localized: "Copy image of the screenshot from \(Texts.ago(capture.created))"))
        }
    }

    private func folderRow(hidden: Int) -> some View {
        HStack(spacing: FanLayout.gap) {
            pill(hidden > 0 ? String(localized: "\(Texts.number(hidden)) more in Finder") : String(localized: "Open in Finder"), systemImage: nil, fill: Self.pillFill, action: onOpenFolder)
                .frame(width: FanLayout.labelWidth, alignment: .trailing)
            Button(action: onOpenFolder) {
                Image(systemName: "arrowshape.turn.up.right.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(Self.pillFill, in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1.5))
                    .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
            }
            .buttonStyle(.plain)
            .frame(width: FanLayout.thumb.width, height: FanLayout.thumb.height)
            .accessibilityLabel(String(localized: "Open screenshots folder"))
        }
    }

    @ViewBuilder private func thumbnail(_ capture: Capture) -> some View {
        if let thumb = Thumbnailer.thumbnail(for: capture.url) {
            Image(nsImage: thumb)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(.white.opacity(0.9), lineWidth: 1.5))
                .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
        } else {
            RoundedRectangle(cornerRadius: 4).fill(.gray.opacity(0.4))
        }
    }

    private func pill(_ text: String, systemImage: String?, fill: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage { Image(systemName: systemImage) }
                Text(text).lineLimit(1)
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(fill, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.14)))
            .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
        }
        .buttonStyle(.plain)
    }

    private func label(_ capture: Capture, now: Date) -> String {
        if let copied, copied.url == capture.url {
            return copied.kind == .image ? String(localized: "Image copied ✓") : String(localized: "Path copied ✓")
        }
        return String(localized: "Screenshot · \(Texts.ago(capture.created, now: now))")
    }

    private func pillColor(_ capture: Capture, active: Bool) -> Color {
        if let copied, copied.url == capture.url { return Self.copiedGreen }
        return active ? Self.accent : Self.pillFill
    }

    private func copy(_ capture: Capture, _ kind: CopyKind) {
        copied = (capture.url, kind)
        onCopy(capture, kind)
    }
}
