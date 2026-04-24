import Foundation

struct AIRetryPolicy: Sendable {
    let maxAttempts: Int
    let retryDelay: Duration

    static let standard = AIRetryPolicy(maxAttempts: 2, retryDelay: .seconds(1))

    func shouldRetry(error: Error, attempt: Int) -> Bool {
        guard attempt < maxAttempts else { return false }

        if let planError = error as? NLPlanError {
            switch planError {
            case .aiRequestTimeout, .networkUnavailable:
                return true
            case .aiAPIError(let statusCode, _):
                return [408, 429, 500, 502, 503, 504].contains(statusCode)
            default:
                return false
            }
        }

        return false
    }
}

actor AIExecutionCoordinator {
    func run<T: Sendable>(
        policy: AIRetryPolicy = .standard,
        operation: @Sendable () async throws -> T
    ) async throws -> T {
        var attempt = 1

        while true {
            do {
                return try await operation()
            } catch {
                guard policy.shouldRetry(error: error, attempt: attempt) else {
                    throw error
                }
                attempt += 1
                try await Task.sleep(for: policy.retryDelay)
            }
        }
    }
}
