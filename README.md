# Scraps

A small local macOS menu-bar app for snippets, notes, questions, reminders, and anything else worth keeping.

[Website](https://chaosdeselva.github.io/Scraps/) · [Source](https://github.com/ChaosDeSelva/Scraps)

Click the tray icon in the menu bar or press **Control–Option–Space** (the default shortcut) to capture something. Paste content, optionally add a title and comma-separated tags, and save with **Command–Return**. The library supports search across titles, content, sources, tags, and annotations. Each item keeps its original saved date; edits and annotations are dated separately.

Choose **Snippet**, **Note**, **Question**, **Reminder**, or **Other** when capturing or editing. Each type has its own library filter. Reminder items are a way to organize things to revisit; this version does not schedule notifications.

Choose **Light**, **Dark**, or **Follow macOS** from the appearance control at the bottom of the library sidebar, **View → Appearance**, or the menu-bar icon’s right-click menu. Your choice is saved and applies to quick capture and editing windows too. Follow macOS is the default.

Change the global capture shortcut in **Scraps → Settings…** (**Command–Comma**) or **Keyboard shortcut…** in the sidebar. Click the shortcut and press a combination containing Control, Option, or Command. Escape cancels recording; **Reset to default** restores Control–Option–Space. If a shortcut is already taken, Scraps keeps the previous working shortcut.

## Install

[Download Scraps 0.1.0 for Apple silicon](https://github.com/ChaosDeSelva/Scraps/releases/download/v0.1.0/Scraps-0.1.0-arm64.dmg). Requires macOS 14 or later. Open the signed and notarized disk image and drag Scraps into Applications.

## Run

Requires macOS 14 or later and Apple's Command Line Tools. There are no third-party dependencies or network services.

```sh
bash scripts/build.sh
open build/Scraps.app
```

For a local installation, copy `build/Scraps.app` to `~/Applications`. Closing the library leaves the menu-bar app running. Right-click its menu-bar icon to reopen the library or quit. Use File → Show local data folder to locate the library.

## Data

The library lives at `~/Library/Application Support/Scraps/Scraps.sqlite`. SQLite transactions protect each save; the database is readable only by the current user. Data is not encrypted by this version. Quit Scraps before copying the whole data folder as a backup, including any SQLite sidecar files. Trash is recoverable; this version has no permanent-delete action.

The app makes no network requests and uses no account, telemetry, cloud synchronization, or Git-based data storage. Clipboard access happens when you press Paste, use the normal paste command, or copy an item. Saved content stays in the Application Support folder, outside this source tree. Build output, local databases, environment files, and common credential-file formats are excluded from version control.

Dedicated encrypted secret storage, recordings, transcription, and Apple Notes import are not included in this version. Do not treat the current database as a credential vault.

## Development

`Sources/App.swift` owns the menu bar, global shortcut, and native window lifecycle. SwiftUI views share the observable store. The store commits each change to SQLite before updating the visible library; failed or unreadable storage is surfaced without replacing user content.

```sh
bash scripts/test.sh
```

Tests cover Unicode and whitespace fidelity, annotations, search and filters, saved-date preservation, trash/restore, reopening the database, failed writes, unsupported or corrupt libraries, appearance persistence and contrast, and shortcut validation and conflict recovery. A QA app with bundle identifier `local.scraps.qa` uses a separate `Scraps-QA` data folder.

## Website and releases

The static website is in `docs/`, published with GitHub Pages from the `main` branch. It has no JavaScript, analytics, or third-party assets. Screenshots are rendered with sample content using `bash scripts/render-ui.sh`.

The build script produces a locally ad-hoc-signed app. Developer ID signing, notarization, and release downloads are handled separately; no signing identities, certificates, or credentials belong in this repository. The website links to the signed and notarized release as well as source and build instructions.

## License

[MIT](LICENSE).
