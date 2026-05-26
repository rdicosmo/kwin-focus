# kwin-focus

List and focus application windows on **KDE Plasma 6** (X11 *and* Wayland),
fully **Activities-aware**. A replacement for `wmctrl` / `xdotool` workflows,
which are broken on Plasma 6 (no Wayland support, no Activities).

Two front-ends share one idea — *talk to KWin, enumerate every window across all
virtual desktops and Activities, and focus the one you want*:

| | |
|---|---|
| **`cli/kwin-focus`** | a self-contained bash tool: list (`-l`), JSON (`-j`), pattern-focus (`-p RE`, ideal for global keybindings), and an interactive picker (fzf or a numbered menu). |
| **`applet/`** ("Window Filter") | a Plasma 6 panel/dock applet: a search box over a live window list, filter by title/application, navigate with the arrow keys, Enter to focus. |

## How it works (the interesting part)

KWin exposes **no** direct "list windows" D-Bus method, and the two front-ends
solve the data problem very differently:

- **The CLI** is *outside* Plasma, so it injects a JavaScript snippet via
  `org.kde.KWin /Scripting loadScript`, and reads the script's `print()` output
  back from the **systemd user journal** (`journalctl --user`, where it lands as
  `kwin_x11[…]: js: …`). A common dead end is filtering with
  `journalctl --user -u plasma-kwin_x11.service` — kwin is *not* a user systemd
  unit, so that matches nothing; drop the `-u` filter. Focusing sets
  `workspace.activeWindow` (write-deferred — don't read it back in the same
  tick) after `raiseWindow()`, switches the virtual desktop, and switches the
  Activity via `org.kde.ActivityManager … SetCurrentActivity`.
- **The applet** runs *inside* plasmashell, so it needs none of that: it uses
  `TaskManager.TasksModel` directly and `requestActivate()`, which switches
  desktop **and** Activity for free.

## Install

```sh
make install          # links ~/bin/kwin-focus onto PATH + installs the applet
make dev              # run the applet standalone (plasmawindowed) to try it
make upgrade          # redeploy the applet after edits
make uninstall        # remove both
```

Then add the applet to a panel/dock: right-click the panel → **Add Widgets…** →
search **"Window Filter"**.

## Requirements

- **CLI:** `qdbus6` (or `qdbus`), `journalctl`, `awk`, `sed`. Optional: `fzf`.
- **Applet:** KDE Plasma 6 (`kpackagetool6` to install). Uses the stock
  `org.kde.taskmanager` and `org.kde.kitemmodels` QML modules.

## Layout

```
cli/kwin-focus              the command-line tool
applet/metadata.json        Plasma applet manifest (id: org.dicosmo.windowfilter)
applet/contents/ui/main.qml the applet UI
```

## License

MIT. See [LICENSE](LICENSE).
