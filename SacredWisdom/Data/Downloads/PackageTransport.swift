import Foundation

/// How a download starts: fresh, or from data a paused download produced.
enum DownloadStart: Sendable {
    case fresh(URL)
    case resume(Data, URL)
}

enum DownloadFailure: Error, Sendable, Equatable {
    /// Paused by the user; resume data is present when the server supports resuming.
    case paused(resumeData: Data?)
    case offline
    case server(status: Int)
    case other(String)
}

/// Network access for content. Only the manifest and packages are ever fetched; no user data is sent.
protocol PackageTransport: Sendable {
    func fetch(_ url: URL) async throws(DownloadFailure) -> Data
    /// Downloads to a temporary file the caller owns. Throws `.paused` when `pause(_:)` is called.
    func download(_ key: String, _ start: DownloadStart, progress: @escaping @Sendable (Double) -> Void) async throws(DownloadFailure) -> URL
    func pause(_ key: String) async
}

/// URLSession download tasks: progress, pause with resume data (where the server supports it), offline detection.
final class URLSessionPackageTransport: NSObject, PackageTransport, URLSessionDownloadDelegate, @unchecked Sendable {
    private struct Job {
        let key: String
        let continuation: CheckedContinuation<URL, any Error>
        let progress: @Sendable (Double) -> Void
        var finishedFile: URL?
    }

    private let lock = NSLock()
    private var jobs: [Int: Job] = [:]
    private var tasksByKey: [String: URLSessionDownloadTask] = [:]
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 30
        configuration.httpAdditionalHeaders = ["User-Agent": "SacredWisdom-ContentDownloader/1.0"]
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        return URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
    }()

    func fetch(_ url: URL) async throws(DownloadFailure) -> Data {
        do {
            let (data, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw DownloadFailure.server(status: http.statusCode)
            }
            return data
        } catch let failure as DownloadFailure {
            throw failure
        } catch {
            throw Self.failure(from: error)
        }
    }

    func download(_ key: String, _ start: DownloadStart, progress: @escaping @Sendable (Double) -> Void) async throws(DownloadFailure) -> URL {
        do {
            return try await withCheckedThrowingContinuation { continuation in
                let task: URLSessionDownloadTask = switch start {
                case .fresh(let url): session.downloadTask(with: url)
                case .resume(let data, _): session.downloadTask(withResumeData: data)
                }
                lock.withLock {
                    jobs[task.taskIdentifier] = Job(key: key, continuation: continuation, progress: progress)
                    tasksByKey[key] = task
                }
                task.resume()
            }
        } catch let failure as DownloadFailure {
            throw failure
        } catch {
            throw Self.failure(from: error)
        }
    }

    func pause(_ key: String) async {
        guard let task = lock.withLock({ tasksByKey[key] }) else { return }
        // The task then completes with a cancellation error carrying the resume data (see didCompleteWithError).
        _ = await task.cancelByProducingResumeData()
    }

    // MARK: URLSessionDownloadDelegate

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0, let job = lock.withLock({ jobs[downloadTask.taskIdentifier] }) else { return }
        job.progress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // The system deletes `location` when this returns, so move it now.
        let destination = FileManager.default.temporaryDirectory.appending(path: "pkg-\(UUID().uuidString).download")
        let moved = (try? FileManager.default.moveItem(at: location, to: destination)) != nil
        lock.withLock { jobs[downloadTask.taskIdentifier]?.finishedFile = moved ? destination : nil }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        guard let job = lock.withLock({ () -> Job? in
            let job = jobs.removeValue(forKey: task.taskIdentifier)
            if let job, tasksByKey[job.key] === task { tasksByKey[job.key] = nil }
            return job
        }) else { return }
        if let error {
            job.continuation.resume(throwing: Self.failure(from: error))
        } else if let http = task.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            if let file = job.finishedFile { try? FileManager.default.removeItem(at: file) }
            job.continuation.resume(throwing: DownloadFailure.server(status: http.statusCode))
        } else if let file = job.finishedFile {
            job.progress(1)
            job.continuation.resume(returning: file)
        } else {
            job.continuation.resume(throwing: DownloadFailure.other("Downloaded file could not be kept"))
        }
    }

    private static func failure(from error: any Error) -> DownloadFailure {
        guard let urlError = error as? URLError else { return .other(String(describing: error)) }
        switch urlError.code {
        case .cancelled: return .paused(resumeData: urlError.downloadTaskResumeData)
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .cannotFindHost,
             .cannotConnectToHost, .timedOut, .internationalRoamingOff:
            return .offline
        default: return .other(urlError.localizedDescription)
        }
    }
}
