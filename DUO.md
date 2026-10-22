# Hearken on iPhone Duo

This is an overnight pass, done without a compiler. Nothing is committed. Review it with `git diff`,
then build. Everything builds on `Services/Hearth/HearthDuo.swift` (the HearthKit copy, unchanged).

## What changed

- `App/HearkenApp.swift`: `.hearthDuoPose()` on the scene root, outside the tab view.
- `Features/Games/GameView.swift`: the game now sits in a `NavigationStack` with its bar hidden.
  - On the outer display the bar shows, with the streak as its one item on the rail.
  - Answers use a 2×2 even grid on the outer display and in Laptop. They stay one column at accessibility text sizes.
  - In Laptop, `HearthFoldOverlay` puts the question and explanation on the upright half. 84 pt answers and Continue go on the flat half.
  - The game's state was already in `GameView`, above the pose, so a picked answer carries across poses.
  - `AnswerButton` takes a `minHeight` (58 by default).
- `Features/Reader/ReaderView.swift`:
  - `ReaderView` now owns `explainRequest`, so Explain survives a pose change.
  - It keeps a `layoutPose`. That follows the pose, but only after it notes the verse on screen, so the new layout opens at the same verse (`adoptPose`).
  - Open wide: `HearthFoldSplit(axes: .horizontal)` puts chapters on the left and text on the right. Highlight and Explain are on the rail. The text column is capped at 720 pt.
  - Book: `HearthFoldSplit` puts the text on the left page and the notebook on the right. The nav bar and tab bar are hidden. Bookmarks open as a sheet here, because the toolbar popover isn't on screen.
  - The Listen menu and Reader Options were moved into `listenMenu`, `optionsMenu` and `optionsItems`, with the same behavior. Reader Options also gains "Verse Board".
  - `ReaderPage` takes new parameters: `explainRequest` (a binding), `duoPose`, `markedVerse`, `command` and `onSelectionChange`.
  - A verse marked from the notebook gets the same soft wash that Listen uses.
- `Features/Reader/ExplainView.swift`: `ExplainSheet` has an `inline` mode for the Book page, with its own Close/title/Copy row and no NavigationStack. The sheet mode is unchanged.
- `Features/Reader/ReaderDuo.swift` (new):
  - `ReaderCommand`: rail actions for the selection.
  - `ReaderChapterPane`: an even 4-column chapter grid that reuses `ChapterTile`.
  - `ReaderNotebookPane`: the right page in Book. It shows this chapter's notes and highlights, tied to verses, and inline Explain. Edit Note opens the existing `NoteEditorView`.
- `Features/Reader/VerseGlanceBoard.swift` (new): the Tent board, built on `HearthGlanceBoard`.
  - The eye switches between the full text and first letters.
  - Listen speaks the verse with `ListenVoices.best()`. It's gated on Hearken Plus, like Listen.
  - Spaced Review opens the free review game.
- `Features/Today/TodayView.swift` and `Features/Games/PlayView.swift`: the streak toolbar item is now a `Label` (title and flame), so it can show on the rail. It looks the same.
- `Features/Groups/GroupViews.swift`: the group icon picker and the members grid now use even column counts (`HearthEvenColumns`, measured with `onGeometryChange`) instead of `.adaptive`.

## How each pose behaves

- **Closed (outer display):** Start the Daily Challenge from Today or Play. Answers show in a 2×2 grid, the streak is on the rail, and Close stays at top left in the game's header. In the reader, the rail also gets a Verse Board button.
- **Open tall:** The reader is as it was: standard bars, Reading Options at top right, and marks drawn the same as in every pose.
- **Open wide:** The book's chapters are on the left in four columns. The text is on the right with a comfortable line length. Highlight (uses the selected text's existing color, or the first legend color) and Explain sit on the rail, and they're enabled while text is selected. Explain is on-device and free.
- **Book:** Text is on the left page with no bars. The right page has Back, location, Listen, Bookmarks and Reader Options at the top, then this chapter's notes and highlights. Tap one to mark and scroll to its verse. Explain opens on the right page.
- **Laptop:** The question is on the upright half, with 84 pt answers in a 2×2 grid on the flat half. The answer you picked stays picked if you close the device.
- **Tent:** Reader › Verse Board (on the rail on the outer display, or in Reader Options anywhere). It shows the selected verse, or the one at the top of the page.

## Testing in the iPhone Duo simulator

1. Run on the iPhone Duo simulator (iOS 27.1). Use the device posture controls to switch between Closed, Open, Book and Laptop.
2. **Closed:** Today › Daily Challenge. Check for the 2×2 answers and the streak on the rail.
3. **Laptop:** During a challenge, set the posture to Laptop. Pick an answer, then switch to Closed: it's still answered.
4. **Open tall:** Open a chapter. Highlight, add a note, and check that Reading Options is at top right.
5. **Open wide:** Rotate to landscape. Check the chapter grid on the left. Select text, then try Highlight and Explain on the rail.
6. **Book:** Fold to Book. Check that the left page has no bars. Tap a note on the right page, and its verse should wash and scroll into view. Select text, tap Explain in the highlight bar, and it should open on the right page. Unfold: you should be at the same verse.
7. **Tent:** On the outer display, tap Verse Board on the rail. Try the eye, Listen and Spaced Review.
8. Check that iPhone 17 and iPad look unchanged (the pose is `.standard` there and below iOS 27.1).

## Skipped, and why

- **Inline notes under their verse (Open tall).** Notes still open in the note sheet from the icon at the end of the verse. Drawing a note inside the UITextView flow is a big change to `ChapterText.swift`.
- **"The verse you're memorizing."** Hearken has no memorization list. The board uses the selected verse, or the top verse, instead. A "Memorize" flag on a verse would be a new synced model.
- **Spaced Review tie-in.** It opens the regular due-question review. There are no verse-recall questions yet.
- **List → detail splits (Library → book, Notebook → entry, Groups).** These were left as push navigation. Restructuring them needs a design decision and testing. The reader's Open wide split covers the main chapters/text case.
- **The game's custom header (Close + progress) and the pinned Continue/Done buttons.** These are a deliberate full-screen game layout, so I kept them.
- **`UIDevice.isPad`** (Theme.swift, and its uses in the reader and tips) is only for Apple Pencil features, not for layout, so I kept it.
- **The plan calendar's 7-column grid** stays 7 columns, one per weekday. Chapter grids were already 6 columns.
- **Fixed sizes** (badge art, Explain's 112 pt term column, `maxWidth` caps) are component sizes, not phone-width assumptions, so I left them.

## Please confirm

1. **Open wide Highlight** applies the selected text's existing color, or the first legend color. The full color bar still appears at the bottom too. Should Highlight on the rail open the color bar instead?
2. **Book hides the tab bar** along with the nav bar ("no bars at all"). Is that OK?
3. **The Verse Board is also in Reader Options** on every device, not only on the outer display. Keep it there?
4. **Verse Board Listen** is gated on Hearken Plus, like Listen. The design note only says Spaced Review stays free.
5. **The streak on the game rail** is a plain Label (not a button). If the rail drops non-button items, it may need to become a button. What should tapping it do?

## Review (overnight)

A second pass, also without a compiler. I read every changed and new file, grepped each new symbol, and ran `swiftparse.py` on all of them (0 errors).

### What I checked
- Every symbol the new code uses exists with that name, labels and access: `ChapterTile`, `LibraryProgress`, `LibraryCatalog.location(ofChapter:)`, `book.unit.count`, `NoteEditorView`, `HighlightLegend.name(for:)`, `Font.scripture(size:weight:)`, `MasteryService.dueQuestions`, `MasterySnapshot`, `ListenVoices.best()`, `HearthPurchases.shared.isUnlocked`, `hearthPaywall`, `CheckMenuItem.button`, `ExplainEngine.shared.isOffered`, `MasteryMath.streak`, `onGeometryChange`, and the HearthDuo API.
- The uncertain spots the author listed:
  - `ReaderCommand(kind:)` works. The memberwise init skips `let id = UUID()`, and synthesized Equatable is fine for `onChange`.
  - Each `item:` ternary has the same type on both sides (`Binding<X?>`).
  - `toolbarVisibility(_, for: .tabBar)` on a pushed view is already used in NotebookView.
  - `ForEach(1...n, id: \.self)` already has its id.
  - `SheetCancelButton` + `.glass` matches SheetButtons.swift ("an X in a clear glass circle"), and its own `.tint(.primary)` stays. That's fine outside a toolbar.
- `ReaderPage(` has one call site, and it passes every new parameter.
- Explain still runs only on `FoundationModels` (on-device), with no paywall.
- No banned API, `UIScreen` or idiom check in the new code.

### What I fixed
- `ReaderView.swift:154`: on first appear, `adoptPose` no longer replaces the verse the reader was opened at. Before, a reader opened at a bookmark or note while already in Open wide or Book opened at the top verse instead.
- `ReaderView.swift:156`: a verse marked from the notebook is cleared when the chapter changes, so verse N of the next chapter isn't washed.
- `ReaderView.swift:387`: Book's right-page header gains Original Pages (imported PDFs). It was lost with the hidden toolbar.
- `ReaderDuo.swift:26`, `VerseGlanceBoard.swift:31`: explicit inits. A `@Query` or a `private let` with a default can make the memberwise init private or fragile.
- `ReaderDuo.swift:66,196`: pull to refresh on the chapter pane and the notebook page (AGENT.md iCloud rule).
- `VerseGlanceBoard.swift:140-165`: `VerseSpeaker` now uses ListenEngine's pattern. It hops to the main actor with the utterance's `ObjectIdentifier` (weak self), and ignores a late callback from a replaced utterance. That stops Stop/Listen from flickering.
- `TodayView.swift:86`, `PlayView.swift:79`, `VerseGlanceBoard.swift:70`: `.hearthDuoPose()` on `GameView` inside its full-screen cover. A cover takes the presenter out of the window, so the root probe may stop measuring. The cover now reads the pose itself.

### Remaining risks
- `GameView.swift:84`: the streak is a plain `Label` in a `ToolbarItem`, not a button. The HIG says non-button items may not go on the rail. The same goes for the Today/Play streak items.
- `ExplainView.swift:91`: `.buttonStyle(.glass)` from outside `SheetCancelButton`. It should apply to the inner Button. If not, the X is a plain icon (cosmetic only).
- In Open wide and Book, moving between poses rebuilds the page, so an open selection, Pencil palette or highlight toolbar closes. Place, Explain and marks are kept.
- `GroupViews.swift`: the grids start at 2 columns for one frame, until the width is measured.

### Open questions for Steve
- Should the game's streak become a button, so it reliably shows on the rail? If yes, what does tapping it do?
- Confirm the author's five questions above (Highlight color on the rail, the hidden tab bar in Book, Verse Board in Reader Options, Plus gating for board Listen, the streak item).
