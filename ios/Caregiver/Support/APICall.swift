import Foundation

extension AppError {
    /// Maps a thrown error (transport, decoding, unexpected status) to a friendly message.
    static func from(_ error: Error) -> AppError {
        if error is URLError { return .transport }
        if let appError = error as? AppError { return appError }
        return .unknown
    }
}
