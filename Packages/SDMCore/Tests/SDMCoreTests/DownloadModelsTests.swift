import Foundation
import SDMEngineTestSupport
import XCTest
@testable import SDMCore

final class DownloadModelsTests: XCTestCase {
    func testDownloadIDDescriptionRoundTrips() throws {
        let id = DownloadID()
        let parsed = try XCTUnwrap(UUID(uuidString: id.description))
        XCTAssertEqual(parsed, id.rawValue)
    }

    func testSegmentPlannerCoversRepresentationWithoutGaps() {
        var segments = Array(
            repeating: sdm_test_segment_t(),
            count: 8
        )
        let count = sdm_test_plan_segments(80, 8, 8, &segments, segments.count)

        XCTAssertEqual(count, 8)
        XCTAssertEqual(segments[0].start, 0)
        XCTAssertEqual(segments[7].end, 79)

        for index in segments.indices {
            XCTAssertEqual(segments[index].ordinal, UInt32(index))
            XCTAssertEqual(segments[index].next, segments[index].start)
            if index > 0 {
                XCTAssertEqual(segments[index - 1].end + 1, segments[index].start)
            }
        }
    }

    func testSegmentPlannerBoundsConnectionsByContentLengthAndMaximum() {
        var segments = Array(repeating: sdm_test_segment_t(), count: 16)
        XCTAssertEqual(sdm_test_plan_segments(3, 8, 16, &segments, segments.count), 3)
        XCTAssertEqual(sdm_test_plan_segments(100, 16, 4, &segments, segments.count), 4)
        XCTAssertEqual(sdm_test_plan_segments(0, 8, 8, &segments, segments.count), 0)
    }

    func testStateMachineRejectsInvalidCommands() {
        XCTAssertTrue(sdm_test_can_transition(0, 1))
        XCTAssertFalse(sdm_test_can_transition(8, 3))

        XCTAssertEqual(sdm_test_validate_command(3, 1), 0)
        XCTAssertEqual(sdm_test_validate_command(8, 1), 3)
        XCTAssertEqual(sdm_test_validate_command(5, 2), 0)
    }

    func testCurlCertificateFailuresAreNotRetried() {
        XCTAssertFalse(sdm_test_curl_error_is_retryable(sdm_test_curl_bad_ca_file_error()))
        XCTAssertFalse(
            sdm_test_curl_error_is_retryable(sdm_test_curl_peer_verification_error())
        )
    }

    func testCurlTransientNetworkFailuresAreRetried() {
        XCTAssertTrue(sdm_test_curl_error_is_retryable(sdm_test_curl_timeout_error()))
        XCTAssertTrue(
            sdm_test_curl_error_is_retryable(sdm_test_curl_could_not_connect_error())
        )
    }

    func testSegmentSnapshotCalculatesProgress() {
        let segment = DownloadSegmentSnapshot(
            ordinal: 0,
            start: 100,
            end: 199,
            next: 125
        )
        XCTAssertEqual(segment.downloadedBytes, 25)
        XCTAssertEqual(segment.totalBytes, 100)
    }
}
