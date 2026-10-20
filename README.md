# Hearken

A native iPhone and iPad app for studying the scriptures: seven subjects with mastery meters,
games, a library, and a reader built for highlighting and notes. SwiftUI with Liquid Glass,
SwiftData for user data, and Sign in with Apple as the only login.

Where data lives:

- **The user's own iCloud** (CloudKit, private database): notes, highlights, bookmarks, plans,
  reading progress and XP. These never go to a Hearth server.
- **Hearth's server** (hearth-api at `api.hearthapps.com`, signed in through Hearth's Supabase
  project with the same Sign in with Apple): the **Hearth account** and **study groups**. A group
  member's display name and initials, their progress on the group's plan, and the highlights,
  reflections, replies, answers and questions they share to a group are stored there, along with
  reports and blocks. Settings › Delete Account deletes the Hearth account (`DELETE /v1/me`).
- **RevenueCat**: Hearken Plus / Hearth+ purchases and tips, linked to the Hearth account.

Requires Xcode 26 and iOS 26.

## First run

1. Open `Hearken.xcodeproj`.
2. Select the **Hearken** target › **Signing & Capabilities** and choose your **Team**.
3. If `com.stephenwarren.hearken` isn't available to your team, change the **Bundle Identifier**,
   then update the iCloud container in `Hearken.entitlements` and `AppConfig.cloudKitContainerID`
   to match (`iCloud.<your bundle id>`).
4. Run on an iPhone simulator or device. Sign in with Apple needs a simulator or device that is
   signed in to an Apple Account.

The entitlements already include Sign in with Apple, CloudKit and iCloud key-value storage.
Automatic signing registers them for your team the first time you build.

## Turning on iCloud sync

User data is saved on the device while `AppConfig.cloudSyncEnabled` is `false` (Models/Persistence.swift).
To sync through the user's iCloud:

1. In **Signing & Capabilities**, confirm the iCloud container is checked under **CloudKit**.
2. Add **Push Notifications** and **Background Modes › Remote notifications** (CloudKit uses silent pushes).
3. Set `AppConfig.cloudSyncEnabled = true` and run once on a device signed in to iCloud.
4. In the CloudKit Console, deploy the development schema to production before release.

The highlight color legend already syncs with iCloud key-value storage.

## What's built (milestone 1)

- **Sign in** — first-launch screen with Sign in with Apple only, a "Not now" guest path,
  and the no-affiliation disclaimer.
- **Tab bar** — Liquid Glass `TabView` with icon-only Today, Subjects, Play and Scriptures tabs
  plus the system search tab; minimizes on scroll.
- **Today** — daily challenge, level ring, streak, continue reading, subjects with mastery.
- **Subjects** — mastery ring and tier bar, Learn / Play / Library, units with readings and unit checks.
- **Games** — multiple-choice engine used by the Daily Challenge, Chronology Challenge, Unit Check
  and Spaced Review. Green checkmark for correct, red X for incorrect, haptics, results ring.
- **Reader** — New York text with adjustable size, tap a verse for the floating glass highlight
  toolbar (legend colors, Highlight / Underline, Note, Copy, Remove), inline notes, and a chapter-read
  toggle in both reader layouts. Unmarking preserves reading position and earned XP; each chapter
  awards reading XP only once.
- **Notes and Highlights** — everything marked, filterable by color.
- **Search** — scripture text and subjects.
- **Settings** — account, appearance, Highlight Colors legend, text size,
  daily goal, study reminder, legal links.
- **Mastery** — spaced repetition recall per question, unit and subject mastery, tiers, XP,
  levels and streaks, all computed from records (see Services/Mastery).
- **Tests** — Swift Testing for the mastery math and content integrity (⌘U).

## Other Hearth apps

Hearken shares with Steve's other apps on the same device (BigTable, Suffice, Sated, Caloma)
through the app group `group.com.stephenwarren.hearth`, added to `Hearken.entitlements` (main
app only). `Services/Hearth/HearthShared.swift` is synced from `~/Developer/hearthkit`; don't
edit it here. Hearken's side is `Services/Hearth/HearthLink.swift`.

- **One Sign in with Apple.** Apple's user ID is the same in every app from the team, and Apple
  only gives the name and email to the first app that asks, so the sign-in is kept in the shared
  Keychain (`HearthAccounts.appleID()`). When another app already signed in, the sign-in screen
  (and Settings, signed out) shows **Continue as <name>** instead of the Apple button; Apple is
  still asked that the sign-in is valid. A normal sign-in is shared with the others, and uses the
  shared name when Apple sends none. **Sign Out signs out of the other Hearth apps too**
  (`HearthAccounts.signOutEverywhere()`), and signing out everywhere in another app signs
  Hearken out; notes and progress stay either way.
- **Photos.** While signed in with a name, Hearken shares the reader as a one-person family
  (`me`) with their photo, on launch and whenever the name or photo changes, and takes it back
  on sign-out. Without a photo in Hearken, Settings shows another app's photo of them.

## Content

Content ships as JSON in `Hearken/Resources/Content`:

- `scripture.json` — volumes › books › chapters › verses. This build has sample chapters only
  (Psalm 23 and an excerpt of Alma 32).
- `subjects.json` — the seven subjects, units, library resources and questions.

IDs are permanent (`bofm.alma.32.27`, `q.bofm.0001`): user highlights, notes and reviews point
at them. Never renumber an ID once it ships. Next step is a build-time script that imports the
full standard works into a SQLite store with full-text search; `ContentService` is the only
type that needs to change.

## Project layout

```
Hearken/
  App/            App entry, root tab view, preview support
  DesignSystem/   Accent and appearance options, highlight hues, shared components
  Features/       Onboarding, Today, Subjects, Games, Reader, Search, Settings
  Models/         SwiftData models and the data store
  Resources/      Bundled content
  Services/       Content, Account (Sign in with Apple, Keychain), Mastery, Highlights, Reminders
HearkenTests/     Swift Testing
```

## Next up

- Full scripture import and SQLite search.
- Character-range highlights in the reader with TextKit 2.
- Turn on CloudKit sync, CloudKit zone deletion on account delete, and the Sign in with Apple
  token revocation endpoint.
- Game Center, widgets, App Intents, Spotlight, read-aloud and the Recite game (milestone 3).

Hearken is an independent study app. It is not made, sponsored or endorsed by The Church of
Jesus Christ of Latter-day Saints.

## Scripture content

The standard works come from [Atreyu4EVR/Standard-Works](https://github.com/Atreyu4EVR/Standard-Works) (public domain). To regenerate the bundled files:

```sh
git clone https://github.com/Atreyu4EVR/Standard-Works /tmp/Standard-Works
python3 scripts/import_standard_works.py /tmp/Standard-Works Hearken/Resources/Content
```

The source leaves out copyrighted material (chapter summaries, footnotes, the Official Declarations, introductions), so those arrive with the Church content license.
