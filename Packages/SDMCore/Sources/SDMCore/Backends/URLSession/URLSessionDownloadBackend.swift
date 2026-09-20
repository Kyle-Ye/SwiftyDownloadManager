import Foundation

actor URLSessionDownloadBackend: DownloadEngineBackend {
    nonisolated let descriptor: DownloadEngineDescriptor

    private let configuration: DownloadManagerConfiguration
    private let store: URLSessionDownloadStore
    private let delegate: URLSessionDownloadDelegateBridge
    private var records: [DownloadID: URLSessionDownloadRecord]
    private var activeTasks: [DownloadID: URLSessionDownloadTask] = [:]
    private var continuations: [UUID: AsyncStream<DownloadUpdate>.Continuation] = [:]
    private var progressSamples: [DownloadID: (bytes: UInt64, date: Date)] = [:]
    private var sessionStorage: URLSession?
    private var browserSession: URLSession?
    private var learnedCookies: [DownloadID: [String: DownloadCookie]] = [:]
    private var sequence: UInt64 = 0
    private var isShutDown = false
    private var didRestoreSession = false

    init(configuration: DownloadManagerConfiguration) throws {
        guard configuration.maximumActiveDownloads > 0 else {
            throw DownloadError(
                code: .invalidArgument,
                message: "Download manager limits must be positive"
            )
        }
        self.configuration = configuration
        store = URLSessionDownloadStore(databaseURL: configuration.databaseURL)
        let stagingDirectory = configuration.temporaryDirectory.appending(
            path: "URLSession",
            directoryHint: .isDirectory
        )
        delegate = URLSessionDownloadDelegateBridge(stagingDirectory: stagingDirectory)

        var features: Set<DownloadFeature> = [
            .persistentRecovery,
            .systemTrustStore,
        ]
        if configuration.urlSessionIdentifier != nil {
            features.insert(.backgroundTransfers)
        }
        descriptor = DownloadEngineDescriptor(
            kind: .urlSession,
            version: "Foundation",
            features: features,
            maximumConnectionsPerDownload: 1
        )

        let restored = try store.load()
        var restoredRecords: [DownloadID: URLSessionDownloadRecord] = [:]
        for record in restored {
            guard restoredRecords.updateValue(record, forKey: record.snapshot.id) == nil else {
                throw DownloadError(
                    code: .persistence,
                    message: "URLSession history contains a duplicate download identity."
                )
            }
        }
        records = restoredRecords
        if configuration.urlSessionIdentifier == nil {
            for id in records.keys {
                guard var record = records[id],
                      record.snapshot.state.requiresTaskRestoration else { continue }
                record.snapshot = record.snapshot.replacing(
                    state: .paused,
                    bytesPerSecond: 0,
                    estimatedTimeRemaining: .some(nil),
                    error: .some(nil)
                )
                records[id] = record
            }
        }
    }

    func enqueue(_ request: DownloadRequest) async throws -> DownloadID {
        try request.validateContext()
        try validate(request)
        guard records[request.id] == nil else {
            throw DownloadError(code: .invalidArgument, message: "Download ID already exists")
        }
        let now = Date.now
        let filename = request.filename?.nonEmptyLastPathComponent
            ?? request.url.lastPathComponent.nonEmptyValue
            ?? "download"
        let snapshot = DownloadSnapshot(
            id: request.id,
            sourceURL: request.url,
            filename: filename,
            state: .queued,
            createdAt: now,
            updatedAt: now,
            engine: .urlSession
        )
        var record = URLSessionDownloadRecord(
            request: request,
            snapshot: snapshot,
            resumeData: nil,
            events: []
        )
        appendEvent("Queued with URLSession.", to: &record)
        records[request.id] = record
        try persist()
        broadcast()
        makeSessionIfNeeded()
        schedule()
        return request.id
    }

    func pause(_ id: DownloadID) async throws {
        var record = try requiredRecord(id)
        guard [.queued, .downloading, .retrying].contains(record.snapshot.state) else {
            throw invalidState("pause", id: id)
        }
        if record.snapshot.state == .queued {
            record.snapshot = record.snapshot.replacing(state: .paused)
            appendEvent("Download paused.", to: &record)
            records[id] = record
            try persist()
            broadcast()
            return
        }

        record.snapshot = record.snapshot.replacing(state: .pausing)
        records[id] = record
        broadcast()
        let resumeData = await cancelProducingResumeData(activeTasks[id])
        activeTasks[id] = nil
        record = try requiredRecord(id)
        record.resumeData = record.request.requiresRequestContext ? nil : resumeData
        record.snapshot = record.snapshot.replacing(
            state: .paused,
            bytesPerSecond: 0,
            estimatedTimeRemaining: .some(nil)
        )
        appendEvent("Download paused.", to: &record)
        records[id] = record
        try persist()
        broadcast()
        schedule()
    }

    func resume(_ id: DownloadID) async throws {
        var record = try requiredRecord(id)
        try record.request.validateContext()
        guard record.snapshot.state == .paused else {
            throw invalidState("resume", id: id)
        }
        record.snapshot = record.snapshot.replacing(
            state: .queued,
            error: .some(nil),
            lastAttemptAt: .some(Date.now)
        )
        appendEvent("Download queued to resume.", to: &record)
        records[id] = record
        try persist()
        broadcast()
        makeSessionIfNeeded()
        schedule()
    }

    func cancel(_ id: DownloadID) async throws {
        var record = try requiredRecord(id)
        guard record.snapshot.state != .completed,
              record.snapshot.state != .cancelled else {
            throw invalidState("cancel", id: id)
        }
        activeTasks[id]?.cancel()
        activeTasks[id] = nil
        record.resumeData = nil
        record.snapshot = record.snapshot.replacing(
            state: .cancelled,
            bytesPerSecond: 0,
            estimatedTimeRemaining: .some(nil),
            error: .some(nil)
        )
        appendEvent("Download cancelled.", to: &record)
        records[id] = record
        try persist()
        broadcast()
        schedule()
    }

    func retry(_ id: DownloadID) async throws {
        var record = try requiredRecord(id)
        try record.request.validateContext()
        guard [.failed, .cancelled].contains(record.snapshot.state) else {
            throw invalidState("retry", id: id)
        }
        record.snapshot = record.snapshot.replacing(
            state: .queued,
            bytesPerSecond: 0,
            estimatedTimeRemaining: .some(nil),
            error: .some(nil),
            lastAttemptAt: .some(Date.now)
        )
        appendEvent("Download queued to retry.", to: &record)
        records[id] = record
        try persist()
        broadcast()
        makeSessionIfNeeded()
        schedule()
    }

    func remove(_ id: DownloadID) async throws {
        let record = try requiredRecord(id)
        guard [.completed, .failed, .cancelled, .paused].contains(record.snapshot.state) else {
            throw invalidState("remove", id: id)
        }
        activeTasks[id]?.cancel()
        activeTasks[id] = nil
        records[id] = nil
        progressSamples[id] = nil
        try persist()
        broadcast()
    }

    func snapshot(for id: DownloadID) async throws -> DownloadSnapshot {
        try requiredRecord(id).snapshot
    }

    func allSnapshots() async throws -> [DownloadSnapshot] {
        records.values.map(\.snapshot).sorted { $0.updatedAt > $1.updatedAt }
    }

    func diagnosticEvents(for id: DownloadID) async throws -> [DownloadDiagnosticEvent] {
        try requiredRecord(id).events
    }

    func updates() -> AsyncStream<DownloadUpdate> {
        makeSessionIfNeeded()
        let token = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            continuations[token] = continuation
            continuation.yield(DownloadUpdate(
                sequence: sequence,
                snapshots: records.values.map(\.snapshot).sorted { $0.updatedAt > $1.updatedAt }
            ))
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeContinuation(token) }
            }
        }
    }

    func shutdown() async {
        guard !isShutDown else { return }
        isShutDown = true
        try? persist()
        sessionStorage?.finishTasksAndInvalidate()
        sessionStorage = nil
        browserSession?.invalidateAndCancel()
        browserSession = nil
        learnedCookies.removeAll()
        activeTasks.removeAll()
        for continuation in continuations.values {
            continuation.finish()
        }
        continuations.removeAll()
    }

    func didWrite(
        downloadID: DownloadID,
        totalBytesWritten: Int64,
        totalBytesExpected: Int64,
        response: HTTPURLResponse? = nil,
        sourceTaskIdentifier: Int? = nil
    ) {
        guard sourceTaskIdentifier == nil || activeTasks[downloadID]?.taskIdentifier == sourceTaskIdentifier else { return }
        guard var record = records[downloadID],
              record.snapshot.state == .downloading else { return }
        let now = Date.now
        let bytes = UInt64(max(totalBytesWritten, 0))
        let contentLength = totalBytesExpected > 0
            ? UInt64(totalBytesExpected)
            : record.snapshot.contentLength
        let speed: UInt64
        if let sample = progressSamples[downloadID] {
            let interval = now.timeIntervalSince(sample.date)
            speed = interval > 0
                ? UInt64(Double(bytes.saturatingSubtracting(sample.bytes)) / interval)
                : record.snapshot.bytesPerSecond
        } else {
            speed = record.snapshot.bytesPerSecond
        }
        progressSamples[downloadID] = (bytes, now)
        let remaining: Duration?
        if let contentLength, speed > 0, contentLength > bytes {
            remaining = .seconds(Int64((contentLength - bytes) / speed))
        } else {
            remaining = nil
        }
        // A download task exposes its final response as soon as body progress
        // arrives. Publish the resolved name now, including for paused tasks.
        let filename = response.flatMap { response in
            (200 ... 299).contains(response.statusCode)
                ? resolvedFilename(for: record.request, finalURL: response.url,
                                   suggestedFilename: response.suggestedFilename)
                : nil
        }
        record.snapshot = record.snapshot.replacing(
            finalURL: filename != nil ? .some(response?.url) : nil,
            filename: filename,
            contentLength: .some(contentLength),
            downloadedBytes: bytes,
            bytesPerSecond: speed,
            estimatedTimeRemaining: .some(remaining),
            updatedAt: now
        )
        records[downloadID] = record
        broadcast()
    }

    func didFinish(
        downloadID: DownloadID,
        stagedURL: URL,
        finalURL: URL?,
        suggestedFilename: String?,
        statusCode: Int?,
        expectedContentLength: Int64,
        mimeType: String? = nil,
        sourceTaskIdentifier: Int? = nil
    ) async {
        guard sourceTaskIdentifier == nil || activeTasks[downloadID]?.taskIdentifier == sourceTaskIdentifier else {
            try? FileManager.default.removeItem(at: stagedURL)
            return
        }
        guard var record = records[downloadID],
              record.snapshot.state == .downloading else {
            try? FileManager.default.removeItem(at: stagedURL)
            return
        }
        let unexpectedHTML = record.request.rejectsHTML &&
            ["text/html", "application/xhtml+xml"].contains(mimeType?.lowercased() ?? "")
        guard let statusCode, (200 ... 299).contains(statusCode), !unexpectedHTML else {
            try? FileManager.default.removeItem(at: stagedURL)
            fail(
                record: &record,
                code: .protocolViolation,
                message: unexpectedHTML ? DownloadRequest.unexpectedHTMLMessage
                    : "Server returned HTTP \(statusCode ?? 0)."
            )
            activeTasks[downloadID] = nil
            progressSamples[downloadID] = nil
            records[downloadID] = record
            try? persist()
            broadcast()
            schedule()
            return
        }

        do {
            let filename = resolvedFilename(for: record.request, finalURL: finalURL,
                                            suggestedFilename: suggestedFilename)
            let destinationURL = try resolvedDestinationURL(
                directory: record.request.destinationDirectory,
                filename: filename,
                policy: record.request.conflictPolicy
            )
            try FileManager.default.createDirectory(
                at: record.request.destinationDirectory,
                withIntermediateDirectories: true
            )
            let finalizingAt = Date.now
            let expectedLength = expectedContentLength > 0
                ? UInt64(expectedContentLength)
                : record.snapshot.contentLength
            record.snapshot = record.snapshot.replacing(
                finalURL: .some(finalURL),
                destinationURL: .some(destinationURL),
                filename: destinationURL.lastPathComponent,
                state: .finalizing,
                contentLength: .some(expectedLength),
                downloadedBytes: expectedLength ?? record.snapshot.downloadedBytes,
                bytesPerSecond: 0,
                estimatedTimeRemaining: .some(nil),
                error: .some(nil),
                updatedAt: finalizingAt
            )
            records[downloadID] = record
            try persist()
            broadcast()

            try await CoordinatedFileFinalizer.moveOffActor(
                from: stagedURL,
                to: destinationURL,
                replacesExisting: record.request.conflictPolicy == .replace
            )
            let now = Date.now
            let fileSize = try? destinationURL.resourceValues(forKeys: [.fileSizeKey]).fileSize
            let contentLength = fileSize.map(UInt64.init)
                ?? (expectedContentLength > 0 ? UInt64(expectedContentLength) : nil)
            record.resumeData = nil
            record.snapshot = record.snapshot.replacing(
                finalURL: .some(finalURL),
                destinationURL: .some(destinationURL),
                filename: destinationURL.lastPathComponent,
                state: .completed,
                contentLength: .some(contentLength),
                downloadedBytes: contentLength ?? record.snapshot.downloadedBytes,
                bytesPerSecond: 0,
                estimatedTimeRemaining: .some(nil),
                error: .some(nil),
                completedAt: .some(now),
                updatedAt: now
            )
            appendEvent("Download completed.", to: &record)
        } catch {
            fail(record: &record, code: .inputOutput, message: error.localizedDescription)
        }
        activeTasks[downloadID] = nil
        progressSamples[downloadID] = nil
        records[downloadID] = record
        try? persist()
        broadcast()
        schedule()
    }

    func didFail(
        downloadID: DownloadID,
        code: DownloadErrorCode,
        message: String,
        resumeData: Data?,
        sourceTaskIdentifier: Int? = nil
    ) {
        // Cancel completions can arrive after pause returns or a replacement
        // request starts. An old task must never fail its replacement.
        guard sourceTaskIdentifier == nil || activeTasks[downloadID]?.taskIdentifier == sourceTaskIdentifier else { return }
        guard var record = records[downloadID] else { return }
        if record.snapshot.state == .pausing || record.snapshot.state == .cancelled {
            return
        }
        record.resumeData = record.request.requiresRequestContext ? nil : (resumeData ?? record.resumeData)
        fail(record: &record, code: code, message: message)
        activeTasks[downloadID] = nil
        progressSamples[downloadID] = nil
        records[downloadID] = record
        try? persist()
        broadcast()
        schedule()
    }

    func didFinishBackgroundEvents(identifier: String) {
        try? persist()
        SDMCoreBackgroundSessionEvents.finish(identifier: identifier)
    }

    private func makeSessionIfNeeded() {
        guard sessionStorage == nil, !isShutDown else { return }
        delegate.backend = self
        let browserConfiguration = URLSessionConfiguration.ephemeral
        browserConfiguration.httpCookieStorage = nil
        browserConfiguration.urlCache = nil
        browserSession = URLSession(configuration: browserConfiguration, delegate: delegate, delegateQueue: nil)
        let sessionConfiguration: URLSessionConfiguration
        if let identifier = configuration.urlSessionIdentifier {
            sessionConfiguration = .background(withIdentifier: identifier)
            sessionConfiguration.sessionSendsLaunchEvents = true
            sessionConfiguration.isDiscretionary = false
        } else {
            sessionConfiguration = .default
        }
        sessionConfiguration.httpMaximumConnectionsPerHost = max(
            configuration.maximumActiveDownloads,
            1
        )
        sessionStorage = URLSession(
            configuration: sessionConfiguration,
            delegate: delegate,
            delegateQueue: nil
        )
        if configuration.urlSessionIdentifier == nil {
            didRestoreSession = true
        } else {
            Task { [weak self] in
                await self?.restoreSessionTasks()
            }
        }
    }

    private func restoreSessionTasks() async {
        guard !didRestoreSession, let sessionStorage else { return }
        didRestoreSession = true
        let tasks = await sessionStorage.allTasks
        var restoredIDs: Set<DownloadID> = []
        for case let task as URLSessionDownloadTask in tasks {
            guard let id = task.taskDescription
                .flatMap(UUID.init(uuidString:))
                .map({ DownloadID(rawValue: $0) }),
                  records[id] != nil else {
                task.cancel()
                continue
            }
            activeTasks[id] = task
            restoredIDs.insert(id)
        }

        for id in records.keys {
            guard var record = records[id],
                  record.snapshot.state.requiresTaskRestoration else { continue }
            if restoredIDs.contains(id) {
                record.snapshot = record.snapshot.replacing(state: .downloading)
            } else {
                record.snapshot = record.snapshot.replacing(
                    state: .paused,
                    bytesPerSecond: 0,
                    estimatedTimeRemaining: .some(nil)
                )
                appendEvent("Transfer was recovered in a paused state.", to: &record)
            }
            records[id] = record
        }
        try? persist()
        broadcast()
        schedule()
    }

    private func schedule() {
        guard let sessionStorage, didRestoreSession || configuration.urlSessionIdentifier == nil else {
            return
        }
        let availableSlots = max(configuration.maximumActiveDownloads - activeTasks.count, 0)
        guard availableSlots > 0 else { return }
        let queuedIDs = records.values
            .filter { $0.snapshot.state == .queued }
            .sorted { $0.snapshot.createdAt < $1.snapshot.createdAt }
            .prefix(availableSlots)
            .map(\.snapshot.id)
        for id in queuedIDs {
            guard var record = records[id] else { continue }
            if record.request.requiresRequestContext && record.request.requestContext == nil {
                fail(record: &record, code: .invalidState, message: DownloadRequest.missingContextMessage)
                records[id] = record
                continue
            }
            let session = record.request.requiresRequestContext ? (browserSession ?? sessionStorage) : sessionStorage
            let task: URLSessionDownloadTask
            if let resumeData = record.resumeData {
                task = session.downloadTask(withResumeData: resumeData)
            } else {
                var request = URLRequest(url: record.request.url)
                request.httpMethod = "GET"
                request.setValue("SwiftyDownloadManager/0.3 URLSession", forHTTPHeaderField: "User-Agent")
                if record.request.requestContext != nil {
                    request = browserRequest(request, for: id)
                }
                task = session.downloadTask(with: request)
            }
            task.taskDescription = id.description
            activeTasks[id] = task
            let now = Date.now
            record.snapshot = record.snapshot.replacing(
                state: .downloading,
                error: .some(nil),
                startedAt: .some(record.snapshot.startedAt ?? now),
                lastAttemptAt: .some(now),
                updatedAt: now
            )
            appendEvent("URLSession transfer started.", to: &record)
            records[id] = record
            progressSamples[id] = (record.snapshot.downloadedBytes, now)
            task.resume()
        }
        try? persist()
        broadcast()
    }

    func redirectedRequest(
        downloadID: DownloadID, response: HTTPURLResponse, request: URLRequest
    ) -> URLRequest? {
        guard let record = records[downloadID] else { return nil }
        guard record.request.requestContext != nil else { return request }
        guard let url = request.url,
              !(record.request.url.scheme?.lowercased() == "https" && url.scheme?.lowercased() != "https") else { return nil }
        if let responseURL = response.url {
            let headers = response.allHeaderFields.reduce(into: [String: String]()) { result, item in
                if let key = item.key as? String, let value = item.value as? String { result[key] = value }
            }
            for cookie in HTTPCookie.cookies(withResponseHeaderFields: headers, for: responseURL) {
                let value = DownloadCookie(name: cookie.name, value: cookie.value, domain: cookie.domain,
                    path: cookie.path, secure: cookie.isSecure, hostOnly: !cookie.domain.hasPrefix("."),
                    expirationDate: cookie.expiresDate?.timeIntervalSince1970)
                let host = responseURL.host?.lowercased() ?? ""
                let domain = value.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
                guard host == domain || host.hasSuffix("." + domain) else { continue }
                learnedCookies[downloadID, default: [:]][cookieKey(value)] = value
            }
        }
        return browserRequest(request, for: downloadID)
    }

    private func cookieKey(_ cookie: DownloadCookie) -> String {
        [cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased(),
         cookie.path, cookie.name].joined(separator: "\t")
    }

    private func browserRequest(_ original: URLRequest, for id: DownloadID) -> URLRequest {
        guard let context = records[id]?.request.requestContext, let url = original.url else { return original }
        var request = original
        request.httpShouldHandleCookies = false
        var cookies: [String: DownloadCookie] = [:]
        for cookie in context.cookies { cookies[cookieKey(cookie)] = cookie }
        cookies.merge(learnedCookies[id] ?? [:]) { _, learned in learned }
        let current = DownloadRequestContext(cookies: Array(cookies.values))
        request.setValue(current.cookieHeader(for: url), forHTTPHeaderField: "Cookie")
        if let userAgent = context.userAgent { request.setValue(userAgent, forHTTPHeaderField: "User-Agent") }
        request.setValue(context.referrerHeader(for: url), forHTTPHeaderField: "Referer")
        return request
    }

    private func resolvedFilename(
        for request: DownloadRequest, finalURL: URL?, suggestedFilename: String?
    ) -> String {
        request.filename?.nonEmptyLastPathComponent
            ?? suggestedFilename?.nonEmptyLastPathComponent
            ?? finalURL?.lastPathComponent.nonEmptyValue
            ?? request.url.lastPathComponent.nonEmptyValue
            ?? "download"
    }

    private func validate(_ request: DownloadRequest) throws {
        try ensureRunning()
        guard let scheme = request.url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              request.url.host != nil,
              request.destinationDirectory.isFileURL,
              request.connectionLimit > 0 else {
            throw DownloadError(code: .invalidArgument, message: "Download request is invalid")
        }
        guard request.connectionLimit == 1 else {
            throw DownloadError(
                code: .unsupportedFeature,
                message: "URLSession does not support multi-connection transfers."
            )
        }
        guard request.bandwidthLimit == nil || request.bandwidthLimit == 0 else {
            throw DownloadError(
                code: .unsupportedFeature,
                message: "URLSession does not support per-download bandwidth limits."
            )
        }
    }

    private func requiredRecord(_ id: DownloadID) throws -> URLSessionDownloadRecord {
        guard let record = records[id] else {
            throw DownloadError(code: .notFound, message: "Download was not found")
        }
        return record
    }

    private func invalidState(_ command: String, id: DownloadID) -> DownloadError {
        DownloadError(
            code: .invalidState,
            message: "Cannot \(command) download \(id.description) in its current state."
        )
    }

    private func fail(
        record: inout URLSessionDownloadRecord,
        code: DownloadErrorCode,
        message: String
    ) {
        let error = DownloadError(code: code, message: message)
        record.snapshot = record.snapshot.replacing(
            state: .failed,
            bytesPerSecond: 0,
            estimatedTimeRemaining: .some(nil),
            error: .some(error)
        )
        appendEvent(message, level: .error, code: code.rawValue, to: &record)
    }

    private func appendEvent(
        _ message: String,
        level: DownloadDiagnosticLevel = .info,
        code: UInt32 = 0,
        to record: inout URLSessionDownloadRecord
    ) {
        let nextID = (record.events.last?.id ?? 0) &+ 1
        record.events.append(DownloadDiagnosticEvent(
            id: nextID,
            timestamp: .now,
            level: level,
            code: code,
            message: message
        ))
        if record.events.count > 500 {
            record.events.removeFirst(record.events.count - 500)
        }
    }

    private func persist() throws {
        try store.save(
            records.values.map { record in
                var persisted = record
                if record.request.requiresRequestContext { persisted.resumeData = nil }
                return persisted
            }.sorted { $0.snapshot.updatedAt > $1.snapshot.updatedAt }
        )
    }

    private func broadcast() {
        sequence &+= 1
        let update = DownloadUpdate(
            sequence: sequence,
            snapshots: records.values.map(\.snapshot).sorted { $0.updatedAt > $1.updatedAt }
        )
        for continuation in continuations.values {
            continuation.yield(update)
        }
    }

    private func resolvedDestinationURL(
        directory: URL,
        filename: String,
        policy: DownloadConflictPolicy
    ) throws -> URL {
        let original = directory.appending(path: filename)
        guard FileManager.default.fileExists(atPath: original.path) else { return original }
        switch policy {
        case .replace:
            return original
        case .fail:
            throw DownloadError(
                code: .inputOutput,
                message: "A file named \(filename) already exists."
            )
        case .rename:
            let stem = original.deletingPathExtension().lastPathComponent
            let pathExtension = original.pathExtension
            for suffix in 2 ... Int.max {
                let candidateName = pathExtension.isEmpty
                    ? "\(stem) (\(suffix))"
                    : "\(stem) (\(suffix)).\(pathExtension)"
                let candidate = directory.appending(path: candidateName)
                if !FileManager.default.fileExists(atPath: candidate.path) {
                    return candidate
                }
            }
            throw DownloadError(code: .inputOutput, message: "No destination name is available.")
        }
    }

    private func cancelProducingResumeData(_ task: URLSessionDownloadTask?) async -> Data? {
        guard let task else { return nil }
        return await withCheckedContinuation { continuation in
            task.cancel { data in
                continuation.resume(returning: data)
            }
        }
    }

    private func removeContinuation(_ token: UUID) {
        continuations[token] = nil
    }

    private func ensureRunning() throws {
        guard !isShutDown else {
            throw DownloadError(code: .shuttingDown, message: "Engine is shut down")
        }
    }
}

private extension DownloadState {
    var requiresTaskRestoration: Bool {
        switch self {
        case .probing, .downloading, .pausing, .retrying, .finalizing:
            true
        case .created, .queued, .paused, .completed, .failed, .cancelled:
            false
        }
    }
}

private extension String {
    var nonEmptyValue: String? {
        isEmpty ? nil : self
    }

    var nonEmptyLastPathComponent: String? {
        let value = URL(fileURLWithPath: self).lastPathComponent
        return value.isEmpty ? nil : value
    }
}

private extension UInt64 {
    func saturatingSubtracting(_ other: UInt64) -> UInt64 {
        self >= other ? self - other : 0
    }
}
