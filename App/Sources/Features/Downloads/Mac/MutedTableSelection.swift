#if os(macOS)
import SDMCore
import SwiftUI

/// Keeps table selection visible without letting the app accent color overpower row content.
struct MutedTableSelection: NSViewRepresentable {
    let selectedIDs: Set<DownloadID>

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> MarkerView {
        let marker = MarkerView()
        marker.didMoveToWindow = { [weak marker, weak coordinator = context.coordinator] in
            guard let marker, let coordinator else { return }
            connectCoordinator(coordinator, from: marker)
        }
        return marker
    }

    func updateNSView(_ marker: MarkerView, context: Context) {
        connectCoordinator(context.coordinator, from: marker)
        context.coordinator.selectionDidUpdate(selectedIDs)
    }

    private func connectCoordinator(_ coordinator: Coordinator, from marker: NSView) {
        Task { @MainActor [weak marker, weak coordinator] in
            for _ in 0..<10 {
                guard let marker, let coordinator else { return }
                if let tableView = mainTableView(from: marker) {
                    coordinator.connect(to: tableView)
                    return
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    private func mainTableView(from marker: NSView) -> NSTableView? {
        guard let contentView = marker.window?.contentView else { return nil }
        return allTableViews(in: contentView).first { $0.numberOfColumns > 1 }
    }

    private func allTableViews(in view: NSView) -> [NSTableView] {
        var result: [NSTableView] = []
        if let tableView = view as? NSTableView {
            result.append(tableView)
        }
        for subview in view.subviews {
            result.append(contentsOf: allTableViews(in: subview))
        }
        return result
    }

    final class MarkerView: NSView {
        var didMoveToWindow: (() -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            didMoveToWindow?()
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        private weak var tableView: NSTableView?
        private weak var clipView: NSClipView?
        private var selectedIDs: Set<DownloadID> = []
        private var selectionUpdateTask: Task<Void, Never>?

        func selectionDidUpdate(_ selectedIDs: Set<DownloadID>) {
            self.selectedIDs = selectedIDs
            scheduleSelectionUpdate()
        }

        func connect(to tableView: NSTableView) {
            guard self.tableView !== tableView else {
                scheduleSelectionUpdate()
                return
            }
            if let currentTableView = self.tableView {
                NotificationCenter.default.removeObserver(
                    self,
                    name: NSTableView.selectionDidChangeNotification,
                    object: currentTableView
                )
            }
            if let currentClipView = clipView {
                NotificationCenter.default.removeObserver(
                    self,
                    name: NSView.boundsDidChangeNotification,
                    object: currentClipView
                )
            }
            self.tableView = tableView
            tableView.selectionHighlightStyle = .none
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(selectionDidChange),
                name: NSTableView.selectionDidChangeNotification,
                object: tableView
            )
            let clipView = tableView.enclosingScrollView?.contentView
            self.clipView = clipView
            if let clipView {
                clipView.postsBoundsChangedNotifications = true
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(visibleRowsDidChange),
                    name: NSView.boundsDidChangeNotification,
                    object: clipView
                )
            }
            scheduleSelectionUpdate()
        }

        @objc private func selectionDidChange() {
            scheduleSelectionUpdate()
        }

        @objc private func visibleRowsDidChange() {
            scheduleSelectionUpdate()
        }

        private func scheduleSelectionUpdate() {
            selectionUpdateTask?.cancel()
            let expectedIDs = selectedIDs
            selectionUpdateTask = Task { @MainActor [weak self] in
                await Task.yield()
                guard !Task.isCancelled, self?.selectedIDs == expectedIDs else { return }
                self?.updateSelectionBackgrounds()

                for delay in [30, 120] {
                    do {
                        try await Task.sleep(for: .milliseconds(delay))
                    } catch {
                        return
                    }
                    guard !Task.isCancelled, self?.selectedIDs == expectedIDs else { return }
                    self?.updateSelectionBackgrounds()
                }
            }
        }

        private func updateSelectionBackgrounds() {
            guard let tableView else { return }
            let selectedRows = tableView.selectedRowIndexes
            tableView.enumerateAvailableRowViews { rowView, row in
                rowView.backgroundColor = selectedRows.contains(row)
                    ? NSColor.controlAccentColor.withAlphaComponent(0.14)
                    : .clear
                rowView.needsDisplay = true
            }
        }
    }
}
#endif
