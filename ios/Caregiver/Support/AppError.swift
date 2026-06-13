import Foundation

/// A user-facing error with a friendly message.
struct AppError: Error, Equatable {
    let message: String

    static let transport = AppError(message: "No connection — please try again.")
    static let unknown = AppError(message: "Something went wrong. Please try again.")

    static func forStatus(_ status: Int, serverMessage: String?) -> AppError {
        switch status {
        case 400: return AppError(message: serverMessage ?? "That didn't look right.")
        case 401: return AppError(message: "Your session expired. Please sign in again.")
        case 403: return AppError(message: "You don't have permission to do that.")
        case 404: return AppError(message: "Not found.")
        default:  return serverMessage.map { AppError(message: $0) } ?? .unknown
        }
    }
}
