# SDMCore integration

`SDMCore` is the only module an app target imports. A manager owns one native
libcurl backend, one URLSession backend, their persistent stores, and bounded
active-download schedulers. The facade routes each task to its owning backend
and merges both update streams.

```swift
import SDMCore

let support = try FileManager.default.url(
    for: .applicationSupportDirectory,
    in: .userDomainMask,
    appropriateFor: nil,
    create: true
).appending(path: "SwiftyDownloadManager", directoryHint: .isDirectory)

let manager = try DownloadManager(configuration: .init(
    databaseURL: support.appending(path: "downloads.sqlite3"),
    temporaryDirectory: support.appending(
        path: "PartialDownloads",
        directoryHint: .isDirectory
    ),
    defaultEngine: .libcurl,
    urlSessionIdentifier: "com.example.app.background-downloads"
))

let observation = Task { @MainActor in
    for await update in await manager.updates() {
        // Assign update.snapshots to the app's observable presentation model.
    }
}

let id = try await manager.enqueue(DownloadRequest(
    url: sourceURL,
    destinationDirectory: destinationURL,
    connectionLimit: connectionCount
))

// Change the backend used by future tasks without interrupting existing ones.
try await manager.setDefaultEngine(.urlSession)

for descriptor in await manager.engineDescriptors() {
    print(descriptor.kind, descriptor.features)
}

// App termination:
observation.cancel()
await manager.shutdown()
```

Command methods return after native acceptance or rejection. A command may be
followed immediately by another legal engine state, so UI code should consume
snapshots instead of assuming that an intermediate state remains visible.

`DownloadSnapshot` includes stable `createdAt`, `startedAt`, `lastAttemptAt`,
`completedAt`, and `updatedAt` lifecycle values. Persistent, bounded diagnostic
history is available through:

```swift
let events = try await manager.diagnosticEvents(for: id)
```

The engine migrates schema v1 databases to v2 transactionally. It refuses a
newer unsupported schema with a typed persistence error rather than replacing
the user's history. SQLite uses foreign keys and WAL mode; graceful shutdown
checkpoints the WAL after the final task checkpoint.

On macOS App Sandbox, the application layer owns security-scoped bookmarks and
must keep destination access active for the lifetime of the transfer. Core
persists paths and transfer metadata, but never persists credentials, cookies,
or request headers.

Recovery changes in-flight tasks to `paused`. Resume uses persisted Range
offsets and `If-Range` validators; an incompatible response fails before new
bytes can be written into the partial representation.

For multi-connection libcurl downloads, the initial representation is divided
evenly across the requested connections. When one connection finishes early,
the engine reclaims the largest eligible in-flight Range, preserves its
downloaded prefix, and divides only its remaining tail between two requests.
This keeps connection slots busy without overlapping byte coverage. Dynamic
segments are checkpointed with the rest of the download and survive pause,
restart, and retry.

`remove(_:)` removes task metadata, segment checkpoints, diagnostics, and any
partial representation. It never removes a finalized destination file.

The libcurl backend stores its history in SQLite. URLSession keeps a separate
JSON state file next to that database so its opaque resume data and background
session ownership remain independent. URLSession accepts one connection and no
bandwidth limit; requesting either unsupported feature throws
`.unsupportedFeature`.

Host apps that accept arbitrary plain-HTTP URLs must configure an appropriate
App Transport Security exception for URLSession. SDMApp declares
`NSAllowsArbitraryLoads` because a download manager cannot enumerate destination
domains in advance; this exception should be called out in App Store review
notes. HTTPS remains the recommended default.
