---
name: ops-kde-pitfalls
description: Use when a KDE/Plasma desktop integration does not behave — a Dolphin right-click service menu that never appears, a .desktop file that is silently ignored, a KDE config change that does not take effect — or before writing or editing anything under kio/servicemenus. Covers the Plasma 6 traps where the failure mode is total silence: no error, no log line, no warning. Includes a probe that asks KIO what it would render, so a context menu can be tested without right-clicking.
---

# KDE / Plasma Pitfalls

Every trap here shares one property: **KDE fails silently.** No error, no stderr, nothing in
journalctl. The entry simply is not there. So the first move is never "read the logs" — it is to
get a programmatic answer out of KIO. Start with the probe below.

All findings verified against Plasma 6.7.3 / KF6 6.29.0.

## `X-KDE-Submenu` deletes your service menu entry

The single most expensive trap. A service menu that sets `X-KDE-Submenu` **does not appear at all**
— not in a submenu, not at top level, nowhere.

KIO honours the key by filing the action into a submenu list that `KFileItemActions` then never
renders. The entry is parsed, matched against the mimetype, and dropped on the floor.

```ini
# WRONG — this entry is invisible, with no diagnostic anywhere
Actions=myAction;
X-KDE-Submenu=My Tools

# RIGHT — actions render flat in the context menu
Actions=myAction;
```

`X-KDE-Show-In-Submenu` is the key KIO 6.29 actually reads, but it applies to *plugin* actions
rather than service menus. Setting it stops the suppression yet still renders flat, so it buys
nothing. **There is no working way to group service-menu actions under a heading on Plasma 6.7.**

The consequence is a design constraint, not just a bug: if you cannot nest entries, you cannot
afford broad mimetypes. An action matching `inode/directory` lands in *every* folder's context
menu. Scope the `MimeType` list tightly and expose the broad case through the CLI instead.

## Things that are NOT the problem (stop checking them)

Each of these looks like the obvious culprit and is not. KIO's own source
(`src/widgets/kfileitemactions.cpp`) settles it:

| Suspicion | Reality |
| --- | --- |
| `Type=Service` vs `Type=Application` | **Not checked at all** for files in `kio/servicemenus`. Both behave identically. |
| `NoDisplay=true` hides it | **Not consulted.** `KService::noDisplay()` appears in KIOWidgets but not on this path. |
| Needs `kbuildsycoca6` | Service menus are read live from disk. **None** of them are in sycoca — verify with `grep -ac konsolerun ~/.cache/ksycoca6*` → 0. |
| Missing `kservicemenurc` entry | The `[Show]` group defaults to `true` when an entry is absent, so a missing file shows everything. |
| Not executable | No executable requirement during discovery. |
| Wrong mimetype spelling | Matching uses `inherits()`, so subclasses and aliases work. Check with `xdg-mime query filetype`. |

`NoDisplay` is unnecessary for a different reason worth knowing: the application launcher only
scans `applications/` directories, never `kio/servicemenus`, so a service menu was never at risk
of showing up there.

## `desktop-file-validate` false-positives on `Type=Service`

It reports `required key "Name" ... is not present` and `key "MimeType"/"Actions" ... only valid
for type "Application"`. These are not real errors — `Type=Service` is a KDE extension the
freedesktop validator does not know.

Confirm before chasing one: KDE's own shipped file fails identically.

```bash
desktop-file-validate /usr/share/kio/servicemenus/filelight.desktop   # same three "errors"
```

## Qt strings are UTF-16 — plain `strings` finds nothing

`QStringLiteral` stores UTF-16, so an ASCII `strings`/`grep -a` over a Qt or KF6 binary misses every
literal. This makes it look like the code you are hunting for does not exist.

```bash
strings /usr/lib/libKF6KIOWidgets.so.6 | grep servicemenus     # no hits — misleading
strings -e l /usr/lib/libKF6KIOWidgets.so.6 | grep servicemenus # kio/servicemenus, kservicemenurc
```

Use `strings -e l` (16-bit little-endian) on anything Qt-based. It is often the fastest way to learn
which config keys and paths a KDE component actually reads.

## Probe: ask KIO what it would render

Do not debug a context menu by right-clicking and guessing. Build this once and bisect a `.desktop`
file in seconds. It prints the exact action list Dolphin would show for a given path.

`probe.cpp`:

```cpp
#include <QApplication>
#include <QMenu>
#include <QAction>
#include <QUrl>
#include <cstdio>
#include <functional>
#include <KFileItem>
#include <KFileItemListProperties>
#include <KFileItemActions>

int main(int argc, char **argv) {
    QApplication app(argc, argv);
    if (argc < 2) { fprintf(stderr, "usage: probe <file>\n"); return 2; }
    KFileItem item(QUrl::fromLocalFile(QString::fromLocal8Bit(argv[1])));
    item.determineMimeType();
    printf("mimetype: %s\n", item.mimetype().toUtf8().constData());
    KFileItemList l; l << item;
    KFileItemActions acts;
    acts.setItemListProperties(KFileItemListProperties(l));
    QMenu menu;
    acts.addActionsTo(&menu);
    std::function<void(QMenu *, QString)> dump = [&](QMenu *m, QString ind) {
        for (QAction *a : m->actions()) {
            if (a->isSeparator()) continue;
            printf("%s\n", (ind + "- " + a->text()).toUtf8().constData());
            if (a->menu()) dump(a->menu(), ind + "    ");
        }
    };
    dump(&menu, QString());
    return 0;
}
```

Build and run it **outside any nix shell** — nix's `ld` cannot link the distro Qt/KF6 libraries and
produces a wall of bogus undefined references:

```bash
cat > build.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
INC=()
while IFS= read -r d; do INC+=("-I$d"); done < <(find /usr/include/KF6 -maxdepth 1 -type d)
INC+=(-I/usr/include/qt6 -I/usr/include/qt6/QtCore -I/usr/include/qt6/QtGui
      -I/usr/include/qt6/QtWidgets -I/usr/lib/qt6/mkspecs/linux-g++)
/usr/bin/g++ -std=c++20 -fPIC probe.cpp -o probe "${INC[@]}" \
  -lQt6Core -lQt6Gui -lQt6Widgets -lKF6KIOWidgets -lKF6KIOCore -lKF6Service
EOF
env -i HOME="$HOME" PATH=/usr/local/bin:/usr/bin:/bin bash build.sh

env -i HOME="$HOME" PATH=/usr/bin:/bin XDG_DATA_HOME="$HOME/.local/share" \
  XDG_DATA_DIRS=/usr/local/share:/usr/share QT_QPA_PLATFORM=offscreen \
  ./probe /path/to/some/file.exe
```

Three build details that each cost a round trip:

- **All** of `/usr/include/KF6/*` must be on the include path (`kio_version.h` lives in `KF6/KIO`,
  not `KF6/KIOCore`), plus `/usr/lib/qt6/mkspecs/linux-g++` for `qplatformdefs.h`.
- `QT_QPA_PLATFORM=offscreen` — otherwise it needs a display.
- Print with `printf`, not `qInfo()`. Qt filters `qInfo` by default and the probe appears to run
  silently and succeed.

To bisect, write candidate `.desktop` bodies to the deployed path in a loop and grep the probe's
output for your action name. Restore the original when done.

## Where service menus live

`~/.local/share/kio/servicemenus/` (per `XDG_DATA_HOME`) and `$XDG_DATA_DIRS/kio/servicemenus/`.
The three KDE ships — `filelight`, `konsolerun`, `installfont` — are the reference examples for
what actually works.

In this repo they are chezmoi-managed templates under
`chezmoi/dot_local/share/kio/servicemenus/`, deployed by `chezmoi apply`. See
[ops-chezmoi](../ops-chezmoi/SKILL.md) for the deployment mechanics.
