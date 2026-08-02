# SDM HTTP Range Fixture

This local-only server provides deterministic HTTP behavior for SDM download
engine development. It implements HTTP/1.1 persistent connections, byte-range
requests, `If-Range`, single-part `206` responses, multipart
`multipart/byteranges` responses, and `416` responses.

## Run

From the repository root:

```bash
python3 Fixture/range_server.py
```

The server automatically loads [`config.json`](config.json) at startup. The
following fields can be changed there:

| Field | Meaning |
| --- | --- |
| `host` | Listening interface |
| `port` | Listening TCP port |
| `max_connections` | Concurrent file transfers and ranges per request |
| `file_size` | Virtual `/empty.bin` size in bytes |
| `bytes_per_second` | `/empty.bin` transfer rate per connection |
| `chunk_size` | `/empty.bin` streaming write size |

CLI arguments can override the main multi-connection fields for one run:

```bash
python3 Fixture/range_server.py \
  --max-connections <count> \
  --file-size <bytes> \
  --bytes-per-second <bytes-per-second>
```

Endpoints:

- `http://127.0.0.1:8080/empty.bin` — a configurable virtual file with
  deterministic non-zero content, used for single- and multi-connection tests.
- `http://127.0.0.1:8080/health` — readiness check.
- `http://127.0.0.1:8080/flaky-once.bin` — returns one retryable response,
  then serves the same virtual content for retry tests.
- `http://127.0.0.1:8080/head-fallback.bin` — rejects `HEAD` and supports a
  one-byte Range probe.
- `http://127.0.0.1:8080/no-range.bin` — ignores Range and forces safe
  single-connection behavior.
- `http://127.0.0.1:8080/single-connection.bin` — an explicit manual-test
  resource that advertises no Range support and always uses one connection.
- `http://127.0.0.1:8080/fails-halfway.bin` — advertises a full response but
  closes its single connection after exactly half of the body on every try.
- `http://127.0.0.1:8080/very-slow.bin` — a fixed 1 MiB single-connection
  resource limited to 1 KiB/s for long-running pause, resume, and UI tests.
- `http://127.0.0.1:8080/github-like/pull/923` — a dynamic HTML page whose
  successful HEAD response has no length and whose GET body uses chunked
  transfer encoding, matching the reported GitHub pull-request use case.
- `http://127.0.0.1:8080/redirect.bin` — redirects to `/empty.bin`.

The binary fixture bodies are generated from each byte's absolute offset while
streaming. `file_size` controls their reported representation size and Range
bounds without creating or allocating a matching file on disk. The pattern
makes misplaced, overlapping, or missing segment writes visible in
byte-for-byte tests.

## Connection and Range limits

`max_connections` limits both:

- the number of file response bodies that the server transfers concurrently;
- the number of comma-separated ranges accepted in one `Range` request.

Requests beyond the concurrent connection limit wait for a slot. A request
containing too many ranges receives `400`; an unsatisfiable range receives
`416` with `Content-Range: bytes */<size>`. Multiple satisfiable ranges receive
a standards-compatible `multipart/byteranges` body.

The response header `X-SDM-Max-Connections` exposes the configured limit for
fixture diagnostics. It is not a standard HTTP negotiation header. HTTP only
lets a server advertise range support using `Accept-Ranges: bytes`; the client
still decides how many connections to open. Therefore the configured maximum
is a ceiling, not a guarantee that NDM or SDM will create that many connections.

For NDM multi-connection testing, use `/empty.bin`.

## Inspect

```bash
curl --head http://127.0.0.1:8080/empty.bin
curl --range 0-127 --output part-0.bin \
  http://127.0.0.1:8080/empty.bin
curl --header 'Range: bytes=0-9,100-109' \
  http://127.0.0.1:8080/empty.bin
```

Request logs include the `Range` value and current/maximum active transfers,
which makes client connection behavior visible.

## Test

```bash
python3 -m unittest discover -s Fixture/tests -v
```

The test suite verifies configuration, virtual-file streaming, single and
multipart ranges, persistent connections, multi-part reconstruction,
throttling, and enforcement of the concurrent transfer limit.
