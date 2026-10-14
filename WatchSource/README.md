# Hearken for Apple Watch — setup

The iPhone side is already in the app (`Services/Watch/WatchBridge.swift`, `Services/Reminders/ReviewNotifications.swift`).
This folder holds the code for the two watch targets, which have to be created in Xcode.

Review questions (Settings › Review Questions) need none of this: they're iPhone notifications, and
their answer buttons appear on the watch automatically.

## 1. Watch app

1. File › New › Target… › watchOS › **App** › Next.
2. Product Name: **HearkenWatch**. Choose **Watch App for Existing iOS App**, companion app **Hearken**.
   Leave "Include Notification Scene" and tests unchecked. Finish (and Activate the scheme if asked).
3. Xcode makes a folder named **HearkenWatch Watch App**. Delete its `ContentView.swift` and
   `HearkenWatchApp.swift` (Move to Trash). Keep `Assets.xcassets`.
4. In Finder, move every `.swift` file from `WatchSource/HearkenWatch/` into **HearkenWatch Watch App/**.

## 2. Widget extension (Smart Stack and complications)

1. File › New › Target… › watchOS › **Widget Extension** › Next.
2. Product Name: **HearkenWatchWidgets**. Uncheck "Include Configuration App Intent".
   Embed in **HearkenWatch Watch App**. Finish.
3. In the new **HearkenWatchWidgets** folder, delete every `.swift` file Xcode made. Keep `Assets.xcassets` and `Info.plist`.
4. Move both `.swift` files from `WatchSource/HearkenWatchWidgets/` into it.

## 3. App Group

Signing & Capabilities › + Capability › App Groups, then tick **group.com.stephenwarren.hearken** on
both **HearkenWatch Watch App** and **HearkenWatchWidgets**. (The watch app saves the plan there; the widget reads it.)

## 4. Try it

Run the **HearkenWatch Watch App** scheme on a watch simulator paired with an iPhone simulator, with Hearken
running on the iPhone. Start a reading plan, then add the Today's Reading widget to the Smart Stack.

Then delete this `WatchSource` folder.

## Notes

- The app icon: drop the 1024 icon into the watch app's `Assets.xcassets › AppIcon`.
- `PlanSnapshot.swift` exists in three places (iPhone app, iPhone widget, both watch targets). Keep them in sync.
- Message keys in `WatchStore.swift` must match `WatchBridge.swift` in the iPhone app.
