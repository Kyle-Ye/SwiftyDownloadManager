import Foundation
import Security

enum CertificateAuthorityBundle {
    static func write(to directory: URL) throws -> URL {
        #if os(macOS)
        var rawCertificates: CFArray?
        let status = SecTrustCopyAnchorCertificates(&rawCertificates)
        guard status == errSecSuccess,
              let certificates = rawCertificates as? [SecCertificate],
              !certificates.isEmpty else {
            throw DownloadError(
                code: .internalFailure,
                message: "The system trust store could not be exported for libcurl."
            )
        }

        let bundle = certificates.map { certificate in
            let data = SecCertificateCopyData(certificate) as Data
            let body = data.base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
            return "-----BEGIN CERTIFICATE-----\n\(body)\n-----END CERTIFICATE-----\n"
        }
        .joined()

        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let url = directory.appending(path: "system-ca-bundle.pem")
            try Data(bundle.utf8).write(to: url, options: .atomic)
            return url
        } catch {
            throw DownloadError(
                code: .inputOutput,
                message: "The libcurl trust bundle could not be written: \(error.localizedDescription)"
            )
        }
        #else
        guard let url = Bundle.module.url(forResource: "cacert", withExtension: "pem") else {
            throw DownloadError(
                code: .internalFailure,
                message: "The bundled libcurl trust store is unavailable."
            )
        }
        return url
        #endif
    }
}
