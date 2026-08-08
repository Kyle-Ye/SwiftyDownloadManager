import Foundation
import Security
import XCTest
@testable import SDMCore

#if os(macOS)
final class CertificateAuthorityBundleTests: XCTestCase {
    func testSystemCertificateAuthorityBundleWritesValidPEM() throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let bundleURL = try CertificateAuthorityBundle.write(to: directory)
        let contents = try String(contentsOf: bundleURL, encoding: .utf8)
        let beginMarker = "-----BEGIN CERTIFICATE-----"
        let endMarker = "-----END CERTIFICATE-----"
        var isReadingCertificate = false
        var encodedBody = ""
        var certificateCount = 0

        for line in contents.split(separator: "\n", omittingEmptySubsequences: false) {
            switch line {
            case Substring(beginMarker):
                XCTAssertFalse(isReadingCertificate)
                isReadingCertificate = true
                encodedBody = ""
            case Substring(endMarker):
                XCTAssertTrue(isReadingCertificate)
                let data = try XCTUnwrap(Data(base64Encoded: encodedBody))
                XCTAssertNotNil(SecCertificateCreateWithData(nil, data as CFData))
                isReadingCertificate = false
                certificateCount += 1
            default:
                if isReadingCertificate {
                    XCTAssertLessThanOrEqual(line.utf8.count, 64)
                    encodedBody.append(contentsOf: line)
                }
            }
        }

        XCTAssertFalse(isReadingCertificate)
        XCTAssertGreaterThan(certificateCount, 0)
    }
}
#endif
