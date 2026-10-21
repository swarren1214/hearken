import CloudKit
import Foundation
import os

/// The words people see when something fails: what didn't work and what to do next, never a
/// system error's own text (`localizedDescription`), an HTTP status or a server's internals. The
/// raw error always goes to the log.
///
///     catch {
///         errorMessage = FriendlyError.message(error, action: "erase your data")
///     }
///
/// Errors Hearken wrote for people (`ownMessage`) keep their own message.
nonisolated enum FriendlyError {
    private static let log = Logger(subsystem: "com.stephenwarren.hearken", category: "errors")

    /// A message for a failed `action` ("save your note", "delete your account").
    @MainActor
    static func message(_ error: Error, action: String) -> String {
        log.error("\(action, privacy: .public) failed: \(String(describing: error), privacy: .public)")
        if let own = error as? AccountService.AccountError, let message = own.errorDescription { return message }
        if let known = knownMessage(error) { return known }
        return "Hearken couldn’t \(action) right now. Try again in a moment."
    }

    /// Signing in with Apple (or continuing as someone another Hearth app signed in).
    @MainActor
    static func signIn(_ error: Error) -> String {
        log.error("sign-in failed: \(String(describing: error), privacy: .public)")
        if let own = error as? AccountService.AccountError, let message = own.errorDescription { return message }
        if let known = knownMessage(error) { return known }
        return "Couldn’t sign in. Try again in a moment."
    }

    /// Why a file couldn't be imported, as the end of "“Book.epub” couldn’t be imported. …".
    static func importReason(_ error: Error) -> String {
        log.error("import failed: \(String(describing: error), privacy: .public)")
        if let message = ownMessage(error) { return message }
        if let error = error as? CocoaError {
            switch error.code {
            case .fileReadNoPermission: return "Hearken wasn’t allowed to open it. Try sharing it to Hearken again."
            case .fileReadNoSuchFile: return "The file isn’t there anymore."
            case .fileReadCorruptFile: return "The file is damaged."
            case .fileWriteOutOfSpace: return "Your iPhone is out of space. Free some up and try again."
            default: break
            }
        }
        return "Hearken couldn’t read it. Make sure it’s an EPUB or PDF without copy protection."
    }

    /// The natural voice couldn't download (or be saved once it did).
    static func voiceDownload(_ error: Error) -> String {
        log.error("voice download failed: \(String(describing: error), privacy: .public)")
        if isOffline(error) { return "You’re offline. Connect to the internet and try again." }
        if let error = error as? CocoaError, error.code == .fileWriteOutOfSpace {
            return "There isn’t enough room on your iPhone. Free up some space and try again."
        }
        return "The natural voice couldn’t download. Try again in a moment."
    }

    /// The natural voice couldn't speak (the standard voice takes over).
    static func voicePlayback(_ error: Error) -> String {
        log.error("natural voice failed: \(String(describing: error), privacy: .public)")
        return "Hearken switched to the standard voice for now."
    }

    /// The cases every action shares: offline, iCloud, the Hearth account and service.
    static func knownMessage(_ error: Error) -> String? {
        if let message = ownMessage(error) { return message }
        if isOffline(error) { return "You’re offline. Try again when you’re back online." }
        if let error = error as? CKError {
            switch error.code {
            case .quotaExceeded: return "Your iCloud storage is full. Free up space in Settings › your name › iCloud, then try again."
            case .notAuthenticated: return "Sign in to iCloud in Settings to keep your notes and progress on all your devices."
            case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy:
                return "iCloud isn’t reachable right now. Try again in a moment."
            default: break
            }
        }
        if let error = error as? HearthAPI.APIError {
            if error.status == 401 { return "Your sign-in has expired. Sign in with Apple again." }
            if error.status == 429 { return "Too many requests just now. Try again in a minute." }
            // The API's own messages are written for people; outages aren't.
            if error.status >= 500 || error.message.isEmpty { return "Hearth is having trouble right now. Try again in a moment." }
            return error.message
        }
        if let error = error as? HearthAPI.ClientError {
            switch error {
            case .notConnected: return "Sign in with Apple to use study groups."
            case .rateLimited: return "Too many requests just now. Try again in a minute."
            case .missingAppleToken, .missingAppleNonce: return "The sign-in didn’t finish. Try again."
            case .invalidResponse, .service, .rejected: return "Hearth is having trouble right now. Try again in a moment."
            }
        }
        if error is DecodingError { return "Hearth sent something Hearken didn’t understand. Make sure Hearken is up to date." }
        return nil
    }

    /// Errors whose message Hearken wrote for people, shown as they are.
    private static func ownMessage(_ error: Error) -> String? {
        if let own = error as? EPUBParser.ParseError { return own.errorDescription }
        if let own = error as? ZipArchive.ZipError { return own.errorDescription }
        if let own = error as? PDFTextExtractor.ExtractError { return own.errorDescription }
        return nil
    }

    static func isOffline(_ error: Error) -> Bool {
        guard let error = error as? URLError else { return false }
        return [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .cannotConnectToHost,
                .dnsLookupFailed, .dataNotAllowed, .internationalRoamingOff].contains(error.code)
    }
}

