#!/usr/bin/env python3
"""Configurable HTTP Range server for SDM integration tests."""

from __future__ import annotations

import argparse
import json
import sys
import threading
import time
from contextlib import contextmanager
from dataclasses import dataclass, fields, replace
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Iterator, Sequence
from urllib.parse import urlsplit

DEFAULT_CONFIG_PATH = Path(__file__).with_name("config.json")
DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 8080
DEFAULT_MAX_CONNECTIONS = 8
DEFAULT_FILE_SIZE = 80 * 1024 * 1024
DEFAULT_BYTES_PER_SECOND = 1024 * 1024
DEFAULT_CHUNK_SIZE = 16 * 1024

EMPTY_FILE_PATH = "/empty.bin"
FLAKY_FILE_PATH = "/flaky-once.bin"
HEAD_FALLBACK_FILE_PATH = "/head-fallback.bin"
NO_RANGE_FILE_PATH = "/no-range.bin"
REDIRECT_FILE_PATH = "/redirect.bin"
EMPTY_FILE_NAME = "empty.bin"
EMPTY_FILE_LAST_MODIFIED = "Wed, 01 Jan 2025 00:00:00 GMT"
MULTIPART_BOUNDARY = "sdm-fixture-boundary"


class RangeNotSatisfiable(ValueError):
    """Raised when a Range header selects no bytes from the fixture."""


class RangeLimitExceeded(ValueError):
    """Raised when one request asks for more ranges than configured."""


@dataclass(frozen=True)
class FixtureConfig:
    """Runtime configuration loaded when the fixture starts."""

    host: str = DEFAULT_HOST
    port: int = DEFAULT_PORT
    max_connections: int = DEFAULT_MAX_CONNECTIONS
    file_size: int = DEFAULT_FILE_SIZE
    bytes_per_second: int = DEFAULT_BYTES_PER_SECOND
    chunk_size: int = DEFAULT_CHUNK_SIZE
    quiet: bool = False

    def __post_init__(self) -> None:
        if not 0 <= self.port <= 65535:
            raise ValueError("port must be between 0 and 65535")
        if self.max_connections <= 0:
            raise ValueError("max_connections must be positive")
        if self.file_size <= 0:
            raise ValueError("file_size must be positive")
        if self.bytes_per_second < 0:
            raise ValueError("bytes_per_second cannot be negative")
        if self.chunk_size <= 0:
            raise ValueError("chunk_size must be positive")

    @classmethod
    def from_json(cls, path: Path) -> "FixtureConfig":
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as error:
            raise ValueError(f"cannot load config {path}: {error}") from error

        if not isinstance(payload, dict):
            raise ValueError(f"config {path} must contain a JSON object")

        allowed_keys = {field.name for field in fields(cls)}
        unknown_keys = set(payload) - allowed_keys
        if unknown_keys:
            names = ", ".join(sorted(unknown_keys))
            raise ValueError(f"unknown config field(s): {names}")

        try:
            return cls(**payload)
        except TypeError as error:
            raise ValueError(f"invalid config {path}: {error}") from error


@dataclass(frozen=True)
class VirtualResource:
    path: str
    name: str
    size: int
    bytes_per_second: int
    chunk_size: int

    @property
    def etag(self) -> str:
        return f'"sdm-fixture-pattern-{self.size}-v1"'


@dataclass(frozen=True)
class ResourceSlice:
    offset: int
    length: int


def pattern_bytes(offset: int, length: int) -> bytes:
    """Return deterministic non-zero content for a representation slice."""

    return bytes((((offset + index) * 31 + 17) % 251) + 1 for index in range(length))


def _parse_range_spec(value: str, size: int) -> tuple[int, int] | None:
    start_text, separator, end_text = value.strip().partition("-")
    if not separator or (not start_text and not end_text):
        raise RangeNotSatisfiable("invalid byte range syntax")

    try:
        if not start_text:
            suffix_length = int(end_text)
            if suffix_length <= 0:
                return None
            suffix_length = min(suffix_length, size)
            return size - suffix_length, size - 1

        start = int(start_text)
        if start < 0 or start >= size:
            return None

        if end_text:
            end = int(end_text)
            if end < start:
                return None
            end = min(end, size - 1)
        else:
            end = size - 1
    except ValueError as error:
        raise RangeNotSatisfiable("range bounds must be integers") from error

    return start, end


def parse_byte_ranges(
    value: str,
    size: int,
    *,
    max_ranges: int,
) -> list[tuple[int, int]]:
    """Parse an RFC 9110 byte range-set and return satisfiable ranges."""

    unit, separator, range_set = value.partition("=")
    if not separator or unit.lower().strip() != "bytes":
        raise RangeNotSatisfiable("only byte ranges are supported")

    specifications = range_set.split(",")
    if len(specifications) > max_ranges:
        raise RangeLimitExceeded(
            f"requested {len(specifications)} ranges; maximum is {max_ranges}"
        )

    ranges = [
        parsed
        for specification in specifications
        if (parsed := _parse_range_spec(specification, size)) is not None
    ]
    if not ranges:
        raise RangeNotSatisfiable("no requested range is satisfiable")
    return ranges


def parse_byte_range(value: str, size: int) -> tuple[int, int]:
    """Compatibility helper for callers that require exactly one range."""

    ranges = parse_byte_ranges(value, size, max_ranges=1)
    return ranges[0]


class FixtureHTTPServer(ThreadingHTTPServer):
    """Thread-per-connection server with a bounded transfer pool."""

    daemon_threads = True
    allow_reuse_address = True

    def __init__(self, config: FixtureConfig) -> None:
        self.config = config
        self._transfer_slots = threading.BoundedSemaphore(config.max_connections)
        self._transfer_count_lock = threading.Lock()
        self.active_transfers = 0
        self.peak_active_transfers = 0
        self._failure_lock = threading.Lock()
        self._failed_once_paths: set[str] = set()
        super().__init__((config.host, config.port), FixtureRequestHandler)

    @contextmanager
    def transfer_slot(self) -> Iterator[None]:
        self._transfer_slots.acquire()
        with self._transfer_count_lock:
            self.active_transfers += 1
            self.peak_active_transfers = max(
                self.peak_active_transfers,
                self.active_transfers,
            )
        try:
            yield
        finally:
            with self._transfer_count_lock:
                self.active_transfers -= 1
            self._transfer_slots.release()

    def resource_for_path(self, path: str) -> VirtualResource | None:
        if path in (
            EMPTY_FILE_PATH,
            FLAKY_FILE_PATH,
            HEAD_FALLBACK_FILE_PATH,
            NO_RANGE_FILE_PATH,
        ):
            return VirtualResource(
                path=path,
                name=EMPTY_FILE_NAME,
                size=self.config.file_size,
                bytes_per_second=self.config.bytes_per_second,
                chunk_size=self.config.chunk_size,
            )
        return None

    def consume_first_failure(self, path: str) -> bool:
        with self._failure_lock:
            if path in self._failed_once_paths:
                return False
            self._failed_once_paths.add(path)
            return True


class FixtureRequestHandler(BaseHTTPRequestHandler):
    """Serve deterministic zero-filled files with HTTP Range semantics."""

    protocol_version = "HTTP/1.1"
    server_version = "SDMFixture/2.0"

    @property
    def fixture_server(self) -> FixtureHTTPServer:
        return self.server  # type: ignore[return-value]

    def handle(self) -> None:
        try:
            super().handle()
        except (BrokenPipeError, ConnectionResetError):
            # Download managers close redundant persistent sockets after
            # dynamically splitting or completing a segment.
            return

    def do_HEAD(self) -> None:
        self._dispatch(include_body=False)

    def do_GET(self) -> None:
        self._dispatch(include_body=True)

    def _dispatch(self, *, include_body: bool) -> None:
        path = urlsplit(self.path).path
        if path == "/health":
            self._serve_health(include_body=include_body)
            return
        if path == REDIRECT_FILE_PATH:
            self.send_response(302)
            self.send_header("Location", EMPTY_FILE_PATH)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        if not include_body and path == HEAD_FALLBACK_FILE_PATH:
            self._send_empty_response(405)
            return
        if include_body and path == FLAKY_FILE_PATH and \
                self.fixture_server.consume_first_failure(path):
            self._send_retryable_response()
            return

        resource = self.fixture_server.resource_for_path(path)
        if resource is None:
            self._send_empty_response(404)
            return
        self._serve_virtual_file(resource, include_body=include_body)

    def _serve_health(self, *, include_body: bool) -> None:
        body = b"ok\n"
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if include_body:
            self.wfile.write(body)

    def _serve_virtual_file(
        self,
        resource: VirtualResource,
        *,
        include_body: bool,
    ) -> None:
        range_header = self.headers.get("Range")
        if resource.path == NO_RANGE_FILE_PATH:
            range_header = None
        if_range = self.headers.get("If-Range")
        if range_header and if_range not in (
            None,
            resource.etag,
            EMPTY_FILE_LAST_MODIFIED,
        ):
            range_header = None

        try:
            ranges = (
                parse_byte_ranges(
                    range_header,
                    resource.size,
                    max_ranges=self.fixture_server.config.max_connections,
                )
                if range_header
                else []
            )
        except RangeLimitExceeded:
            self._send_range_error(resource, status=400, reason="too-many-ranges")
            return
        except RangeNotSatisfiable:
            self._send_range_error(resource, status=416, reason="unsatisfiable")
            return

        if include_body:
            with self.fixture_server.transfer_slot():
                self._send_virtual_response(resource, ranges, include_body=True)
        else:
            self._send_virtual_response(resource, ranges, include_body=False)

    def _send_virtual_response(
        self,
        resource: VirtualResource,
        ranges: Sequence[tuple[int, int]],
        *,
        include_body: bool,
    ) -> None:
        if not ranges:
            body_parts: list[bytes | ResourceSlice] = [
                ResourceSlice(offset=0, length=resource.size)
            ]
            status = 200
            content_type = "application/octet-stream"
            content_range = None
        elif len(ranges) == 1:
            start, end = ranges[0]
            body_parts = [ResourceSlice(offset=start, length=end - start + 1)]
            status = 206
            content_type = "application/octet-stream"
            content_range = f"bytes {start}-{end}/{resource.size}"
        else:
            body_parts = self._multipart_body_parts(resource, ranges)
            status = 206
            content_type = f"multipart/byteranges; boundary={MULTIPART_BOUNDARY}"
            content_range = None

        content_length = sum(
            len(part) if isinstance(part, bytes) else part.length for part in body_parts
        )
        self.send_response(status)
        self._send_file_headers(
            resource,
            content_length=content_length,
            content_type=content_type,
        )
        if content_range:
            self.send_header("Content-Range", content_range)
        self.end_headers()

        if include_body:
            self._write_throttled(
                body_parts,
                bytes_per_second=resource.bytes_per_second,
                chunk_size=resource.chunk_size,
            )

    def _multipart_body_parts(
        self,
        resource: VirtualResource,
        ranges: Sequence[tuple[int, int]],
    ) -> list[bytes | ResourceSlice]:
        body_parts: list[bytes | ResourceSlice] = []
        for start, end in ranges:
            body_parts.extend(
                [
                    (
                        f"--{MULTIPART_BOUNDARY}\r\n"
                        "Content-Type: application/octet-stream\r\n"
                        f"Content-Range: bytes {start}-{end}/{resource.size}\r\n"
                        "\r\n"
                    ).encode("ascii"),
                    ResourceSlice(offset=start, length=end - start + 1),
                    b"\r\n",
                ]
            )
        body_parts.append(f"--{MULTIPART_BOUNDARY}--\r\n".encode("ascii"))
        return body_parts

    def _send_range_error(
        self,
        resource: VirtualResource,
        *,
        status: int,
        reason: str,
    ) -> None:
        self.send_response(status)
        self._send_file_headers(
            resource,
            content_length=0,
            content_type="application/octet-stream",
        )
        if status == 416:
            self.send_header("Content-Range", f"bytes */{resource.size}")
        self.send_header("X-SDM-Range-Error", reason)
        self.end_headers()

    def _send_file_headers(
        self,
        resource: VirtualResource,
        *,
        content_length: int,
        content_type: str,
    ) -> None:
        if resource.path != NO_RANGE_FILE_PATH:
            self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(content_length))
        self.send_header("Content-Disposition", f'attachment; filename="{resource.name}"')
        self.send_header("ETag", resource.etag)
        self.send_header("Last-Modified", EMPTY_FILE_LAST_MODIFIED)
        self.send_header("Cache-Control", "no-store")
        self.send_header(
            "X-SDM-Max-Connections",
            str(self.fixture_server.config.max_connections),
        )

    def _send_empty_response(self, status: int) -> None:
        self.send_response(status)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def _send_retryable_response(self) -> None:
        self.send_response(503)
        self.send_header("Content-Length", "0")
        self.send_header("Retry-After", "0")
        self.end_headers()

    def _write_throttled(
        self,
        body_parts: Sequence[bytes | ResourceSlice],
        *,
        bytes_per_second: int,
        chunk_size: int,
    ) -> None:
        started_at = time.monotonic()
        sent = 0
        try:
            for part in body_parts:
                if isinstance(part, bytes):
                    chunks = (
                        part[offset : offset + chunk_size]
                        for offset in range(0, len(part), chunk_size)
                    )
                else:
                    chunks = self._pattern_chunks(
                        part.offset,
                        part.length,
                        chunk_size=chunk_size,
                    )

                for chunk in chunks:
                    if bytes_per_second:
                        target_time = started_at + (sent + len(chunk)) / bytes_per_second
                        delay = target_time - time.monotonic()
                        if delay > 0:
                            time.sleep(delay)
                    self.wfile.write(chunk)
                    self.wfile.flush()
                    sent += len(chunk)
        except (BrokenPipeError, ConnectionResetError):
            # Pausing or cancelling a download closes the client socket normally.
            return

    @staticmethod
    def _pattern_chunks(
        offset: int,
        byte_count: int,
        *,
        chunk_size: int,
    ) -> Iterator[bytes]:
        remaining = byte_count
        while remaining:
            length = min(remaining, chunk_size)
            yield pattern_bytes(offset, length)
            offset += length
            remaining -= length

    def log_message(self, format: str, *args: object) -> None:
        if self.fixture_server.config.quiet:
            return
        range_header = self.headers.get("Range", "full")
        active = self.fixture_server.active_transfers
        sys.stderr.write(
            f"{self.address_string()} [{active}/"
            f"{self.fixture_server.config.max_connections}] "
            f"Range={range_header} - {format % args}\n"
        )


def create_server(config: FixtureConfig | None = None) -> FixtureHTTPServer:
    """Create a configured fixture server without starting its event loop."""

    return FixtureHTTPServer(config or FixtureConfig())


def _load_runtime_config(args: argparse.Namespace) -> FixtureConfig:
    config = FixtureConfig.from_json(args.config)
    overrides = {
        name: value
        for name, value in {
            "host": args.host,
            "port": args.port,
            "max_connections": args.max_connections,
            "file_size": args.file_size,
            "bytes_per_second": args.bytes_per_second,
            "chunk_size": args.chunk_size,
            "quiet": args.quiet,
        }.items()
        if value is not None
    }
    return replace(config, **overrides)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG_PATH)
    parser.add_argument("--host")
    parser.add_argument("--port", type=int)
    parser.add_argument("--max-connections", type=int)
    parser.add_argument("--file-size", type=int)
    parser.add_argument("--bytes-per-second", type=int)
    parser.add_argument("--chunk-size", type=int)
    parser.add_argument("--quiet", action="store_true", default=None)
    args = parser.parse_args()

    try:
        config = _load_runtime_config(args)
        server = create_server(config)
    except ValueError as error:
        parser.error(str(error))

    actual_port = server.server_address[1]
    base_url = f"http://{config.host}:{actual_port}"
    print(
        f"SDM Fixture listening on {base_url}\n"
        f"  file: {base_url}{EMPTY_FILE_PATH} "
        f"({config.file_size} bytes, {config.bytes_per_second} B/s per connection)\n"
        f"  max concurrent connections: {config.max_connections}",
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
