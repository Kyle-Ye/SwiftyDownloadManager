import Foundation
import SDMEngineBridge

struct BridgeEvent: Sendable {
    enum Kind: UInt32, Sendable {
        case commandResult = 0
        case snapshotChanged = 1
        case removed = 2
        case engineStopped = 3
    }

    let sequence: UInt64
    let commandID: UInt64
    let downloadID: DownloadID?
    let kind: Kind
    let result: UInt32
}

final class EngineBridge: @unchecked Sendable {
    private var handle: OpaquePointer?
    private let lock = NSLock()

    init(configuration: DownloadManagerConfiguration) throws {
        var createdHandle: OpaquePointer?
        let databasePath = configuration.databaseURL.path(percentEncoded: false)
        let temporaryPath = configuration.temporaryDirectory.path(percentEncoded: false)

        let result = Self.withStringView(databasePath) { databaseView in
            Self.withStringView(temporaryPath) { temporaryView in
                var config = sdm_engine_config_t()
                config.struct_size = UInt32(MemoryLayout<sdm_engine_config_t>.size)
                config.abi_version = sdm_engine_abi_version()
                config.database_path = databaseView
                config.temporary_directory = temporaryView
                config.maximum_active_downloads = UInt32(configuration.maximumActiveDownloads)
                config.maximum_connections_per_download = UInt32(
                    configuration.maximumConnectionsPerDownload
                )
                return sdm_engine_create(&config, &createdHandle)
            }
        }
        try Self.check(result, operation: "create engine")
        guard let createdHandle else {
            throw DownloadError(
                code: .internalFailure,
                message: "Engine creation returned no handle"
            )
        }
        handle = createdHandle
    }

    deinit {
        lock.withLock {
            if let handle {
                sdm_engine_shutdown(handle)
                sdm_engine_destroy(handle)
                self.handle = nil
            }
        }
    }

    func enqueue(_ request: DownloadRequest) throws -> UInt64 {
        try lock.withLock {
            let handle = try requiredHandle()
            var commandID: UInt64 = 0
            let filename = request.filename ?? ""

            let result = try Self.withStringView(request.id.description) { idView in
                try Self.withStringView(request.url.absoluteString) { urlView in
                    Self.withStringView(
                        request.destinationDirectory.path(percentEncoded: false)
                    ) { destinationView in
                        Self.withStringView(filename) { filenameView in
                            var value = sdm_download_request_t()
                            value.struct_size = UInt32(
                                MemoryLayout<sdm_download_request_t>.size
                            )
                            value.id = idView
                            value.url = urlView
                            value.destination_directory = destinationView
                            value.filename = filenameView
                            value.connection_limit = UInt32(request.connectionLimit)
                            value.bandwidth_limit = request.bandwidthLimit ?? 0
                            value.conflict_policy = request.conflictPolicy.rawValue
                            return sdm_engine_enqueue(handle, &value, &commandID)
                        }
                    }
                }
            }
            try Self.check(result, operation: "enqueue download")
            return commandID
        }
    }

    func submit(_ command: sdm_command_t, id: DownloadID) throws -> UInt64 {
        try lock.withLock {
            let handle = try requiredHandle()
            var commandID: UInt64 = 0
            let result = Self.withStringView(id.description) { idView in
                sdm_engine_submit(handle, idView, command, &commandID)
            }
            try Self.check(result, operation: "submit command")
            return commandID
        }
    }

    func pollEvents(maximumCount: Int = 128) throws -> [BridgeEvent] {
        try lock.withLock {
            let handle = try requiredHandle()
            var rawEvents = Array(repeating: sdm_event_t(), count: maximumCount)
            var count = 0
            let result = rawEvents.withUnsafeMutableBufferPointer { buffer in
                sdm_engine_poll_events(
                    handle,
                    buffer.baseAddress,
                    buffer.count,
                    &count
                )
            }
            try Self.check(result, operation: "poll events")
            return rawEvents.prefix(count).compactMap(Self.makeEvent)
        }
    }

    func snapshot(for id: DownloadID) throws -> DownloadSnapshot {
        try lock.withLock {
            let handle = try requiredHandle()
            var rawSnapshot = sdm_download_snapshot_t()
            let result = Self.withStringView(id.description) { idView in
                sdm_engine_copy_snapshot(handle, idView, &rawSnapshot)
            }
            try Self.check(result, operation: "copy snapshot")
            return try Self.makeSnapshot(&rawSnapshot)
        }
    }

    func allSnapshots() throws -> [DownloadSnapshot] {
        try lock.withLock {
            let handle = try requiredHandle()
            var requiredCount = 0
            let countResult = sdm_engine_copy_snapshots(
                handle,
                nil,
                0,
                &requiredCount
            )
            try Self.check(countResult, operation: "count snapshots")
            guard requiredCount > 0 else { return [] }

            var rawSnapshots = Array(
                repeating: sdm_download_snapshot_t(),
                count: requiredCount
            )
            var copiedCount = 0
            let copyResult = rawSnapshots.withUnsafeMutableBufferPointer { buffer in
                sdm_engine_copy_snapshots(
                    handle,
                    buffer.baseAddress,
                    buffer.count,
                    &copiedCount
                )
            }
            try Self.check(copyResult, operation: "copy snapshots")
            return try rawSnapshots.prefix(copiedCount).map { raw in
                var mutableRaw = raw
                return try Self.makeSnapshot(&mutableRaw)
            }
        }
    }

    func shutdown() {
        lock.withLock {
            if let handle {
                sdm_engine_shutdown(handle)
            }
        }
    }

    private func requiredHandle() throws -> OpaquePointer {
        guard let handle else {
            throw DownloadError(code: .shuttingDown, message: "Engine is shut down")
        }
        return handle
    }

    private static func makeEvent(_ raw: sdm_event_t) -> BridgeEvent? {
        var mutableRaw = raw
        let idText = string(from: &mutableRaw.download_id)
        return BridgeEvent(
            sequence: raw.sequence,
            commandID: raw.command_id,
            downloadID: UUID(uuidString: idText).map { DownloadID(rawValue: $0) },
            kind: BridgeEvent.Kind(rawValue: raw.kind) ?? .snapshotChanged,
            result: raw.result
        )
    }

    private static func makeSnapshot(
        _ raw: inout sdm_download_snapshot_t
    ) throws -> DownloadSnapshot {
        let idText = string(from: &raw.id)
        let sourceText = string(from: &raw.source_url)
        guard let uuid = UUID(uuidString: idText),
              let sourceURL = URL(string: sourceText),
              let state = DownloadState(rawValue: raw.state) else {
            throw DownloadError(
                code: .internalFailure,
                message: "Engine returned an invalid snapshot"
            )
        }

        let finalText = string(from: &raw.final_url)
        let destinationText = string(from: &raw.destination_url)
        let errorText = string(from: &raw.error_message)
        let error: DownloadError?
        if raw.error_code == 0 {
            error = nil
        } else {
            error = DownloadError(
                code: DownloadErrorCode(rawValue: raw.error_code) ?? .internalFailure,
                message: errorText
            )
        }

        return DownloadSnapshot(
            id: DownloadID(rawValue: uuid),
            sourceURL: sourceURL,
            finalURL: finalText.isEmpty ? nil : URL(string: finalText),
            destinationURL: destinationText.isEmpty
                ? nil
                : URL(fileURLWithPath: destinationText),
            filename: string(from: &raw.filename),
            state: state,
            contentLength: raw.content_length_known == 0 ? nil : raw.content_length,
            downloadedBytes: raw.downloaded_bytes,
            bytesPerSecond: raw.bytes_per_second,
            estimatedTimeRemaining: raw.estimated_seconds_remaining == 0
                ? nil
                : .seconds(Int64(raw.estimated_seconds_remaining)),
            segments: [],
            error: error,
            updatedAt: Date(
                timeIntervalSince1970: Double(raw.updated_milliseconds) / 1_000
            )
        )
    }

    private static func withStringView<Result>(
        _ value: String,
        _ body: (sdm_string_view_t) throws -> Result
    ) rethrows -> Result {
        try value.utf8CString.withUnsafeBufferPointer { buffer in
            let count = max(buffer.count - 1, 0)
            return try body(sdm_string_view_t(data: buffer.baseAddress, length: count))
        }
    }

    private static func string<Value>(from value: inout Value) -> String {
        withUnsafePointer(to: &value) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: MemoryLayout<Value>.size) {
                String(cString: $0)
            }
        }
    }

    private static func check(_ result: sdm_result_t, operation: String) throws {
        guard result == SDM_RESULT_OK else {
            let rawCode = UInt32(result.rawValue)
            throw DownloadError(
                code: DownloadErrorCode(rawValue: rawCode) ?? .internalFailure,
                message: "Failed to \(operation) (\(rawCode))"
            )
        }
    }
}
