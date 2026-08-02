# ADR 001: Pull engine events behind a Swift actor

Status: accepted

## Decision

`SDMEngine` owns mutable download state on one C++ `std::jthread`.
`SDMEngineBridge` exposes an opaque, versioned C handle and a non-blocking event
poll. `SDMCore.DownloadManager` is the sole Swift owner and converts copied C
records into immutable Swift snapshots and a newest-value `AsyncStream`.

The bridge does not retain a Swift callback or expose a C++ type. Command IDs
are acknowledged by reliable result events; progress snapshots may be
coalesced.

## Consequences

- shutdown joins the native thread before the opaque handle is destroyed;
- SwiftUI never owns libcurl, SQLite, file descriptors, or native pointers;
- abandoned or slow stream consumers cannot grow an unbounded queue;
- engine and bridge lifecycle behavior can be tested without a main run loop;
- the actor polling interval bounds presentation latency.
