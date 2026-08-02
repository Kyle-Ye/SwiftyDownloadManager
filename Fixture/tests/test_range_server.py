from __future__ import annotations

import threading
import time
import unittest
from concurrent.futures import ThreadPoolExecutor
from contextlib import contextmanager
from http.client import HTTPResponse
from typing import Iterator
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from Fixture.range_server import (
    DEFAULT_BYTES_PER_SECOND,
    ZERO_FILE,
    ZERO_FILE_ETAG,
    ZERO_FILE_PATH,
    FixtureHTTPServer,
    create_server,
)


@contextmanager
def running_server(*, bytes_per_second: int) -> Iterator[tuple[FixtureHTTPServer, str]]:
    server = create_server(
        "127.0.0.1",
        0,
        bytes_per_second=bytes_per_second,
        quiet=True,
    )
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
        cls.server_context = running_server(bytes_per_second=0)
        cls.server, cls.base_url = cls.server_context.__enter__()
        cls.file_url = cls.base_url + ZERO_FILE_PATH

    @classmethod
    def tearDownClass(cls) -> None:
        cls.server_context.__exit__(None, None, None)

    def test_head_describes_one_kibibyte_fixture(self) -> None:
        response = urlopen(Request(self.file_url, method="HEAD"), timeout=10)
        self.assertEqual(response.status, 200)
        self.assertEqual(response.headers["Content-Length"], "1024")
        self.assertEqual(response.headers["Accept-Ranges"], "bytes")
        self.assertEqual(response.headers["ETag"], ZERO_FILE_ETAG)
        self.assertEqual(response.read(), b"")

    def test_full_get_returns_zero_filled_fixture(self) -> None:
        with fetch(self.file_url) as response:
            self.assertEqual(response.status, 200)
            self.assertEqual(response.read(), ZERO_FILE)

    def test_range_get_returns_partial_content(self) -> None:
        with fetch(self.file_url, range_header="bytes=100-199") as response:
            self.assertEqual(response.status, 206)
            self.assertEqual(response.headers["Content-Range"], "bytes 100-199/1024")
            self.assertEqual(response.headers["Content-Length"], "100")
            self.assertEqual(response.read(), bytes(100))

    def test_suffix_and_open_ended_ranges_are_supported(self) -> None:
        with fetch(self.file_url, range_header="bytes=-16") as response:
            self.assertEqual(response.headers["Content-Range"], "bytes 1008-1023/1024")
            self.assertEqual(len(response.read()), 16)

        with fetch(self.file_url, range_header="bytes=1000-") as response:
            self.assertEqual(response.headers["Content-Range"], "bytes 1000-1023/1024")
            self.assertEqual(len(response.read()), 24)

    def test_unsatisfiable_range_returns_416(self) -> None:
        with self.assertRaises(HTTPError) as context:
            fetch(self.file_url, range_header="bytes=1024-2047")

        self.assertEqual(context.exception.code, 416)
        self.assertEqual(context.exception.headers["Content-Range"], "bytes */1024")

    def test_eight_ranges_reconstruct_the_fixture(self) -> None:
        ranges = [(start, start + 127) for start in range(0, len(ZERO_FILE), 128)]

        def fetch_part(bounds: tuple[int, int]) -> bytes:
            start, end = bounds
            with fetch(self.file_url, range_header=f"bytes={start}-{end}") as response:
                self.assertEqual(response.status, 206)
                self.assertEqual(
                    response.headers["Content-Range"],
                    f"bytes {start}-{end}/{len(ZERO_FILE)}",
                )
                return response.read()

        with ThreadPoolExecutor(max_workers=8) as executor:
            parts = list(executor.map(fetch_part, ranges))

        self.assertEqual(b"".join(parts), ZERO_FILE)

    def test_default_throttle_is_per_connection_and_requests_run_concurrently(self) -> None:
        self.assertEqual(DEFAULT_BYTES_PER_SECOND, 20)

        with running_server(bytes_per_second=DEFAULT_BYTES_PER_SECOND) as (_, base_url):
            file_url = base_url + ZERO_FILE_PATH
            ranges = [f"bytes={start}-{start + 39}" for start in range(0, 160, 40)]

            def fetch_body(header: str) -> bytes:
                with fetch(file_url, range_header=header) as response:
                    return response.read()

            started_at = time.monotonic()
            with ThreadPoolExecutor(max_workers=4) as executor:
                bodies = list(executor.map(fetch_body, ranges))
            elapsed = time.monotonic() - started_at

        self.assertEqual(bodies, [bytes(40)] * 4)
        self.assertGreaterEqual(elapsed, 1.5)
        self.assertLess(elapsed, 4.5)


if __name__ == "__main__":
    unittest.main()
