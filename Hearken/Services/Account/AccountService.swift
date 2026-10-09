import AuthenticationServices
import CloudKit
import Foundation
import Observation
import OSLog
import SwiftData

/// Sign in with Apple is the only way to sign in. The Apple user ID is kept in the
/// Keychain; the user's data itself lives in their own iCloud (see AppConfig).
@Observable
final class AccountService {
    enum Status: Equatable {
        case unknown, signedOut, signedIn
    }

    enum AccountError: LocalizedError {
        case unexpectedCredential
        case couldNotSave

        var errorDescription: String? {
            switch self {
            case .unexpectedCredential: "Sign in with Apple returned an unexpected credential."
            case .couldNotSave: "Your sign-in couldn't be saved on this device. Please try again."
            }
        }
    }

    private(set) var status: Status = .unknown
    private(set) var displayName: String? = nil
    /// nil until checked.
    private(set) var iCloudAvailable: Bool? = nil

    var isSignedIn: Bool { status == .signedIn }

    private let log = Logger(subsystem: "com.stephenwarren.hearken", category: "account")

    private enum Keys {
        static let userID = "appleUserID"
        static let displayName = "account.displayName"
    }

    init() {
        status = KeychainStore.read(Keys.userID) == nil ? .signedOut : .signedIn
        displayName = UserDefaults.standard.string(forKey: Keys.displayName)
    }

    /// Re-checks the Apple ID credential and iCloud status. Call on launch and when returning to the foreground.
    func refresh() async {
        guard let userID = KeychainStore.read(Keys.userID) else {
            log.info("refresh: no saved Apple user ID, signed out")
            status = .signedOut
            await refreshICloudStatus()
            return
        }

        #if targetEnvironment(simulator)
        // The Simulator can't answer credential-state checks reliably (it fails with
        // AKAuthenticationError -7084 or reports .notFound for valid sign-ins), so trust the saved ID.
        log.info("refresh: Simulator, keeping saved sign-in for \(userID.prefix(6), privacy: .public)…")
        status = .signedIn
        #else
        do {
            let state = try await ASAuthorizationAppleIDProvider().credentialState(forUserID: userID)
            log.info("refresh: credential state \(state.rawValue, privacy: .public)")
            switch state {
            case .authorized:
                status = .signedIn
            case .revoked, .notFound:
                // Revoked: the person stopped using Sign in with Apple for Hearken in their Apple Account settings.
                signOut()
            default:
                break
            }
        } catch {
            // Offline or the check failed: keep the saved sign-in.
            log.error("refresh: credential check failed, keeping sign-in: \(error.localizedDescription, privacy: .public)")
            status = .signedIn
        }
        #endif
        await refreshICloudStatus()
    }

    func refreshICloudStatus() async {
        // Ask CloudKit directly. (The old ubiquity-token check only reflects iCloud Drive,
        // which Hearken doesn't use, so it read "Off" even when iCloud was fine.)
        do {
            let accountStatus = try await CKContainer(identifier: AppConfig.cloudKitContainerID).accountStatus()
            log.info("iCloud account status \(accountStatus.rawValue, privacy: .public)")
            iCloudAvailable = accountStatus == .available
        } catch {
            log.error("iCloud account status failed: \(error.localizedDescription, privacy: .public)")
            iCloudAvailable = false
        }
    }

    /// Handles the result from SignInWithAppleButton.
    func completeSignIn(_ result: Result<ASAuthorization, any Error>) throws {
        let authorization = try result.get()
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            throw AccountError.unexpectedCredential
        }
        guard KeychainStore.save(credential.user, for: Keys.userID) else {
            log.error("completeSignIn: Keychain refused to save the Apple user ID")
            throw AccountError.couldNotSave
        }
        log.info("completeSignIn: saved Apple user ID")

        // Apple only sends the name on the first authorization, so save it right away.
        if let name = credential.fullName {
            let formatted = name.formatted()
            if !formatted.isEmpty {
                displayName = formatted
                UserDefaults.standard.set(formatted, forKey: Keys.displayName)
            }
        }
        status = .signedIn
    }

    /// Previews only: shows signed-in UI without a real Apple ID.
    func markSignedInForPreview() {
        status = .signedIn
    }

    func signOut() {
        log.info("signOut")
        KeychainStore.delete(Keys.userID)
        status = .signedOut
    }

    /// Deletes everything the app stores for this user and signs out.
    ///
    /// Still to do (see the plan's Open questions): revoke the Sign in with Apple token
    /// through the small revocation endpoint, and delete the user's CloudKit zone once sync is on.
    func deleteAccount(context: ModelContext) throws {
        try Persistence.eraseAll(in: context)
        UserDefaults.standard.removeObject(forKey: Keys.displayName)
        displayName = nil
        signOut()
    }
}
