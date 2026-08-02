# SDM HTTP Range Fixture

This local-only server provides deterministic HTTP behavior for SDM download
engine development. It uses a thread per connection, supports single HTTP byte
ranges, and serves a 1 KiB zero-filled file.

## Run

From the repository root:

```bash
python3 Fixture/range_server.py
```

Endpoints:

- `http://127.0.0.1:8080/1kb-zero.bin` — 1,024 zero bytes
- `http://127.0.0.1:8080/health` — readiness check

The file body is limited to **20 B/s per connection** by default. A complete
single-connection transfer therefore takes about 51.2 seconds. Eight parallel
128-byte range requests each take about 6.4 seconds, making connection-level
parallelism visible without requiring a large fixture.

Inspect the metadata or request one segment:

```bash
curl --head http://127.0.0.1:8080/1kb-zero.bin
curl --range 0-127 --output part-0.bin \
  http://127.0.0.1:8080/1kb-zero.bin
```

The server supports closed, open-ended, and suffix byte ranges. Invalid or
unsatisfiable ranges return `416` with `Content-Range: bytes */1024`. Stable
`ETag` and `Last-Modified` values make pause/resume and `If-Range` behavior
repeatable.

Use `--bytes-per-second 0` to disable throttling or `--port 0` to let the OS
choose an available port. This fixture binds to loopback by default and is not
intended for deployment.

## Test

```bash
python3 -m unittest discover -s Fixture/tests -v
```

The test suite verifies metadata, full and partial responses, `416` handling,
eight-part reconstruction, per-connection throttling, and concurrent serving.
