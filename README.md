# Scraps

A small local macOS menu-bar app for snippets, notes, questions, reminders, and anything else worth keeping.

[Website](https://chaosdeselva.github.io/Scraps/) · [Source](https://github.com/ChaosDeSelva/Scraps)

Click the tray icon in the menu bar or press **Control–Option–Space** to capture something. Paste content, optionally add a title and comma-separated tags, and save with **Command–Return**. The library supports search across titles, content, sources, tags, and annotations. Each item keeps its original saved date; edits and annotations are dated separately.

Choose **Snippet**, **Note**, **Question**, **Reminder**, or **Other** when capturing or editing. Each type has its own library filter. Reminder items are a way to organize things to revisit; this version does not schedule notifications.

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

Tests cover Unicode and whitespace fidelity, annotations, search and filters, saved-date preservation, trash/restore, reopening the database, failed writes, and unsupported or corrupt libraries. A QA app with bundle identifier `local.scraps.qa` uses a separate `Scraps-QA` data folder.

## Website and releases

The static website is in `docs/`, published with GitHub Pages from the `main` branch. It has no JavaScript, analytics, or third-party assets. Screenshots are rendered with sample content using `bash scripts/render-ui.sh`.

The build script produces a locally ad-hoc-signed app. Developer ID signing, notarization, and release downloads are handled separately; no signing identities, certificates, or credentials belong in this repository. The website currently points to source and build instructions. When a signed release is available, its download link can be added to `docs/index.html`.

## License

[MIT](LICENSE).
