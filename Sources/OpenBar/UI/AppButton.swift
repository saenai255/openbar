import SwiftUI
import UniformTypeIdentifiers

struct AppButton: View {
    let item: BarItem
    let thickness: CGFloat
    let showTitle: Bool
    let position: BarPosition
    let style: BarStyle

    @State private var hovering = false
    @State private var size: CGSize = .zero
    @State private var dropEdge: DropEdge?

    private var app: AppEntry { item.app }
    private var iconSize: CGFloat { (thickness * 0.68).rounded() }
    private var isFocused: Bool {
        guard app.isActive && !app.isHidden else { return false }
        if let window = item.window { return !window.isMinimized && window == app.windows.first }
        return true
    }
    private var isDimmed: Bool { app.isHidden || item.window?.isMinimized == true }

    var body: some View {
        content
            .frame(maxWidth: showTitle ? .infinity : nil, maxHeight: .infinity)
            .frame(width: showTitle ? nil : thickness, height: position.isVertical ? thickness : nil)
            .background(highlight)
            .overlay(alignment: indicatorAlignment) { indicator }
            .overlay { if app.isUnresponsive { UnresponsiveHatch().clipShape(RoundedRectangle(cornerRadius: 6)).padding(2) } }
            .overlay(alignment: dropMarkerAlignment) { dropMarker }
            .contentShape(Rectangle())
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
            .overlay(
                MouseCatcher(
                    onLeft: { anchor in
                        PreviewController.shared.dismiss()
                        TaskbarModel.shared.primaryClick(item, anchor: anchor)
                    },
                    onRight: { anchor in
                        PreviewController.shared.dismiss()
                        MenuBuilder.contextMenu(for: item).popUp(at: anchor)
                    },
                    onMiddle: { TaskbarModel.shared.middleClick(item) },
                    onHover: { inside, anchor in
                        hovering = inside
                        if inside { PreviewController.shared.hoverBegan(item, anchor: anchor) }
                        else { PreviewController.shared.hoverEnded() }
                    },
                    dragPath: app.path
                )
            )
            .onDrop(of: [.fileURL], delegate: BarDropDelegate(target: app, position: position, size: size,
                                                             edge: $dropEdge))
            .help(showTitle ? "" : item.title)
    }

    private var content: some View {
        HStack(spacing: 6) {
            Image(nsImage: IconCache.icon(app.path))
                .resizable()
                .interpolation(.high)
                .frame(width: iconSize, height: iconSize)
                .saturation(app.isUnresponsive ? 0 : 1)
                .opacity(isDimmed ? 0.55 : 1)
                .pulsing(app.isLaunching, from: 0.35)
                .overlay(alignment: .topTrailing) { badge }
            if showTitle {
                Text(app.isUnresponsive ? "\(item.title) (Not Responding)" : item.title)
                    .font(.system(size: thickness < 34 ? 11 : 12, weight: isFocused ? .semibold : .regular))
                    .italic(item.window?.isMinimized == true)
                    .foregroundStyle(style.foreground.opacity(isDimmed ? 0.6 : 1))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, showTitle ? 8 : 0)
    }

    @ViewBuilder
    private var badge: some View {
        if let text = app.badge {
            Text(text.count > 4 ? String(text.prefix(3)) + "…" : text)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 4)
                .frame(minWidth: 15, minHeight: 15)
                .background(Capsule().fill(style.badge))
                .offset(x: 6, y: -4)
        }
    }

    @ViewBuilder
    private var highlight: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(isFocused ? style.highlight.opacity(0.35) : (hovering ? style.foreground.opacity(0.12) : .clear))
            if app.wantsAttention && !app.isActive {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.orange.opacity(0.55))
                    .pulsing(true, from: 0.15)
            }
        }
        .padding(2)
    }

    private var dropMarkerAlignment: Alignment {
        switch dropEdge {
        case .before: position.isVertical ? .top : .leading
        case .after: position.isVertical ? .bottom : .trailing
        case .onto, nil: .center
        }
    }

    @ViewBuilder
    private var dropMarker: some View {
        switch dropEdge {
        case .before, .after:
            Capsule().fill(style.highlight)
                .frame(width: position.isVertical ? nil : 3, height: position.isVertical ? 3 : nil)
                .padding(position.isVertical ? .horizontal : .vertical, 4)
        case .onto:
            RoundedRectangle(cornerRadius: 6).stroke(style.highlight, lineWidth: 2).padding(2)
        case nil:
            EmptyView()
        }
    }

    private var indicatorAlignment: Alignment {
        switch position {
        case .bottom: .bottom
        case .top: .top
        case .left: .leading
        case .right: .trailing
        }
    }

    @ViewBuilder
    private var indicator: some View {
        if app.isRunning {
            let count = item.window == nil ? min(max(app.windows.count, 1), 3) : 1
            let length: CGFloat = isFocused ? (showTitle ? 28 : 16) : 6
            let stack = position.isVertical
                ? AnyLayout(VStackLayout(spacing: 2)) : AnyLayout(HStackLayout(spacing: 2))
            stack {
                ForEach(0..<count, id: \.self) { _ in
                    Capsule()
                        .fill(isFocused ? style.highlight : style.foreground.opacity(0.7))
                        .frame(width: position.isVertical ? 3 : (count > 1 ? 6 : length),
                               height: position.isVertical ? (count > 1 ? 6 : length) : 3)
                }
            }
            .padding(1)
        }
    }
}

enum DropEdge { case before, after, onto }

/// Dropping an app or folder pins it next to the target; dropping a document onto an
/// app opens it with that app, like the Dock.
struct BarDropDelegate: DropDelegate {
    let target: AppEntry
    let position: BarPosition
    let size: CGSize
    @Binding var edge: DropEdge?

    private func edge(for info: DropInfo, pinning: Bool) -> DropEdge {
        guard pinning else { return .onto }
        let along = position.isVertical ? info.location.y / max(size.height, 1) : info.location.x / max(size.width, 1)
        return along < 0.5 ? .before : .after
    }

    private func isPinnable(_ info: DropInfo) -> Bool {
        // URLs aren't readable until drop; this only picks the marker, BarDrop decides.
        info.hasItemsConforming(to: [.application, .folder]) || !info.hasItemsConforming(to: [.data])
    }

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [.fileURL]) }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        let pin = isPinnable(info) || !target.isRunning && target.isFolder
        edge = edge(for: info, pinning: pin)
        return DropProposal(operation: pin ? .move : .copy)
    }

    func dropExited(info: DropInfo) { edge = nil }

    func performDrop(info: DropInfo) -> Bool {
        let dropEdge = edge(for: info, pinning: isPinnable(info))
        edge = nil
        let providers = info.itemProviders(for: [.fileURL])
        let target = self.target
        Task { @MainActor in
            var urls: [URL] = []
            for provider in providers {
                if let url = try? await provider.loadFileURL() { urls.append(url.standardizedFileURL) }
            }
            BarDrop.handle(urls, onto: target, edge: dropEdge)
        }
        return true
    }
}

enum BarDrop {
    static func isPinnable(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        return url.pathExtension == "app" || (values?.isDirectory == true && values?.isPackage != true)
    }

    @MainActor
    static func handle(_ urls: [URL], onto target: AppEntry?, edge: DropEdge) {
        let prefs = Prefs.shared
        let pins = urls.filter(isPinnable)
        let documents = urls.filter { !isPinnable($0) }

        if !pins.isEmpty {
            var index: Int
            if let target, let i = prefs.favorites.firstIndex(of: target.path) {
                index = edge == .after ? i + 1 : i
            } else {
                index = prefs.favorites.count
            }
            for url in pins where url.path != target?.path {
                let before = prefs.favorites.firstIndex(of: url.path)
                prefs.insertFavorite(url.path, at: index)
                if before == nil || before! >= index { index += 1 }
            }
        }

        if !documents.isEmpty, let target {
            if target.isFolder {
                for doc in documents {
                    try? FileManager.default.copyItem(at: doc, to: URL(fileURLWithPath: target.path)
                        .appendingPathComponent(doc.lastPathComponent))
                }
            } else {
                NSWorkspace.shared.open(documents, withApplicationAt: URL(fileURLWithPath: target.path),
                                        configuration: NSWorkspace.OpenConfiguration())
            }
        }
    }
}

extension NSItemProvider {
    func loadFileURL() async throws -> URL? {
        try await withCheckedThrowingContinuation { continuation in
            _ = loadObject(ofClass: URL.self) { url, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: url) }
            }
        }
    }
}

/// Diagonal stripes marking a hung app.
struct UnresponsiveHatch: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            var x: CGFloat = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += 6
            }
            context.stroke(path, with: .color(.gray.opacity(0.45)), lineWidth: 2)
        }
        .allowsHitTesting(false)
    }
}

extension View {
    /// Repeating fade while `active`; used for launching and attention states.
    @ViewBuilder
    func pulsing(_ active: Bool, from low: Double) -> some View {
        if active {
            PhaseAnimator([low, 1.0]) { opacity in
                self.opacity(opacity)
            } animation: { _ in .easeInOut(duration: 0.6) }
        } else {
            self
        }
    }
}
