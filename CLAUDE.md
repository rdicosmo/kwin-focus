# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`kwin-focus` lists and focuses application windows on **KDE Plasma 6** (X11 *and*
Wayland), fully **Activities-aware** — a replacement for `wmctrl`/`xdotool`
workflows that are broken on Plasma 6. There are two independent front-ends that
share one goal (enumerate every window across all virtual desktops and
Activities, then focus a chosen one) but solve the data-access problem in
completely different ways:

- **`cli/kwin-focus`** — a single self-contained bash script.
- **`applet/`** — a Plasma 6 panel/dock applet ("Window Filter", id
  `org.dicosmo.windowfilter`), written in QML.

## Commands

```sh
make install          # link ~/bin/kwin-focus onto PATH + install/upgrade the applet
make install-cli      # only the CLI symlink (~/bin/kwin-focus)
make install-applet   # only the applet (auto-detects install vs upgrade)
make upgrade          # re-deploy the applet after editing QML
make dev              # run the applet standalone via plasmawindowed (test loop)
make uninstall        # remove both
```

The applet is installed/upgraded with `kpackagetool6`. There is **no build step,
no test suite, and no linter** — both front-ends are interpreted (bash / QML).
The edit→test loop for the applet is: edit QML → `make upgrade` → re-test (the
running plasmashell picks up the upgraded package; `make dev` runs it in
isolation without touching your panel).

### Trying the CLI

```sh
cli/kwin-focus -l       # table of all normal windows
cli/kwin-focus -j       # same data as JSON (pipe to jq)
cli/kwin-focus -p RE    # focus first window matching case-insensitive regex (for keybinds)
cli/kwin-focus -d ...   # dump the raw KWin-script journal capture to stderr
```

## Architecture — the one thing to understand

The two front-ends differ because of **where they run relative to plasmashell**,
and this is the crux of the whole project:

### CLI: outside Plasma → KWin-scripting + journal exfiltration

KWin exposes **no** direct "list windows" D-Bus method. The CLI is an external
process, so it:

1. Writes a JavaScript snippet to a temp file and loads it via
   `org.kde.KWin /Scripting loadScript` (qdbus6).
2. The snippet calls `workspace.windowList()` and `print()`s one
   control-char-separated record per `normalWindow`, tagged with a unique run id,
   ending with a `<RUNID>_END` sentinel.
3. The script's `print()` output lands in the **systemd user journal** as
   `kwin_x11[pid]: js: <msg>`. The CLI reads it back with `journalctl --user`
   (using a wall-clock `--since` cursor), strips the `js: ` prefix, and greps for
   the run id.
4. Focusing: switch Activity first via `org.kde.ActivityManager …
   SetCurrentActivity` (done from bash, polling until it takes), then a second
   KWin script un-minimizes, sets `workspace.currentDesktop`, `raiseWindow()`,
   and sets `workspace.activeWindow`.

**Critical gotchas (documented inline, learned the hard way):**
- KWin is **not** a user systemd *unit*. Filtering with
  `journalctl --user -u plasma-kwin_x11.service` matches **nothing** — drop the
  `-u` filter. This is the single most common dead end.
- `workspace.activeWindow` is **write-deferred** by KWin — do not read it back in
  the same tick.
- Windows are tracked by KWin's stable `internalId`, **not** the printed index
  (indices change between runs). Focus operations re-resolve by `internalId`.
- Field separators are control chars (`US`=`\037`, `GS`=`\036`) that never appear
  in window titles; `clean()` in the JS strips them from captions.

### Applet: inside plasmashell → TaskManager model, no scripting

The applet runs *inside* plasmashell, so **none** of the scripting/journal dance
is needed. It binds `TaskManager.TasksModel` directly (ungrouped, all desktops &
activities), wraps it in a `KItemModels.KSortFilterProxyModel` for the
title/app/activity substring filter, and focuses via `requestActivate()` — which
switches virtual desktop **and** Activity for free.

**Critical gotchas (documented inline):**
- `TaskManager.VirtualDesktopInfo` and `TaskManager.ActivityInfo` objects must be
  instantiated and in scope even though they look unused — without them, changing
  `sortMode` dereferences a null `VirtualDesktopInfo` inside the sort comparator
  and **crashes** plasmashell (confirmed via core dump). This mirrors the stock
  Task Manager wiring.
- Activity id→name resolution uses `Activities.ActivityModel` fanned out through
  an `Instantiator`; each sync rebuilds `activityNames` as a **new object
  reference** so QML bindings re-evaluate.
- `hideOnWindowDeactivate` is a property of `PlasmoidItem` (the root), **not** the
  attached `Plasmoid` object — that is what the "pin" feature toggles.
- The global shortcut default (`Meta+W`) is seeded in `Component.onCompleted`
  **only when none is set**, so a user's own keybinding is never clobbered
  (Plasma persists `globalShortcut`).

## File map

```
cli/kwin-focus                      the entire CLI (bash)
applet/metadata.json                Plasma applet manifest (id org.dicosmo.windowfilter)
applet/contents/ui/main.qml         the applet UI + all logic
applet/contents/ui/ConfigGeneral.qml   settings page
applet/contents/config/main.xml     config keys: sortMode (lru|alpha|activity),
                                     keepOpenOnActivate (pin), showActivityColumn
applet/contents/config/config.qml   wires the settings category
```

The two front-ends share **no code** — keep a behavioural change in sync across
both by hand when it applies to both (e.g. sort order, activity display).

## Conventions

- Verified against **Plasma/KWin 6.3.6**. When changing the journal-parsing or
  KWin-scripting paths, note the version you verified on (existing comments do).
- License is **MIT**; keep SPDX headers on QML files.
