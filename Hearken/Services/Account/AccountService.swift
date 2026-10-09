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
    /// From Sign in with Apple; may be a private relay address. Apple only shares it on the
    /// first sign-in, so people who signed in before this was asked for won't have one.
    private(set) var email: String? = nil
    /// The person's chosen profile photo (small JPEG), synced through their iCloud key-value store.
    private(set) var avatarData: Data? = nil
    /// nil until checked.
    private(set) var iCloudAvailable: Bool? = nil

    var isSignedIn: Bool { status == .signedIn }

    private let log = Logger(subsystem: "com.stephenwarren.hearken", category: "account")

    private enum Keys {
        static let userID = "appleUserID"
        static let displayName = "account.displayName"
        static let email = "account.email"
        static let avatar = "account.avatar"
    }

    @ObservationIgnored private var avatarObserver: NSObjectProtocol?

    init() {
        status = KeychainStore.read(Keys.userID) == nil ? .signedOut : .signedIn
        displayName = UserDefaults.standard.string(forKey: Keys.displayName)
        email = UserDefaults.standard.string(forKey: Keys.email)
        avatarData = NSUbiquitousKeyValueStore.default.data(forKey: Keys.avatar)
            ?? UserDefaults.standard.data(forKey: Keys.avatar)
        // A photo chosen on another device arrives through iCloud.
        avatarObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let data = NSUbiquitousKeyValueStore.default.data(forKey: Keys.avatar)
                self.avatarData = data
                UserDefaults.standard.set(data, forKey: Keys.avatar)
            }
        }
    }

    /// Initials for the monogram avatar, e.g. "SW".
    var initials: String? {
        guard let displayName, let components = PersonNameComponentsFormatter().personNameComponents(from: displayName) else { return nil }
        let formatter = PersonNameComponentsFormatter()
        formatter.style = .abbreviated
        let value = formatter.string(from: components)
        return value.isEmpty ? nil : value
    }

    /// Saves (or with nil, removes) the profile photo on this device and in iCloud.
    func setAvatar(_ data: Data?) {
        avatarData = data
        UserDefaults.standard.set(data, forKey: Keys.avatar)
        if let data {
            NSUbiquitousKeyValueStore.default.set(data, forKey: Keys.avatar)
        } else {
            NSUbiquitousKeyValueStore.default.removeObject(forKey: Keys.avatar)
        }
        NSUbiquitousKeyValueStore.default.synchronize()
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

        // Apple only sends the name and email on the first authorization, so save them right away.
        if let address = credential.email, !address.isEmpty {
            email = address
            UserDefaults.standard.set(address, forKey: Keys.email)
        }
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
        UserDefaults.standard.removeObject(forKey: Keys.email)
        displayName = nil
        email = nil
        setAvatar(nil)
        signOut()
    }
}
