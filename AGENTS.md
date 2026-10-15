# AGENTS.md

## What this is

Anear is a work-in-progress macOS 14+ menu-bar accessory that runs Dock-less
(no Dock icon) and draws ambient first-person lines as a small fading pill
near the cursor every 8–20 minutes of *active* time. It is an SPM package
with two targets: the `AnearCore` library (pure, AppKit-free logic) and the
`Anear` executable (the AppKit/SwiftUI app). For the human-facing product
detail — preview, config window, login item, the starter pack — read
`README.md`. This file is the operating manual for agents.

## Layout

- `Sources/AnearCore` — pure, AppKit-free, unit-tested
- `Sources/Anear` — AppKit/SwiftUI executable: menu, overlay, config window, presence
- `Tests/AnearCoreTests` — Swift Testing
- `build/Anear.app` — output of `./make-app.sh` (also the Start-at-Login target)

Do **not** put AppKit, SwiftUI, or Carbon in `AnearCore`. (`PresenceMonitor`
imports Carbon's `IsSecureEventInputEnabled` — that is why it lives in
`Sources/Anear`.)

## Commands

```sh
swift test
swift build
swift format lint --strict --recursive --configuration .swift-format Sources Tests Package.swift
./make-app.sh          # release .app at build/Anear.app
open build/Anear.app   # or ditto to /Applications
```

### `swift test` on this machine

This machine is Command Line Tools only (no Xcode). The CLT toolchain ships
no XCTest and SwiftPM cannot find Swift Testing on its own. **CI (Xcode) runs
plain `swift test`** — this is a local toolchain quirk, not a package
setting. Do not "fix" `Package.swift` to work around it. On this machine,
point the compiler at the CLT framework and add the two rpaths it needs:

```sh
swift test \
  -Xswiftc -F/Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib
```

## Git workflow

`master` is protected by the **Protect master** ruleset; direct push is
disabled. The facts:

- Pull requests are required
- **Squash merge only** — `allow_merge_commit` and `allow_rebase_merge` are off
- Required checks: `test` and `lint` (must be green before merge)
- Linear history; no force-push; branches are deleted on merge
- 0 required approving reviews — CI is the gate

### Every change

1. `git fetch origin && git checkout master && git pull` — or
   `git reset --hard origin/master` if local master has leftover slice commits.
2. Branch from that: `feat/…`, `fix/…`, `docs/…`, `refactor/…`, `ci/…`.
   One **feature** per branch, not one commit per branch (a one-commit
   feature is one commit).
3. Push the branch. Never push `master`.
4. `gh pr create --base master`. The PR title is the squash-commit subject:
   Conventional Commits, same style as existing history
   (`feat(overlay): …`, `feat(app): …`).
5. Wait for `test` and `lint`: `gh pr checks --watch`.
6. `gh pr merge --squash --delete-branch`.
7. Update local master: `git fetch origin && git checkout master && git reset --hard origin/master`.

### Stacked / sequential features

Do not open a second PR whose commits sit on the first PR's unsquashed SHAs:
the squash rewrite makes those parent commits vanish. Merge the first PR,
update local master, then branch the next feature from the new
`origin/master`, cherry-picking onto it if needed.

Do not `git push origin master`. Do not merge with `--no-ff`. Do not amend
other people's commits.

## Commits

Conventional Commits. Types used here: `feat`, `fix`, `docs`, `refactor`,
`test`, `chore`, `ci`, `build`. Scopes that already appear: `app`, `overlay`,
`config`, `scheduler`, `lines`. One slice = one commit on the feature branch
is fine; the PR squash is what lands on master.

## Invariants agents must not break

- **Config vs runtime state.** Lines, interval bounds, and `followCursor`
  live in `~/Library/Application Support/Anear/config.json` via `ConfigStore`.
  Pause and Start-at-Login stay in UserDefaults. The pause is persisted as an
  explicit state: running, indefinite, or an absolute wall-clock deadline.
  A relaunch mid-pause comes back paused, same deadline, same option ticked,
  and a deadline that passed while the app was closed reads as running. The
  legacy `anear.paused` bool must keep working: a stored `true` is an
  indefinite pause, and anything unreadable or half-written reads as
  **running**, never a stuck pause.
- **New JSON keys.** Existing files on disk must keep decoding. Add
  `decodeIfPresent` (or equivalent) with a safe default. A failed decode
  drops the user onto the starter pack — that is a regression. Add a
  handwritten-JSON test without the new key (see `ConfigStoreTests`).
- **Scheduler semantics.** Idle (`isPresent == false`) *freezes* the leftover
  wait — no backlog after a long absence. Pause *discards* it; resume rolls a
  fresh interval. A timed pause **expiring** is a resume too: the tick runs
  the same `apply` as Resume Now, so expiry rolls a fresh interval and a line
  never fires at the moment a pause lapses. Do not collapse these.
- **Overlay must not activate the app.** The pill is a non-activating,
  click-through panel. The Config window is the only place `NSApp.activate`
  runs.
- **Status item is a glyph.** Never put a title on the status button. Paused
  state is `appearsDisabled` + tooltip `Anear · paused`. The leftover wait is
  a *disabled menu item* — `Next in 5m 15s` while running, `Paused` while
  paused indefinitely, `Paused · 42m left` while timed — never the button
  title. Pause is a *submenu* whose parent reads `Pause` / `Paused`; it never
  toggles to `Resume`. The ticked duration and the `Resume Now` entry (shown
  only while a pause is in effect) carry that state instead.
- **Preview ignores the pause.** The Preview item and the Config window's
  preview always deal and show a line on demand, paused or not. That is
  deliberate — Preview is for checking your lines, not for the cadence.
- **AnearCore stays testable.** Placement (`OverlayGeometry`), timing,
  scheduler, config, shuffle bag, countdown format — pure functions/types
  with tests. AppKit types stay in `Sources/Anear` and are generally untested.
- **ConfigStore tests** use a unique temp file per test. Never the real
  Application Support path.
- **`swift run` is not an app bundle.** Do not consume the one-shot login-item
  flag from a bare executable. `make-app.sh` / `Anear.app` only.
- **Style.** `.swift-format`, 4-space indent, 100-col. Prefer the existing
  slightly-long "why" comments over silent cleverness. No drive-by refactors.

## Where to look

- Overlay show/hold/fade + cursor tracking: `Sources/Anear/OverlayController.swift`
- Placement math: `Sources/AnearCore/OverlayGeometry.swift`
- Scheduler: `Sources/AnearCore/SparseScheduler.swift`
- Pause state + persistence: `Sources/AnearCore/PauseState.swift`,
  `Sources/AnearCore/PauseStore.swift`
- Presence gate: `Sources/Anear/PresenceMonitor.swift`
- Config model + window: `Sources/Anear/ConfigWindow.swift`, `Sources/AnearCore/AnearConfig.swift`, `Sources/AnearCore/ConfigStore.swift`
- Menu, timer, wiring: `Sources/Anear/main.swift`
- Countdown string: `Sources/AnearCore/CountdownFormat.swift`
