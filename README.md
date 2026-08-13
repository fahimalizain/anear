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
swift test     # run the unit tests (overlay placement math)
swift build    # build everything
```

> **Command Line Tools only (no Xcode):** the SwiftPM test runner can't discover
> Swift Testing on its own without Xcode — run
> `swift test -Xswiftc -F/Library/Developer/CommandLineTools/Library/Developer/Frameworks`
> so the tests actually execute.

## Run

```sh
swift run Anear
```

or build a proper .app bundle (menu-bar item, `LSUIElement`, ad-hoc signed):

```sh
./make-app.sh
open build/Anear.app
```

Either way you get a menu-bar item titled **Anear** with a **Quit** menu — no
Dock icon.

## Status

- [x] SPM package: `AnearCore` library + `Anear` executable
- [x] Cursor-overlay placement math (flips + clamping), unit tested
- [ ] Overlay panel + fade
- [ ] Line store + shuffle bag
- [ ] Presence-gated scheduler + Pause
- [ ] Edit Lines window + login item

## License

MIT
