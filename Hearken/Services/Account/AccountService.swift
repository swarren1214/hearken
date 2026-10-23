import AuthenticationServices
import CloudKit
import Foundation
import Observation
import OSLog
import SwiftData

/// Sign in with Apple is the only way to sign in. The Apple user ID is kept in the
/// Keychain. The user's study data (notes, highlights, plans, progress) lives in their own
/// iCloud (see AppConfig); study groups and the Hearth account they need live on Hearth's
/// server (`HearthAPI`, api.hearthapps.com).
///
/// The sign-in is shared with the other Hearth apps on this device (`HearthAccounts.appleID()`;
/// Apple's user ID is the same in every app from the same team): Hearken can continue as the
/// person another app signed in, a new sign-in here is shared with them, and Sign Out here signs
/// out of all of them, as signing out everywhere in another app signs out of Hearken.
@Observable
final class AccountService {
    enum Status: Equatable {
        case unknown, signedOut, signedIn
    }

    enum AccountError: LocalizedError {
        case unexpectedCredential
        case couldNotSave
        case sharedSignInExpired
        /// The server refused to delete the account: the person still manages a BigTable
        /// household with other people in it.
        case householdHasMembers
        /// Deleting the Hearth account failed; nothing was deleted.
        case deleteFailed(String)

        var errorDescription: String? {
            switch self {
            case .unexpectedCredential: "The sign-in didn’t finish. Try Sign in with Apple again."
            case .couldNotSave: "Your sign-in couldn't be saved on this device. Please try again."
            case .sharedSignInExpired: "That sign-in is no longer valid. Please sign in with Apple instead."
            case .householdHasMembers: "Remove the other people from your household in BigTable first."
            case .deleteFailed(let message): message
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
        /// Hearken's sign-in is the one shared with the other Hearth apps, so when it disappears
        /// from there, another app signed out everywhere.
        static let sharedSignIn = "account.hearthSharedSignIn"
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
                HearthLink.shared.update()
            }
        }
        // Screenshot mode: the demo reader, signed in.
        if ScreenshotMode.isOn {
            status = .signedIn
            displayName = ScreenshotMode.demoName
            email = nil
            avatarData = nil
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
        HearthLink.shared.update()
    }

    /// Re-checks the Apple ID credential and iCloud status. Call on launch and when returning to the foreground.
    func refresh() async {
        if ScreenshotMode.isOn {
            status = .signedIn
            iCloudAvailable = true
            return
        }
        HearthLink.shared.start(account: self)
        // Off the main thread: at launch this used to block the main thread on securityd.
        guard let userID = await KeychainStore.readOffMain(Keys.userID) else {
            log.info("refresh: no saved Apple user ID, signed out")
            status = .signedOut
            HearthLink.shared.update()
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
        await followSharedSignIn(userID: userID)
        HearthLink.shared.update()
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
        var gotName = false
        if let name = credential.fullName {
            let formatted = name.formatted()
            if !formatted.isEmpty {
                displayName = formatted
                UserDefaults.standard.set(formatted, forKey: Keys.displayName)
                gotName = true
            }
        }
        // Apple only sends those to the first app that asks; another Hearth app may have them.
        if let shared = HearthAccounts.appleID(), shared.userID == credential.user {
            if !gotName, let name = shared.fullName, !name.isEmpty {
                displayName = name
                UserDefaults.standard.set(name, forKey: Keys.displayName)
            }
            if email == nil, let address = shared.email, !address.isEmpty {
                email = address
                UserDefaults.standard.set(address, forKey: Keys.email)
            }
        }
        status = .signedIn
        shareSignIn(userID: credential.user)
        HearthLink.shared.update()
    }

    // MARK: One sign-in for the Hearth apps

    /// The sign-in another Hearth app shared, to offer as "Continue as <name>": only with a
    /// name, and only when Apple says it's still good.
    func sharedSignInToOffer() async -> HearthSharedAppleID? {
        guard !ScreenshotMode.isOn, !isSignedIn,
              let shared = HearthAccounts.appleID(),
              let name = shared.fullName, !name.isEmpty else { return nil }
        return await isAuthorized(shared.userID) ? shared : nil
    }

    /// Signs in as the person another Hearth app signed in with Apple, without asking Apple
    /// for the sign-in again (Apple is still asked whether it's valid).
    func continueWithSharedSignIn(_ shared: HearthSharedAppleID) async throws {
        guard await isAuthorized(shared.userID) else {
            throw AccountError.sharedSignInExpired
        }
        guard KeychainStore.save(shared.userID, for: Keys.userID) else {
            log.error("continueWithSharedSignIn: Keychain refused to save the Apple user ID")
            throw AccountError.couldNotSave
        }
        log.info("continueWithSharedSignIn: signed in with the shared Apple user ID")
        if let name = shared.fullName, !name.isEmpty {
            displayName = name
            UserDefaults.standard.set(name, forKey: Keys.displayName)
        }
        if let address = shared.email, !address.isEmpty {
            email = address
            UserDefaults.standard.set(address, forKey: Keys.email)
        }
        UserDefaults.standard.set(true, forKey: Keys.sharedSignIn)
        status = .signedIn
        HearthLink.shared.update()
    }

    /// Re-reads the other Hearth apps' shared sign-in, after one of them changed it
    /// (HearthLink calls this when another app writes to the shared store).
    func followSharedSignIn() async {
        guard let userID = await KeychainStore.readOffMain(Keys.userID) else { return }
        await followSharedSignIn(userID: userID)
    }

    /// Keeps Hearken's sign-in and the shared one together: shares a sign-in made before the
    /// apps shared one, picks up a name only another app got from Apple, and signs out here
    /// when another Hearth app signed out everywhere. Runs from `refresh()`, on launch and on
    /// returning to the foreground.
    ///
    /// `userID` is the one `refresh()` just read. The shared sign-in is read off the main thread
    /// (it's in the shared Keychain too).
    private func followSharedSignIn(userID: String) async {
        guard !ScreenshotMode.isOn, isSignedIn else { return }
        let (shared, gone) = await Task.detached(priority: .userInitiated) { (HearthAccounts.appleID(), HearthAccounts.appleIDIsGone) }.value
        // Signed out while that was being read: nothing to follow.
        guard isSignedIn else { return }
        // There but unreadable just now (or written by a newer app): not a sign-out.
        if shared == nil, !gone { return }
        let wasShared = UserDefaults.standard.bool(forKey: Keys.sharedSignIn)
        switch shared {
        case let shared? where shared.userID == userID:
            if !wasShared { UserDefaults.standard.set(true, forKey: Keys.sharedSignIn) }
            if displayName == nil, let name = shared.fullName, !name.isEmpty {
                displayName = name
                UserDefaults.standard.set(name, forKey: Keys.displayName)
                HearthLink.shared.update()
            }
        case nil where wasShared:
            log.info("followSharedSignIn: another Hearth app signed out everywhere")
            signOut()
        case nil:
            // Signed in before the apps shared a sign-in.
            shareSignIn(userID: userID)
        case let shared?:
            // Another Hearth app signed in as someone else: follow it, so every Hearth app shows
            // the same person (one sign-in for the Hearth apps).
            log.info("followSharedSignIn: another Hearth app switched accounts")
            guard KeychainStore.save(shared.userID, for: Keys.userID) else { return }
            displayName = shared.fullName.flatMap { $0.isEmpty ? nil : $0 }
            email = shared.email.flatMap { $0.isEmpty ? nil : $0 }
            for (key, value) in [(Keys.displayName, displayName), (Keys.email, email)] {
                if let value { UserDefaults.standard.set(value, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
            }
            UserDefaults.standard.set(true, forKey: Keys.sharedSignIn)
            HearthLink.shared.update()
            Task { @MainActor in await HearthConnection.shared.update() }
        }
    }

    /// Shares this sign-in with the other Hearth apps. Only remembered as shared once it's
    /// really there (it isn't when the app group is missing from the entitlements).
    private func shareSignIn(userID: String) {
        HearthAccounts.saveAppleID(HearthSharedAppleID(userID: userID, fullName: displayName, email: email, updatedBy: .hearken))
        if HearthAccounts.appleID()?.userID == userID {
            UserDefaults.standard.set(true, forKey: Keys.sharedSignIn)
        }
    }

    private func isAuthorized(_ userID: String) async -> Bool {
        #if targetEnvironment(simulator)
        // As in `refresh()`: the Simulator can't answer credential-state checks reliably.
        return true
        #else
        do {
            return try await ASAuthorizationAppleIDProvider().credentialState(forUserID: userID) == .authorized
        } catch {
            log.error("isAuthorized: credential check failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
        #endif
    }

    /// Previews only: shows signed-in UI without a real Apple ID.
    func markSignedInForPreview() {
        status = .signedIn
    }

    /// Signs out of Hearken only: Apple revoked the sign-in, or another Hearth app signed out
    /// everywhere. Notes and progress stay.
    func signOut() {
        log.info("signOut")
        KeychainStore.delete(Keys.userID)
        UserDefaults.standard.removeObject(forKey: Keys.sharedSignIn)
        status = .signedOut
        HearthLink.shared.update()
        // Study groups belong to the Hearth account: forget them on this device too.
        Task { @MainActor in
            await GroupStore.shared.disablePushToken()
            await HearthConnection.shared.signOut()
            GroupStore.shared.forget()
        }
    }

    /// Sign Out in Settings: signs out of Hearken and of the other Hearth apps on this device
    /// (BigTable, Suffice, Sated, Caloma), which share one sign-in. Notes and progress stay.
    func signOutEverywhere() {
        signOut()
        HearthAccounts.signOutEverywhere()
    }

    /// Settings › Delete Account (signed in) or Delete All Data (signed out).
    ///
    /// Signed in: first deletes the Hearth account on the server (`DELETE /v1/me`), which removes
    /// it for every Hearth app, along with what this person wrote in study groups (groups they own
    /// pass to another member). If that fails nothing is deleted and the error is thrown. Then
    /// erases Hearken's data here and in iCloud, and signs out of every Hearth app on this device.
    ///
    /// Signed out: erases Hearken's data here and in iCloud only; nothing is sent anywhere.
    func deleteAccount(context: ModelContext) async throws {
        let deletingAccount = isSignedIn && !ScreenshotMode.isOn
        if deletingAccount {
            do {
                _ = try await HearthAPI.shared.data("DELETE", "/v1/me")
                log.info("deleteAccount: Hearth account deleted")
                // The session belongs to the deleted account: forget it before anything else
                // (such as turning off the push token) tries to use it.
                await HearthAPI.shared.signOut()
            } catch HearthAPI.ClientError.notConnected {
                // No Hearth session on this device (signed in with Apple before study groups, or
                // never connected): there's no server account this device can reach.
                log.notice("deleteAccount: no Hearth session, deleting local data only")
            } catch {
                log.error("deleteAccount: server deletion failed: \(String(describing: error), privacy: .public)")
                throw Self.deletionError(error)
            }
        }
        var eraseError: (any Error)?
        do {
            try Persistence.eraseAll(in: context)
        } catch {
            eraseError = error
        }
        UserDefaults.standard.removeObject(forKey: Keys.displayName)
        UserDefaults.standard.removeObject(forKey: Keys.email)
        displayName = nil
        email = nil
        setAvatar(nil)
        if deletingAccount {
            GroupStore.shared.forget()
            signOutEverywhere()
        } else if isSignedIn {
            signOut()
        }
        if let eraseError { throw eraseError }
    }

    /// A readable message for a failed account deletion.
    private static func deletionError(_ error: any Error) -> AccountError {
        if let error = error as? HearthAPI.APIError {
            if error.code == "HOUSEHOLD_HAS_MEMBERS" { return .householdHasMembers }
            return .deleteFailed(error.status >= 500
                                 ? "Hearth is having trouble right now, so your account wasn't deleted. Try again in a moment."
                                 : error.message)
        }
        if GroupOutbox.isOffline(error) {
            return .deleteFailed("You're offline, so your account wasn't deleted. Try again when you're back online.")
        }
        if error is HearthAPI.ClientError, let message = FriendlyError.knownMessage(error) {
            return .deleteFailed("Your account wasn’t deleted. \(message)")
        }
        return .deleteFailed("Your account couldn't be deleted right now. Try again in a moment.")
    }
}
