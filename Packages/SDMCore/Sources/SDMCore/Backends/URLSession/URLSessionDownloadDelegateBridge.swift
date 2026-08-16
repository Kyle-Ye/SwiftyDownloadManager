import Foundation

final class URLSessionDownloadDelegateBridge: NSObject, URLSessionDownloadDelegate,
    URLSessionDelegate, @unchecked Sendable {
    weak var backend: URLSessionDownloadBackend?

    private let stagingDirectory: URL
    private let terminalTasks = URLSessionDelegateTaskTracker()

    init(stagingDirectory: URL) {
        self.stagingDirectory = stagingDirectory
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let id = downloadID(for: downloadTask) else { return }
        Task { [weak backend] in
            await backend?.didWrite(
                downloadID: id,
                totalBytesWritten: totalBytesWritten,
                totalBytesExpected: totalBytesExpectedToWrite
            )
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let id = downloadID(for: downloadTask) else { return }
        let stagedURL = stagingDirectory.appending(path: "\(id.description).download")
        do {
            try FileManager.default.createDirectory(
                at: stagingDirectory,
                withIntermediateDirectories: true
            )
            if FileManager.default.fileExists(atPath: stagedURL.path) {
                try FileManager.default.removeItem(at: stagedURL)
            }
            try FileManager.default.moveItem(at: location, to: stagedURL)
            let response = downloadTask.response as? HTTPURLResponse
            terminalTasks.start { [weak backend] in
                await backend?.didFinish(
                    downloadID: id,
                    stagedURL: stagedURL,
                    finalURL: response?.url,
                    suggestedFilename: response?.suggestedFilename,
                    statusCode: response?.statusCode,
                    expectedContentLength: response?.expectedContentLength ?? -1
                )
            }
        } catch {
            terminalTasks.start { [weak backend] in
                await backend?.didFail(
                    downloadID: id,
                    code: .inputOutput,
                    message: error.localizedDescription,
                    resumeData: nil
                )
            }
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error, let id = downloadID(for: task) else { return }
        let nsError = error as NSError
        let resumeData = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data
        terminalTasks.start { [weak backend] in
            await backend?.didFail(
                downloadID: id,
                code: nsError.code == NSURLErrorCancelled ? .invalidState : .network,
                message: nsError.localizedDescription,
                resumeData: resumeData
            )
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        guard let identifier = session.configuration.identifier else { return }
        Task { [weak backend, terminalTasks] in
            await terminalTasks.waitForTrackedTasks()
            await backend?.didFinishBackgroundEvents(identifier: identifier)
        }
    }

    private func downloadID(for task: URLSessionTask) -> DownloadID? {
        task.taskDescription
            .flatMap(UUID.init(uuidString:))
            .map { DownloadID(rawValue: $0) }
    }
}
