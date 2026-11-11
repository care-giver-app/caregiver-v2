import Foundation

/// A user-facing error with a friendly message.
struct AppError: Error, Equatable {
    let message: String
    /// The HTTP status the server answered with, when the error came from one.
    var status: Int? = nil

    static let transport = AppError(message: "No connection — please try again.")
    static let unknown = AppError(message: "Something went wrong. Please try again.")

    static func forStatus(_ status: Int, serverMessage: String?) -> AppError {
        let message: String
        switch status {
        case 400: message = serverMessage ?? "That didn't look right."
        case 401: message = "Your session expired. Please sign in again."
        case 403: message = "You don't have permission to do that."
        case 404: message = "Not found."
        default:  message = serverMessage ?? AppError.unknown.message
        }
        return AppError(message: message, status: status)
    }

    /// The server answered 404 — what was asked for is gone, deleted elsewhere perhaps.
    var isNotFound: Bool { status == 404 }
}
