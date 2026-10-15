import Foundation
import Observation
import UIKit

/// Hearken's side of sharing with the other Hearth apps on this device (see `HearthShared.swift`):
/// - The signed-in reader, as a one-person family with their photo, so BigTable, Caloma and the
///   others can show that photo for someone with the same name.
/// - Another app's photo of the reader, for when they haven't chosen one in Hearken.
/// - One Sign in with Apple across the apps: `AccountService` keeps Hearken's sign-in and the
///   shared one (`HearthAccounts.appleID()`) together.
@MainActor
@Observable
final class HearthLink {
    static let shared = HearthLink()

    /// Another Hearth app's photo of the reader, shown where Hearken has none of its own.
    private(set) var sharedAvatar: Data?

    /// The reader's id in Hearken's family. Hearken only ever has the one person.
    static let memberID = "me"

    @ObservationIgnored private weak var account: AccountService?
    @ObservationIgnored private var changeObserver: NSObjectProtocol?
    /// The photo last shared, to announce a new photo even when the family file is unchanged.
    @ObservationIgnored private var lastSharedPhoto: Data?

    /// Follows the other apps' changes while Hearken is open. Safe to call more than once.
    func start(account: AccountService) {
        self.account = account
        guard changeObserver == nil, !ScreenshotMode.isOn else { return }
        Hearth.startObservingChanges()
        changeObserver = NotificationCenter.default.addObserver(forName: Hearth.didChange, object: nil, queue: .main) { _ in
            Task { @MainActor in HearthLink.shared.otherAppChanged() }
        }
    }

    /// Another Hearth app (or Hearken itself) wrote something: a sign-out everywhere, or a new
    /// photo of the reader.
    private func otherAppChanged() {
        account?.followSharedSignIn()
        reloadSharedAvatar()
    }

    /// Shares the reader and their photo while signed in with a name, and takes them back
    /// otherwise. Call when the sign-in, name or photo changes, and on launch.
    func update() {
        guard !ScreenshotMode.isOn, let account else { return }
        let name = account.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if account.isSignedIn, !name.isEmpty {
            let jpeg = account.avatarData.flatMap { Self.sharedJPEG(from: $0) }
            let photo = jpeg.flatMap { Hearth.savePhoto($0, memberID: Self.memberID, from: .hearken) }
            let me = HearthFamily.Member(id: Self.memberID, name: name, photo: photo)
            let published = Hearth.publish(HearthFamily(name: nil, members: [me], dietaryRestrictions: nil, me: Self.memberID), from: .hearken)
            // A new photo keeps the same file name, so the family file alone wouldn't announce it.
            if !published, photo != nil, jpeg != lastSharedPhoto { Hearth.postChange() }
            lastSharedPhoto = photo == nil ? nil : jpeg
            Hearth.removePhotos(from: .hearken, except: Set([photo].compactMap { $0 }))
        } else {
            Hearth.remove(HearthFamily.self, from: .hearken)
            Hearth.removePhotos(from: .hearken, except: [])
            lastSharedPhoto = nil
        }
        reloadSharedAvatar()
    }

    /// Looks for another app's photo of the reader, by name, only when Hearken has none.
    private func reloadSharedAvatar() {
        var found: Data?
        if !ScreenshotMode.isOn, let account, account.isSignedIn, account.avatarData == nil,
           let name = account.displayName, !name.isEmpty {
            found = Hearth.sharedPhoto(forName: name, excluding: .hearken)
        }
        if found != sharedAvatar { sharedAvatar = found }
    }

    /// The photo as a JPEG of at most 512 px. Hearken's avatars are already 256 px, so this
    /// normally passes them straight through.
    private static func sharedJPEG(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let width = image.size.width * image.scale
        let height = image.size.height * image.scale
        let longest = max(width, height, 1)
        if longest <= 512 { return data }
        let scale = 512 / longest
        let target = CGSize(width: (width * scale).rounded(), height: (height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: 0.8)
    }
}
