# Anear

Ambient first-person lines that appear near your cursor on macOS — like flavor
text from a first-person game, but for your desktop. **Work in progress.**

Anear is a menu-bar accessory: it runs Dock-less (no icon in the Dock), sits in
the menu bar, and eventually draws short lines in a small overlay next to the
cursor.

## Requirements

- macOS 14+

## Develop

```sh
swift test     # run the unit tests (overlay placement + timing)
swift build    # build everything
```

> **Command Line Tools only (no Xcode):** a local quirk of this setup — the
> CLT-only toolchain doesn't ship XCTest, and SwiftPM can't find Swift Testing
> on its own. It is not a package setting: CI (Xcode) runs plain `swift test`.
> If you hit it, point the compiler at the CLT framework and add the two rpaths
> the CLT framework needs at runtime:
>
> ```sh
> swift test \
>   -Xswiftc -F/Library/Developer/CommandLineTools/Library/Developer/Frameworks \
>   -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
>   -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib
> ```

## Run

```sh
swift run Anear
```

or build a proper .app bundle (menu-bar item, `LSUIElement`, ad-hoc signed):

```sh
./make-app.sh
open build/Anear.app
```

Either way you get a menu-bar item titled **Anear** with **Preview** and
**Quit** — no Dock icon. **Preview** shows a fading pill of text
("I begin again.") pinned near the cursor: it holds for ~4s, fades out over
~1.25s, never takes focus, and lets clicks pass through to whatever is under
it.

## Status

- [x] SPM package: `AnearCore` library + `Anear` executable
- [x] Cursor-overlay placement math (flips + clamping), unit tested
- [x] Overlay panel + fade (Preview menu item)
- [ ] Line store + shuffle bag
- [ ] Presence-gated scheduler + Pause
- [ ] Edit Lines window + login item

## License

MIT
