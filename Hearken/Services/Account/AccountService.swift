import AuthenticationServices
import CloudKit
import Foundation
import Observation
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
        var errorDescription: String? { "Sign in with Apple returned an unexpected credential." }
    }

    private(set) var status: Status = .unknown
    private(set) var displayName: String? = nil
    /// nil until checked.
    private(set) var iCloudAvailable: Bool? = nil

    var isSignedIn: Bool { status == .signedIn }

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
        if let userID = KeychainStore.read(Keys.userID) {
            do {
                let state = try await ASAuthorizationAppleIDProvider().credentialState(forUserID: userID)
                switch state {
                case .authorized:
                    status = .signedIn
                case .revoked, .notFound:
                    signOut()
                default:
                    break
                }
            } catch {
                // Offline or the check failed: keep the cached state.
            }
        } else {
            status = .signedOut
        }
        await refreshICloudStatus()
    }

    func refreshICloudStatus() async {
        guard AppConfig.cloudSyncEnabled else {
            iCloudAvailable = FileManager.default.ubiquityIdentityToken != nil
            return
        }
        do {
            let accountStatus = try await CKContainer(identifier: AppConfig.cloudKitContainerID).accountStatus()
            iCloudAvailable = accountStatus == .available
        } catch {
            iCloudAvailable = false
        }
    }

    /// Handles the result from SignInWithAppleButton.
    func completeSignIn(_ result: Result<ASAuthorization, any Error>) throws {
        let authorization = try result.get()
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            throw AccountError.unexpectedCredential
        }
        KeychainStore.save(credential.user, for: Keys.userID)

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
