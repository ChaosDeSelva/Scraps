# Scraps

A small local macOS menu-bar app for snippets, notes, questions, reminders, and anything else worth keeping.

[Website](https://chaosdeselva.github.io/Scraps/) · [Source](https://github.com/ChaosDeSelva/Scraps)

Click the tray icon in the menu bar or press **Control–Option–Space** (the default shortcut) to capture something. Paste content, optionally add a title and comma-separated tags, and save with **Command–Return**. The library supports search across titles, content, sources, tags, and annotations. Each item keeps its original saved date; edits and annotations are dated separately.

Choose **Snippet**, **Note**, **Question**, **Reminder**, or **Other** when capturing or editing. Each type has its own library filter. Reminder items are a way to organize things to revisit; this version does not schedule notifications.

Choose **Light**, **Dark**, or **Follow macOS** from the appearance control at the bottom of the library sidebar, **View → Appearance**, or the menu-bar icon’s right-click menu. Your choice is saved and applies to quick capture and editing windows too. Follow macOS is the default.

Change the global capture shortcut in **Scraps → Settings…** (**Command–Comma**) or **Settings…** in the sidebar. Click the shortcut and press a combination containing Control, Option, or Command. Escape cancels recording; **Reset to default** restores Control–Option–Space. If a shortcut is already taken, Scraps keeps the previous working shortcut.

## Recording and transcription

Choose **Record** in the library, **File → Record audio…**, or the menu-bar icon’s right-click menu. Select Microphone, Mac audio, or both, then **Start recording**. macOS requests the necessary permissions. **Stop and save** creates a dated item with a local audio player, tags, and notes. The menu bar shows **REC** while recording, even if the recording window is closed.

Microphone recording works on macOS 14+. Mac audio and combined capture require macOS 15+. Scraps keeps audio samples only; it does not save screen images or video. Headphones help prevent echo when recording calls.

Open a recording and choose **Create transcript**. Apple’s on-device SpeechTranscriber requires macOS 26+, supported hardware, and a supported language. The first use may download a speech model from Apple. Audio stays on your Mac. Transcripts become editable, searchable item content; transcribing again preserves existing text and adds a dated note. Unfinished recordings can be recovered from the recording window. Trash retains the audio.

## Optional AI

Open **Settings → AI** and select a connection:

- **Codex · account:** install the official [Codex CLI](https://developers.openai.com/codex/cli), then use **Sign in…** or `codex login` to connect your ChatGPT subscription or another supported CLI account.
- **Claude Code · account:** install the official [Claude Code CLI](https://code.claude.com/docs/en/quickstart), then use **Sign in…** or `claude auth login`. The unmodified CLI handles its own authentication, subscription eligibility, and billing. Scraps does not implement Claude OAuth or extract subscription tokens.
- **OpenAI / Anthropic · API key:** save your own provider key in this Mac’s Keychain. API usage is billed separately by the provider. You can change the model or remove the key in Settings.

CLI connections require current versions supporting the isolation flags used by Scraps. Install CLIs in `~/.local/bin`, `/opt/homebrew/bin`, or `/usr/local/bin`. Scraps disables ordinary CLI tools, plugins, project instructions, hooks, and session history for these requests; organization-managed policies may still apply. Provider account terms and data policies apply. Scraps does not bundle or modify either CLI.

Choose **Ask AI → Summarize**, **Bullet points**, or **Chat about this item**. Review the prompt and **Preview what is sent**, optionally exclude attached notes, then press **Send**. Requests contain that item’s title and text, included notes, and the current chat. Raw audio, other library items, tags, and source fields are not sent. AI responses stay in the chat until you choose **Save as note**; closing the chat discards its conversation. Chats have a size limit and can be stopped. Failed requests never fall back to a different paid provider.

## Install

[Download Scraps 0.1.0 for Apple silicon](https://github.com/ChaosDeSelva/Scraps/releases/download/v0.1.0/Scraps-0.1.0-arm64.dmg). Requires macOS 14 or later. Open the signed and notarized disk image and drag Scraps into Applications.

**The 0.1.0 download is the original capture release. Appearance settings, custom shortcuts, recordings, transcription, and AI are currently available by building the latest source; a new signed release is handled separately.**

## Run

Building requires Apple’s Command Line Tools or Xcode with the macOS 26 SDK or later. The built app runs on macOS 14+, with newer recording and transcription features gated by availability. The native app has no third-party library dependencies. Optional account connections use separately installed official CLIs.

```sh
bash scripts/build.sh
open build/Scraps.app
```

For a local installation, copy `build/Scraps.app` to `~/Applications`. Closing the library leaves the menu-bar app running. Right-click its menu-bar icon to reopen the library or quit. Use File → Show local data folder to locate the library.

## Data

The library lives at `~/Library/Application Support/Scraps/Scraps.sqlite`. SQLite transactions protect each save; the database is readable only by the current user. Data is not encrypted by this version. Quit Scraps before copying the whole data folder as a backup, including any SQLite sidecar files and the `Recordings` folder. Audio is stored in owner-only files alongside the database. After saving the first recording, older builds refuse to open the library to prevent loss of attachment metadata. Trash is recoverable; this version has no permanent-delete action.

Capturing, storing, searching, and playing notes and recordings need no account. Scraps has no analytics, cloud synchronization, or Git-based data storage. Optional AI sends the selected context to your chosen provider only when you press Send. Direct API requests use HTTPS, refuse redirects, and disable OpenAI response storage; provider retention policies still apply. Official CLI connections use their own authentication and network behavior. Apple may download speech models when you request transcription. Clipboard access happens when you press Paste, use the normal paste command, or copy an item. Saved content stays in the Application Support folder, outside this source tree. Build output, local databases, environment files, and common credential-file formats are excluded from version control.

API keys belong in Settings → AI, where they are stored in Keychain. Note content and recordings are not encrypted by Scraps; do not treat the library as a credential vault. Apple Notes import is not included.

## Development

`Sources/App.swift` owns the menu bar, global shortcut, and native window lifecycle. SwiftUI views share the observable store. The store commits each change to SQLite before updating the visible library; failed or unreadable storage is surfaced without replacing user content.

```sh
bash scripts/test.sh
```

Tests cover Unicode and whitespace fidelity, annotations, search and filters, saved-date preservation, trash/restore, reopening the database, failed writes, unsupported or corrupt libraries, appearance persistence and contrast, shortcut validation and conflict recovery, selected-item AI context, subprocess cancellation, audio synchronization and playback, recording persistence, and transcript preservation. Audio tests require access to macOS media services. Optional `build/FeatureTests --live-cli` sends a synthetic note through installed accounts; `--speech-check` transcribes synthetic speech only when an English model is already installed. A QA app with bundle identifier `local.scraps.qa` uses a separate `Scraps-QA` data folder.

## Website and releases

The static website is in `docs/`, published with GitHub Pages from the `main` branch. It has no JavaScript, analytics, or third-party assets. Screenshots are rendered with sample content using `bash scripts/render-ui.sh`.

The build script produces a locally ad-hoc-signed app. Release signing with the hardened runtime must include `Resources/Scraps.entitlements` for microphone access and preserve the recording usage descriptions in `Resources/Info.plist`. Developer ID signing, notarization, and release downloads are handled separately; no signing identities, certificates, or credentials belong in this repository. The website links to the signed and notarized release as well as source and build instructions.

## License

[MIT](LICENSE).
