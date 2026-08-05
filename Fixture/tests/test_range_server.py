from __future__ import annotations

import threading
import time
import unittest
from concurrent.futures import ThreadPoolExecutor
from contextlib import contextmanager
from dataclasses import replace
from http.client import HTTPConnection, HTTPResponse, IncompleteRead
from typing import Iterator
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from Fixture.range_server import (
    DEFAULT_CONFIG_PATH,
    DEFAULT_MAX_CONCURRENT_TRANSFERS,
    DEFAULT_MAX_RANGES_PER_REQUEST,
    DYNAMIC_HTML_BODY,
    DYNAMIC_HTML_PATH,
    EMPTY_FILE_PATH,
    FLAKY_FILE_PATH,
    HALFWAY_FAILURE_FILE_PATH,
    HEAD_FALLBACK_FILE_PATH,
    NO_RANGE_FILE_PATH,
    REDIRECT_FILE_PATH,
    SINGLE_CONNECTION_FILE_PATH,
    VERY_SLOW_BYTES_PER_SECOND,
    VERY_SLOW_FILE_PATH,
    VERY_SLOW_FILE_SIZE,
    MULTIPART_BOUNDARY,
    FixtureConfig,
    FixtureHTTPServer,
    create_server,
    pattern_bytes,
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
        self.assertEqual(
            config.max_concurrent_transfers,
            DEFAULT_MAX_CONCURRENT_TRANSFERS,
        )
        self.assertEqual(config.max_concurrent_transfers, 8)
        self.assertEqual(
            config.max_ranges_per_request,
            DEFAULT_MAX_RANGES_PER_REQUEST,
        )
        self.assertEqual(config.file_size, 80 * 1024 * 1024)
        self.assertEqual(config.bytes_per_second, 1024 * 1024)

    def test_head_describes_configured_virtual_file(self) -> None:
        response = urlopen(Request(self.file_url, method="HEAD"), timeout=10)
        self.assertEqual(response.status, 200)
        self.assertEqual(response.headers["Content-Length"], "8192")
        self.assertEqual(response.headers["Accept-Ranges"], "bytes")
        self.assertIsNone(response.headers["X-SDM-Max-Connections"])
        self.assertEqual(response.headers["Content-Disposition"], 'attachment; filename="empty.bin"')
        self.assertEqual(response.read(), b"")

    def test_full_get_returns_configured_pattern_file(self) -> None:
        with fetch(self.file_url) as response:
            self.assertEqual(response.status, 200)
            self.assertEqual(response.read(), pattern_bytes(0, self.config.file_size))

    def test_range_get_returns_partial_content(self) -> None:
        with fetch(self.file_url, range_header="bytes=100-199") as response:
            self.assertEqual(response.status, 206)
            self.assertEqual(response.headers["Content-Range"], "bytes 100-199/8192")
            self.assertEqual(response.headers["Content-Length"], "100")
            self.assertEqual(response.read(), pattern_bytes(100, 100))

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
            max_ranges_per_request=2,
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

    def test_flaky_endpoint_fails_once_then_serves_the_virtual_file(self) -> None:
        url = self.base_url + FLAKY_FILE_PATH
        with self.assertRaises(HTTPError) as context:
            fetch(url)
        self.assertEqual(context.exception.code, 503)
        self.assertEqual(context.exception.headers["Retry-After"], "0")

        with fetch(url) as response:
            self.assertEqual(response.read(), pattern_bytes(0, self.config.file_size))

    def test_head_fallback_endpoint_rejects_head_but_accepts_range_get(self) -> None:
        url = self.base_url + HEAD_FALLBACK_FILE_PATH
        with self.assertRaises(HTTPError) as context:
            urlopen(Request(url, method="HEAD"), timeout=10)
        self.assertEqual(context.exception.code, 405)

        with fetch(url, range_header="bytes=0-0") as response:
            self.assertEqual(response.status, 206)
            self.assertEqual(response.headers["Content-Range"], "bytes 0-0/8192")
            self.assertEqual(response.read(), pattern_bytes(0, 1))

    def test_no_range_endpoint_ignores_range_requests(self) -> None:
        url = self.base_url + NO_RANGE_FILE_PATH
        with fetch(url, range_header="bytes=10-19") as response:
            self.assertEqual(response.status, 200)
            self.assertIsNone(response.headers["Accept-Ranges"])
            self.assertEqual(response.read(), pattern_bytes(0, self.config.file_size))

    def test_single_connection_endpoint_disables_ranges(self) -> None:
        url = self.base_url + SINGLE_CONNECTION_FILE_PATH
        head = urlopen(Request(url, method="HEAD"), timeout=10)
        self.assertIsNone(head.headers["Accept-Ranges"])

        with fetch(url, range_header="bytes=10-19") as response:
            self.assertEqual(response.status, 200)
            self.assertEqual(response.read(), pattern_bytes(0, self.config.file_size))

    def test_halfway_failure_closes_each_response_mid_body(self) -> None:
        url = self.base_url + HALFWAY_FAILURE_FILE_PATH
        expected_length = self.config.file_size // 2

        for _ in range(2):
            with fetch(url) as response:
                self.assertEqual(response.headers["Content-Length"], "8192")
                with self.assertRaises(IncompleteRead) as context:
                    response.read()
                self.assertEqual(
                    context.exception.partial,
                    pattern_bytes(0, expected_length),
                )

    def test_very_slow_endpoint_has_a_fixed_single_connection_profile(self) -> None:
        url = self.base_url + VERY_SLOW_FILE_PATH
        response = urlopen(Request(url, method="HEAD"), timeout=10)
        self.assertEqual(response.headers["Content-Length"], str(VERY_SLOW_FILE_SIZE))
        self.assertEqual(
            response.headers["X-SDM-Bytes-Per-Second"],
            str(VERY_SLOW_BYTES_PER_SECOND),
        )
        self.assertIsNone(response.headers["Accept-Ranges"])

    def test_dynamic_html_has_unknown_length_and_wildcard_range_total(self) -> None:
        url = self.base_url + DYNAMIC_HTML_PATH
        head = urlopen(Request(url, method="HEAD"), timeout=10)
        self.assertEqual(head.status, 200)
        self.assertEqual(head.headers["Content-Type"], "text/html; charset=utf-8")
        self.assertEqual(head.headers["Accept-Ranges"], "bytes")
        self.assertIsNone(head.headers["Content-Length"])
        self.assertIsNone(head.headers["Content-Disposition"])

        with fetch(url) as response:
            self.assertEqual(response.status, 200)
            self.assertIsNone(response.headers["Content-Length"])
            self.assertEqual(response.read(), DYNAMIC_HTML_BODY)

        with fetch(url, range_header="bytes=0-0") as response:
            self.assertEqual(response.status, 206)
            self.assertEqual(response.headers["Content-Range"], "bytes 0-0/*")
            self.assertEqual(response.read(), DYNAMIC_HTML_BODY[:1])

    def test_redirect_endpoint_resolves_to_empty_file(self) -> None:
        with fetch(self.base_url + REDIRECT_FILE_PATH) as response:
            self.assertEqual(response.url, self.file_url)
            self.assertEqual(response.read(), pattern_bytes(0, self.config.file_size))

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

        self.assertEqual(b"".join(parts), pattern_bytes(0, 8192))

    def test_http_11_connection_can_be_reused(self) -> None:
        connection = HTTPConnection(
            "127.0.0.1",
            self.server.server_address[1],
            timeout=10,
        )
        try:
            connection.request("GET", EMPTY_FILE_PATH, headers={"Range": "bytes=0-9"})
            first_response = connection.getresponse()
            self.assertEqual(first_response.read(), pattern_bytes(0, 10))
            first_socket = connection.sock
            self.assertIsNotNone(first_socket)

            connection.request("GET", EMPTY_FILE_PATH, headers={"Range": "bytes=10-19"})
            second_response = connection.getresponse()
            self.assertEqual(second_response.read(), pattern_bytes(10, 10))
            self.assertIs(connection.sock, first_socket)
        finally:
            connection.close()

    def test_excess_range_requests_queue_at_server_transfer_limit(self) -> None:
        config = FixtureConfig(
            max_concurrent_transfers=8,
            file_size=1_280,
            bytes_per_second=80,
            chunk_size=10,
        )

        with running_server(config) as (server, base_url):
            file_url = base_url + EMPTY_FILE_PATH
            ranges = [
                f"bytes={start}-{start + 39}"
                for start in range(0, config.file_size, 40)
            ]
            clients_ready = threading.Barrier(len(ranges))

            def fetch_body(header: str) -> bytes:
                clients_ready.wait(timeout=10)
                with fetch(file_url, range_header=header) as response:
                    return response.read()

            started_at = time.monotonic()
            with ThreadPoolExecutor(max_workers=len(ranges)) as executor:
                bodies = list(executor.map(fetch_body, ranges))
            elapsed = time.monotonic() - started_at

        self.assertEqual(
            bodies,
            [
                pattern_bytes(start, 40)
                for start in range(0, config.file_size, 40)
            ],
        )
        self.assertEqual(len(ranges), 32)
        self.assertEqual(server.peak_active_transfers, 8)
        self.assertGreaterEqual(elapsed, 1.7)


if __name__ == "__main__":
    unittest.main()
