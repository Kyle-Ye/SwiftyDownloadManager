import Foundation
import SDMEngineBridge

enum CoordinatedFileFinalizer {
    static func moveOffActor(
        from source: URL,
        to destination: URL,
        replacesExisting: Bool
    ) async throws {
        let failure = await Task.detached(priority: .utility) {
            do {
                try move(
                    from: source,
                    to: destination,
                    replacesExisting: replacesExisting
                )
                return nil as DownloadError?
            } catch let error as DownloadError {
                return error
            } catch {
                return DownloadError(
                    code: .inputOutput,
                    message: error.localizedDescription
                )
            }
        }.value
        if let failure {
            throw failure
        }
    }

    static func move(
        from source: URL,
        to destination: URL,
        replacesExisting: Bool
    ) throws {
        let sourcePath = source.path(percentEncoded: false)
        let destinationPath = destination.path(percentEncoded: false)
        var errorMessage = [CChar](repeating: 0, count: 1_024)
        let result = withStringView(sourcePath) { sourceView in
            withStringView(destinationPath) { destinationView in
                errorMessage.withUnsafeMutableBufferPointer { buffer in
                    sdm_finalize_file(
                        sourceView,
                        destinationView,
                        replacesExisting ? 1 : 0,
                        buffer.baseAddress,
                        buffer.count
                    )
                }
            }
        }
        guard result == SDM_RESULT_OK else {
            let message = errorMessage.withUnsafeBufferPointer { buffer in
                guard let baseAddress = buffer.baseAddress else { return "" }
                return String(cString: baseAddress)
            }
            throw DownloadError(
                code: .inputOutput,
                message: message.isEmpty
                    ? "The downloaded file could not be saved."
                    : message
            )
        }
    }

    private static func withStringView<Result>(
        _ value: String,
        _ body: (sdm_string_view_t) throws -> Result
    ) rethrows -> Result {
        try value.utf8CString.withUnsafeBufferPointer { buffer in
            let count = max(buffer.count - 1, 0)
            return try body(sdm_string_view_t(data: buffer.baseAddress, length: count))
        }
    }
}
