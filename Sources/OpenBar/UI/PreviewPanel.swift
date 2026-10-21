import AppKit
import SwiftUI

final class PreviewController {
    static let shared = PreviewController()

    private var panel: NSPanel?
    private var showTask: DispatchWorkItem?
    private var hideTask: DispatchWorkItem?
    private var currentID: String?
    private var panelHovered = false

    var isVisible: Bool { panel?.isVisible == true }

    func hoverBegan(_ item: BarItem, anchor: NSRect) {
        guard Prefs.shared.showPreviews, item.app.isRunning, !item.app.windows.isEmpty else { return }
        hideTask?.cancel()
        showTask?.cancel()
        let delay = isVisible ? 0.05 : 0.45
        let task = DispatchWorkItem { [weak self] in self?.show(item, anchor: anchor) }
        showTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: task)
    }

    func hoverEnded() {
        showTask?.cancel()
        scheduleHide()
    }

    func dismiss() {
        showTask?.cancel()
        hideTask?.cancel()
        panel?.orderOut(nil)
        currentID = nil
    }

    private func scheduleHide() {
        hideTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            guard let self, !self.panelHovered else { return }
            self.dismiss()
        }
        hideTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: task)
    }

    private func show(_ item: BarItem, anchor: NSRect) {
        let windows = item.window.map { [$0] } ?? item.app.windows
        let panel = self.panel ?? makePanel()
        self.panel = panel
        currentID = item.id

        let view = PreviewView(app: item.app, windows: windows, images: [:]) { [weak self] inside in
            self?.panelHovered = inside
            if !inside { self?.scheduleHide() } else { self?.hideTask?.cancel() }
        }
        let host = NSHostingView(rootView: view)
        panel.contentView = host
        place(panel, size: host.fittingSize, anchor: anchor)
        panel.orderFrontRegardless()

        let ids = windows.compactMap(\.windowID)
        let id = item.id
        Task { @MainActor [weak self] in
            let images = await WindowPreviews.capture(ids, maxSide: 220)
            guard let self, self.currentID == id, !images.isEmpty, let panel = self.panel else { return }
            let updated = PreviewView(app: item.app, windows: windows, images: images, onHover: view.onHover)
            let host = NSHostingView(rootView: updated)
            panel.contentView = host
            self.place(panel, size: host.fittingSize, anchor: anchor)
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        return panel
    }

    private func place(_ panel: NSPanel, size: NSSize, anchor: NSRect) {
        let gap: CGFloat = 6
        var origin: NSPoint = switch Prefs.shared.position {
        case .bottom: NSPoint(x: anchor.midX - size.width / 2, y: anchor.maxY + gap)
        case .top: NSPoint(x: anchor.midX - size.width / 2, y: anchor.minY - gap - size.height)
        case .left: NSPoint(x: anchor.maxX + gap, y: anchor.midY - size.height / 2)
        case .right: NSPoint(x: anchor.minX - gap - size.width, y: anchor.midY - size.height / 2)
        }
        if let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchor) }) {
            let f = screen.frame
            origin.x = min(max(origin.x, f.minX + 4), f.maxX - size.width - 4)
            origin.y = min(max(origin.y, f.minY + 4), f.maxY - size.height - 4)
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }
}

struct PreviewView: View {
    let app: AppEntry
    let windows: [WindowEntry]
    let images: [CGWindowID: NSImage]
    let onHover: (Bool) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(windows) { window in
                PreviewCard(app: app, window: window, image: window.windowID.flatMap { images[$0] })
            }
        }
        .padding(10)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14))
        .onHover(perform: onHover)
    }
}

private struct PreviewCard: View {
    let app: AppEntry
    let window: WindowEntry
    let image: NSImage?
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(nsImage: IconCache.icon(app.path)).resizable().frame(width: 16, height: 16)
                Text(window.title.isEmpty ? app.name : window.title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if hovering {
                    Button {
                        WindowList.close(window)
                        PreviewController.shared.dismiss()
                        TaskbarModel.shared.refreshSoon()
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .frame(width: 200)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 200, maxHeight: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .opacity(window.isMinimized ? 0.6 : 1)
            } else if window.isMinimized {
                Text("Minimized").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 8).fill(hovering ? Color.primary.opacity(0.1) : .clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            PreviewController.shared.dismiss()
            WindowList.focus(window)
            TaskbarModel.shared.refreshSoon()
        }
    }
}
