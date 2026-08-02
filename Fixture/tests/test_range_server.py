from __future__ import annotations

import threading
import time
import unittest
from concurrent.futures import ThreadPoolExecutor
from contextlib import contextmanager
from dataclasses import replace
from http.client import HTTPConnection, HTTPResponse
from typing import Iterator
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from Fixture.range_server import (
    DEFAULT_CONFIG_PATH,
    DEFAULT_MAX_CONNECTIONS,
    EMPTY_FILE_PATH,
    MULTIPART_BOUNDARY,
    FixtureConfig,
    FixtureHTTPServer,
    create_server,
)


@contextmanager
def running_server(config: FixtureConfig) -> Iterator[tuple[FixtureHTTPServer, str]]:
    server = create_server(replace(config, host="127.0.0.1", port=0, quiet=True))
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    base_url = f"http://127.0.0.1:{server.server_address[1]}"
    try:
        yield server, base_url
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)


def fetch(url: str, *, range_header: str | None = None) -> HTTPResponse:
    headers = {"Range": range_header} if range_header else {}
    return urlopen(Request(url, headers=headers), timeout=10)


class RangeServerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.config = FixtureConfig(
            file_size=8192,
            bytes_per_second=0,
        )
        cls.server_context = running_server(cls.config)
        cls.server, cls.base_url = cls.server_context.__enter__()
        cls.file_url = cls.base_url + EMPTY_FILE_PATH

    @classmethod
    def tearDownClass(cls) -> None:
        cls.server_context.__exit__(None, None, None)

    def test_committed_config_matches_runtime_defaults(self) -> None:
        config = FixtureConfig.from_json(DEFAULT_CONFIG_PATH)
        self.assertEqual(config.max_connections, DEFAULT_MAX_CONNECTIONS)
        self.assertEqual(config.max_connections, 8)
        self.assertEqual(config.file_size, 80 * 1024 * 1024)
        self.assertEqual(config.bytes_per_second, 1024 * 1024)

    def test_head_describes_configured_virtual_file(self) -> None:
        response = urlopen(Request(self.file_url, method="HEAD"), timeout=10)
        self.assertEqual(response.status, 200)
        self.assertEqual(response.headers["Content-Length"], "8192")
        self.assertEqual(response.headers["Accept-Ranges"], "bytes")
        self.assertEqual(response.headers["X-SDM-Max-Connections"], "8")
        self.assertEqual(response.headers["Content-Disposition"], 'attachment; filename="empty.bin"')
        self.assertEqual(response.read(), b"")

    def test_full_get_returns_configured_zero_filled_file(self) -> None:
        with fetch(self.file_url) as response:
            self.assertEqual(response.status, 200)
            self.assertEqual(response.read(), bytes(self.config.file_size))

    def test_range_get_returns_partial_content(self) -> None:
        with fetch(self.file_url, range_header="bytes=100-199") as response:
            self.assertEqual(response.status, 206)
            self.assertEqual(response.headers["Content-Range"], "bytes 100-199/8192")
            self.assertEqual(response.headers["Content-Length"], "100")
            self.assertEqual(response.read(), bytes(100))

    def test_suffix_and_open_ended_ranges_are_supported(self) -> None:
        with fetch(self.file_url, range_header="bytes=-16") as response:
            self.assertEqual(response.headers["Content-Range"], "bytes 8176-8191/8192")
            self.assertEqual(len(response.read()), 16)

        with fetch(self.file_url, range_header="bytes=8168-") as response:
            self.assertEqual(response.headers["Content-Range"], "bytes 8168-8191/8192")
            self.assertEqual(len(response.read()), 24)

    def test_multiple_ranges_return_multipart_byteranges(self) -> None:
        with fetch(self.file_url, range_header="bytes=0-3,100-103") as response:
            body = response.read()
            self.assertEqual(response.status, 206)
            self.assertEqual(
                response.headers["Content-Type"],
                f"multipart/byteranges; boundary={MULTIPART_BOUNDARY}",
            )
            self.assertIn(b"Content-Range: bytes 0-3/8192", body)
            self.assertIn(b"Content-Range: bytes 100-103/8192", body)
            self.assertTrue(body.endswith(f"--{MULTIPART_BOUNDARY}--\r\n".encode()))

    def test_request_over_range_limit_returns_400(self) -> None:
        config = replace(
            self.config,
            max_connections=2,
        )
        with running_server(config) as (_, base_url):
            with self.assertRaises(HTTPError) as context:
                fetch(
                    base_url + EMPTY_FILE_PATH,
                    range_header="bytes=0-0,2-2,4-4",
                )

        self.assertEqual(context.exception.code, 400)
        self.assertEqual(context.exception.headers["X-SDM-Range-Error"], "too-many-ranges")

    def test_unsatisfiable_range_returns_416(self) -> None:
        with self.assertRaises(HTTPError) as context:
            fetch(self.file_url, range_header="bytes=8192-9000")

        self.assertEqual(context.exception.code, 416)
        self.assertEqual(context.exception.headers["Content-Range"], "bytes */8192")

    def test_eight_ranges_reconstruct_the_configured_fixture(self) -> None:
        ranges = [(start, start + 1023) for start in range(0, 8192, 1024)]

        def fetch_part(bounds: tuple[int, int]) -> bytes:
            start, end = bounds
            with fetch(self.file_url, range_header=f"bytes={start}-{end}") as response:
                self.assertEqual(response.status, 206)
                self.assertEqual(
                    response.headers["Content-Range"],
                    f"bytes {start}-{end}/8192",
                )
                return response.read()

        with ThreadPoolExecutor(max_workers=8) as executor:
            parts = list(executor.map(fetch_part, ranges))

        self.assertEqual(b"".join(parts), bytes(8192))

    def test_http_11_connection_can_be_reused(self) -> None:
        connection = HTTPConnection(
            "127.0.0.1",
            self.server.server_address[1],
            timeout=10,
        )
        try:
            connection.request("GET", EMPTY_FILE_PATH, headers={"Range": "bytes=0-9"})
            first_response = connection.getresponse()
            self.assertEqual(first_response.read(), bytes(10))
            first_socket = connection.sock
            self.assertIsNotNone(first_socket)

            connection.request("GET", EMPTY_FILE_PATH, headers={"Range": "bytes=10-19"})
            second_response = connection.getresponse()
            self.assertEqual(second_response.read(), bytes(10))
            self.assertIs(connection.sock, first_socket)
        finally:
            connection.close()

    def test_max_connections_caps_active_range_transfers(self) -> None:
        config = FixtureConfig(
            max_connections=2,
            file_size=160,
            bytes_per_second=40,
            chunk_size=10,
        )

        with running_server(config) as (server, base_url):
            file_url = base_url + EMPTY_FILE_PATH
            ranges = [f"bytes={start}-{start + 39}" for start in range(0, 160, 40)]

            def fetch_body(header: str) -> bytes:
                with fetch(file_url, range_header=header) as response:
                    return response.read()

            started_at = time.monotonic()
            with ThreadPoolExecutor(max_workers=4) as executor:
                bodies = list(executor.map(fetch_body, ranges))
            elapsed = time.monotonic() - started_at

        self.assertEqual(bodies, [bytes(40)] * 4)
        self.assertEqual(server.peak_active_transfers, 2)
        self.assertGreaterEqual(elapsed, 1.7)
        self.assertLess(elapsed, 4.0)


if __name__ == "__main__":
    unittest.main()
