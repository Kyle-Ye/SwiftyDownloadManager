#if os(macOS)
import SDMCore
import SwiftUI

/// Commits native table selection synchronously so snapshot refreshes cannot restore stale state.
struct DownloadTableSelectionBridge: NSViewRepresentable {
    @Binding var selectedIDs: Set<DownloadID>
    let rowIDs: [DownloadID]
    let context: DownloadFilter

    func makeCoordinator() -> Coordinator {
        Coordinator(selectedIDs: $selectedIDs, rowIDs: rowIDs, context: context)
    }

    func makeNSView(context: Context) -> MarkerView {
        let marker = MarkerView()
        marker.didMoveToWindow = { [weak marker, weak coordinator = context.coordinator] in
            guard let marker, let coordinator else { return }
            if marker.window == nil {
                coordinator.disconnect()
                return
            }
            connect(coordinator, from: marker)
        }
        return marker
    }

    func updateNSView(_ marker: MarkerView, context: Context) {
        context.coordinator.update(
            selectedIDs: $selectedIDs,
            rowIDs: rowIDs,
            context: self.context
        )
        connect(context.coordinator, from: marker)
    }

    private func connect(_ coordinator: Coordinator, from marker: NSView) {
        guard coordinator.beginConnecting() else { return }
        Task { @MainActor [weak marker, weak coordinator] in
            defer { coordinator?.endConnecting() }
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
        let tableViews = allTableViews(in: contentView)
        return tableViews.max { lhs, rhs in
            if lhs.numberOfColumns != rhs.numberOfColumns {
                return lhs.numberOfColumns < rhs.numberOfColumns
            }
            return lhs.numberOfRows < rhs.numberOfRows
        }
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
        private var selectedIDs: Binding<Set<DownloadID>>
        private var rowIDs: [DownloadID]
        private var context: DownloadFilter
        private weak var tableView: NSTableView?
        private var selectionAnchor: DownloadID?
        private var eventMonitor: Any?
        private var isConnecting = false

        init(
            selectedIDs: Binding<Set<DownloadID>>,
            rowIDs: [DownloadID],
            context: DownloadFilter
        ) {
            self.selectedIDs = selectedIDs
            self.rowIDs = rowIDs
            self.context = context
        }

        func update(
            selectedIDs: Binding<Set<DownloadID>>,
            rowIDs: [DownloadID],
            context: DownloadFilter
        ) {
            self.selectedIDs = selectedIDs
            self.rowIDs = rowIDs
            if self.context != context {
                self.context = context
                selectionAnchor = nil
            } else if let selectionAnchor, !rowIDs.contains(selectionAnchor) {
                self.selectionAnchor = nil
            }
        }

        func connect(to tableView: NSTableView) {
            guard self.tableView !== tableView else { return }
            if let eventMonitor {
                NSEvent.removeMonitor(eventMonitor)
            }
            self.tableView = tableView
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) {
                [weak self, weak tableView] event in
                guard let self, let tableView else { return event }
                MainActor.assumeIsolated {
                    self.handleMouseDown(event, in: tableView)
                }
                return event
            }
        }

        func beginConnecting() -> Bool {
            guard tableView == nil, !isConnecting else { return false }
            isConnecting = true
            return true
        }

        func endConnecting() {
            isConnecting = false
        }

        func disconnect() {
            if let eventMonitor {
                NSEvent.removeMonitor(eventMonitor)
                self.eventMonitor = nil
            }
            tableView = nil
            isConnecting = false
        }

        private func handleMouseDown(_ event: NSEvent, in tableView: NSTableView) {
            guard event.window === tableView.window,
                  !event.modifierFlags.contains(.control) else {
                return
            }
            let point = tableView.convert(event.locationInWindow, from: nil)
            guard tableView.bounds.contains(point) else { return }
            let row = tableView.row(at: point)
            guard row >= 0 else {
                selectionAnchor = nil
                selectedIDs.wrappedValue.removeAll()
                return
            }
            let column = tableView.column(at: point)
            guard rowIDs.indices.contains(row), column != tableView.numberOfColumns - 1 else {
                return
            }

            let clickedID = rowIDs[row]
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            var selection = selectedIDs.wrappedValue
            if modifiers.contains(.shift),
               let anchor = selectionAnchor,
               let anchorRow = rowIDs.firstIndex(of: anchor) {
                let range = min(anchorRow, row)...max(anchorRow, row)
                let rangeSelection = Set(range.map { rowIDs[$0] })
                selection = modifiers.contains(.command)
                    ? selection.union(rangeSelection)
                    : rangeSelection
            } else if modifiers.contains(.command) {
                if selection.contains(clickedID) {
                    selection.remove(clickedID)
                } else {
                    selection.insert(clickedID)
                }
                selectionAnchor = clickedID
            } else {
                selection = [clickedID]
                selectionAnchor = clickedID
            }

            if selectedIDs.wrappedValue != selection {
                selectedIDs.wrappedValue = selection
            }
        }
    }
}
#endif
