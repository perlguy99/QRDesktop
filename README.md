# QR Desktop

*Quick Reference Desktop* — a macOS menu bar app that turns your desktop background into a rotating quick-reference board. Composite cheat sheets, diagrams, resumes, or any reference image/PDF into "sheets," apply a different sheet to each monitor (and each virtual desktop), and pop the current sheet up over everything else with a single hotkey.

<p align="center"><i>Menu bar app — no Dock icon, no full window.</i></p>

## Features

- **Sheets, not single images.** A sheet holds 1, 2, or 3 side-by-side slots. Each slot has its own image/PDF, its own scale mode (`Fit` to see the whole thing, or `Fill` to crop and cover), and its own background color for letterboxing — so a full-page PDF resume and a cropped photo can share one sheet cleanly.
- **Per-screen, per-Space assignment.** Each physical monitor can show a different sheet, and — because the app tracks which macOS Space (virtual desktop) is currently active on each display — each Space can remember its own sheet too.
- **F6 peek overlay.** Tap F6 to float the sheet for whichever screen your mouse is currently on, on top of every other window (even fullscreen apps), without touching your actual desktop background. Release to hide it, or double-tap to latch it open until you tap again.
- **Launch at Login**, toggleable from the menu.
- **Named, thumbnailed image library** with Quick Look preview — no more guessing what `Screen Shot 2024-01-01.png` actually is.

## How it works

1. **Build a library.** Click the menu bar icon → **Add Images…** and pick any images or PDFs. Give them real names if you want (click the name field in the list). PDFs render their first page.
2. **Build a sheet.** Click **+1**, **+2**, or **+3** under **Sheets** to create a sheet with that many slots. Click **Edit** to expand it, then pick an image for each slot, a scale mode, and a background color.
3. **Apply it.** Pick a screen from the **Screen** picker (if you have more than one), then hit **Apply** on the sheet you want. It renders to a PNG and sets it as that screen's desktop picture. **Previous** / **Next** cycle through your saved sheets on the current screen.
4. **Peek at it anywhere.** Press **F6** (press-and-hold to show, release to hide; double-tap to latch it open, tap again to dismiss) to float the sheet for whichever screen your mouse is on over top of whatever you're doing.

Sheets are rendered per physical-screen resolution and cached in `~/Library/Application Support/QRDesktop/RenderedBoards/`.

## Requirements

- macOS 14.0+
- To build: [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) and Xcode

## Building from source

```sh
git clone https://github.com/perlguy99/QRDesktop.git
cd QRDesktop
xcodegen generate
open QRDesktop.xcodeproj
```

Build and run the `QRDesktop` scheme. Re-run `xcodegen generate` any time you add a new source file or change `project.yml` — the `.xcodeproj` is generated, not hand-maintained, and isn't checked in.

## Known limitations

- **Not sandboxed, not on the App Store.** Per-Space detection (below) relies on a private, undocumented WindowServer API that Apple's App Store review explicitly disallows. This is a build-it-yourself / personal-install app.
- **Per-Space detection uses a private API.** There is no public macOS API for "which Space is currently active on this display." QR Desktop calls `CGSCopyManagedDisplaySpaces` — the same private WindowServer API tools like `yabai` use — via raw symbol linking, since Apple doesn't publish a header for it. **A future macOS release could silently break or remove this without warning.** If it does, the app falls back to one sheet per screen (ignoring which Space you're on) rather than crashing.
- **Space IDs are not stable across a "Displays have separate Spaces" toggle.** Flipping System Settings → Desktop & Dock → Mission Control → *Displays have separate Spaces* (and restarting, which that setting requires) causes macOS to hand out entirely new Space IDs. Since sheet assignments are keyed by Space ID, every flip orphans your existing per-Space assignments — you'll need to re-apply a sheet per screen afterward. This isn't a bug, it's how the private API's IDs behave.
- **F6 is a bare, unmodified key.** It's a global hotkey with no built-in way to change it yet. If F6 is already bound to something else on your hardware/keyboard software, expect a conflict.
- **No delete confirmation** on sheets or images — deleting is immediate.
- Old rendered sheet PNGs aren't automatically cleaned up if your monitor setup or resolution changes often.

## License

No license file is currently included, which means default copyright applies (all rights reserved) even though the repo is public. Open an issue if you'd like to use this and want a license added.
