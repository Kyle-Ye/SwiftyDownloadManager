#!/usr/bin/env python3
"""Threaded, throttled HTTP Range server for SDM integration tests."""

from __future__ import annotations

import argparse
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit

DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 8080
DEFAULT_BYTES_PER_SECOND = 20
DEFAULT_CHUNK_SIZE = 10

ZERO_FILE_PATH = "/1kb-zero.bin"
ZERO_FILE_NAME = "1kb-zero.bin"
ZERO_FILE = bytes(1024)
ZERO_FILE_ETAG = '"sdm-fixture-zero-1024-v1"'
ZERO_FILE_LAST_MODIFIED = "Wed, 01 Jan 2025 00:00:00 GMT"


class RangeNotSatisfiable(ValueError):
    """Raised when a Range header cannot select bytes from the fixture."""


def parse_byte_range(value: str, size: int) -> tuple[int, int]:
    """Parse one RFC 9110 byte range and return its inclusive bounds."""

    if not value.startswith("bytes="):
        raise RangeNotSatisfiable("only byte ranges are supported")

    value = value.removeprefix("bytes=")
    if "," in value or "-" not in value:
        raise RangeNotSatisfiable("exactly one byte range is required")

    start_text, end_text = value.split("-", maxsplit=1)
    if not start_text and not end_text:
        raise RangeNotSatisfiable("empty byte range")

    try:
        if not start_text:
            suffix_length = int(end_text)
            if suffix_length <= 0:
                raise RangeNotSatisfiable("suffix length must be positive")
            suffix_length = min(suffix_length, size)
            return size - suffix_length, size - 1

        start = int(start_text)
        if start < 0 or start >= size:
            raise RangeNotSatisfiable("range starts outside the fixture")

        if end_text:
            end = int(end_text)
            if end < start:
                raise RangeNotSatisfiable("range ends before it starts")
            end = min(end, size - 1)
        else:
            end = size - 1
    except ValueError as error:
        if isinstance(error, RangeNotSatisfiable):
            raise
        raise RangeNotSatisfiable("range bounds must be integers") from error

    return start, end


class FixtureHTTPServer(ThreadingHTTPServer):
    """Thread-per-connection server carrying fixture-specific configuration."""

    daemon_threads = True
    allow_reuse_address = True

    def __init__(
        self,
        server_address: tuple[str, int],
        *,
        bytes_per_second: int = DEFAULT_BYTES_PER_SECOND,
        chunk_size: int = DEFAULT_CHUNK_SIZE,
        quiet: bool = False,
    ) -> None:
        if bytes_per_second < 0:
            raise ValueError("bytes_per_second cannot be negative")
        if chunk_size <= 0:
            raise ValueError("chunk_size must be positive")

        self.bytes_per_second = bytes_per_second
        self.chunk_size = chunk_size
        self.quiet = quiet
        super().__init__(server_address, FixtureRequestHandler)


class FixtureRequestHandler(BaseHTTPRequestHandler):
    """Serve a deterministic zero-filled file with HTTP Range semantics."""

    protocol_version = "HTTP/1.1"
    server_version = "SDMFixture/1.0"

    @property
    def fixture_server(self) -> FixtureHTTPServer:
        return self.server  # type: ignore[return-value]

    def do_HEAD(self) -> None:
        self._dispatch(include_body=False)

    def do_GET(self) -> None:
        self._dispatch(include_body=True)

    def _dispatch(self, *, include_body: bool) -> None:
        path = urlsplit(self.path).path
        if path == "/health":
            self._serve_health(include_body=include_body)
        elif path == ZERO_FILE_PATH:
            self._serve_zero_file(include_body=include_body)
        else:
            self._send_empty_response(404)

    def _serve_health(self, *, include_body: bool) -> None:
        body = b"ok\n"
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.close_connection = True
        if include_body:
            self.wfile.write(body)

    def _serve_zero_file(self, *, include_body: bool) -> None:
        start = 0
        end = len(ZERO_FILE) - 1
        status = 200

        range_header = self.headers.get("Range")
        if_range = self.headers.get("If-Range")
        if range_header and if_range not in (None, ZERO_FILE_ETAG, ZERO_FILE_LAST_MODIFIED):
            range_header = None

        if range_header:
            try:
                start, end = parse_byte_range(range_header, len(ZERO_FILE))
            except RangeNotSatisfiable:
                self.send_response(416)
                self._send_file_headers(content_length=0)
                self.send_header("Content-Range", f"bytes */{len(ZERO_FILE)}")
                self.send_header("Connection", "close")
                self.end_headers()
                self.close_connection = True
                return
            status = 206

        body = ZERO_FILE[start : end + 1]
        self.send_response(status)
        self._send_file_headers(content_length=len(body))
        if status == 206:
            self.send_header("Content-Range", f"bytes {start}-{end}/{len(ZERO_FILE)}")
        self.send_header("Connection", "close")
        self.end_headers()
        self.close_connection = True

        if include_body:
            self._write_throttled(body)

    def _send_file_headers(self, *, content_length: int) -> None:
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Length", str(content_length))
        self.send_header("Content-Disposition", f'attachment; filename="{ZERO_FILE_NAME}"')
        self.send_header("ETag", ZERO_FILE_ETAG)
        self.send_header("Last-Modified", ZERO_FILE_LAST_MODIFIED)
        self.send_header("Cache-Control", "no-store")

    def _send_empty_response(self, status: int) -> None:
        self.send_response(status)
        self.send_header("Content-Length", "0")
        self.send_header("Connection", "close")
        self.end_headers()
        self.close_connection = True

    def _write_throttled(self, body: bytes) -> None:
        rate = self.fixture_server.bytes_per_second
        if rate == 0:
            self.wfile.write(body)
            return

        started_at = time.monotonic()
        sent = 0
        try:
            while sent < len(body):
                chunk = body[sent : sent + self.fixture_server.chunk_size]
                target_time = started_at + (sent + len(chunk)) / rate
                delay = target_time - time.monotonic()
                if delay > 0:
                    time.sleep(delay)
                self.wfile.write(chunk)
                self.wfile.flush()
                sent += len(chunk)
        except (BrokenPipeError, ConnectionResetError):
            # Pausing or cancelling a download closes the client socket normally.
            return

    def log_message(self, format: str, *args: object) -> None:
        if not self.fixture_server.quiet:
            super().log_message(format, *args)


def create_server(
    host: str = DEFAULT_HOST,
    port: int = DEFAULT_PORT,
    *,
    bytes_per_second: int = DEFAULT_BYTES_PER_SECOND,
    chunk_size: int = DEFAULT_CHUNK_SIZE,
    quiet: bool = False,
) -> FixtureHTTPServer:
    """Create a configured fixture server without starting its event loop."""

    return FixtureHTTPServer(
        (host, port),
        bytes_per_second=bytes_per_second,
        chunk_size=chunk_size,
        quiet=quiet,
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default=DEFAULT_HOST)
    parser.add_argument("--port", type=int, default=DEFAULT_PORT)
    parser.add_argument(
        "--bytes-per-second",
        type=int,
        default=DEFAULT_BYTES_PER_SECOND,
        help="body bytes per second for each connection; use 0 for no limit",
    )
    parser.add_argument("--chunk-size", type=int, default=DEFAULT_CHUNK_SIZE)
    args = parser.parse_args()

    try:
        server = create_server(
            args.host,
            args.port,
            bytes_per_second=args.bytes_per_second,
            chunk_size=args.chunk_size,
        )
    except ValueError as error:
        parser.error(str(error))

    actual_port = server.server_address[1]
    print(
        f"SDM Fixture listening on http://{args.host}:{actual_port}{ZERO_FILE_PATH} "
        f"({len(ZERO_FILE)} bytes, {args.bytes_per_second} B/s per connection)",
        flush=True,
    )

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopping SDM Fixture", flush=True)
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
