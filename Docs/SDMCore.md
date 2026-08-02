# SDMCore integration

`SDMCore` is the only module an app target imports. A manager owns one native
engine, one SQLite history database, one temporary directory, and a bounded
active-download scheduler.

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
    temporaryDirectory: support.appending(path: "Partial", directoryHint: .isDirectory)
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

// App termination:
observation.cancel()
await manager.shutdown()
```

Command methods return after native acceptance or rejection. A command may be
followed immediately by another legal engine state, so UI code should consume
snapshots instead of assuming that an intermediate state remains visible.

On macOS App Sandbox, the application layer owns security-scoped bookmarks and
must keep destination access active for the lifetime of the transfer. Core
persists paths and transfer metadata, but never persists credentials, cookies,
or request headers.

Recovery changes in-flight tasks to `paused`. Resume uses persisted Range
offsets and `If-Range` validators; an incompatible response fails before new
bytes can be written into the partial representation.
