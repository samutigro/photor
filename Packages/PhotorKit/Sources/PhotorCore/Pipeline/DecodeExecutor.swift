import Foundation

public final class DecodeExecutor: Sendable {
    private let queue: OperationQueue
    public init(concurrency: Int = 2) {
        queue = OperationQueue()
        queue.name = "Photor.decode"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = concurrency
    }
    public func decode(_ request: DecodeRequest, using decoder: any PhotoDecoder,
                       cancellation: CancellationFlag) async throws -> DecodedImage {
        try await withCheckedThrowingContinuation { continuation in
            queue.addOperation {
                let result: Result<DecodedImage, Error> = autoreleasepool {
                    do {
                        guard !cancellation.isCancelled else { throw PhotoError.cancelled }
                        let image = try decoder.decode(request)
                        guard !cancellation.isCancelled else { throw PhotoError.cancelled }
                        return .success(image)
                    } catch { return .failure(error) }
                }
                continuation.resume(with: result)
            }
        }
    }
}
