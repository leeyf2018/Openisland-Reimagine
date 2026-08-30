# Building Openisland-Reimagine

## Requirements

- macOS 14+ (recommended; project targets macOS 14)
- Xcode Command Line Tools (or full Xcode) with Swift 6.x toolchain
- Network on first build (SwiftPM resolves MarkdownUI + Sparkle)

Optional for the **O** (Copilot credits) chip after install:

- [`gh`](https://cli.github.com/) authenticated (`gh auth login`)

## Prefer prebuilt? (no compile)

If you only want to **run** the app:

1. Open [Releases](https://github.com/leeyf2018/Openisland-Reimagine/releases/latest)
2. Download `Open.Island.zip` (or the DMG when present)
3. Unzip, move `Open Island.app` to `/Applications`
4. First launch: right-click → **Open** (ad-hoc signed; not Apple notarized)

Continue below only if you need to **build or modify** the source.

## Clone / download ZIP

```bash
# Git
git clone https://github.com/leeyf2018/Openisland-Reimagine.git
cd Openisland-Reimagine

# Or: GitHub → Code → Download ZIP, then unzip and cd into the folder
# Source ZIP only (not the prebuilt .app):
# https://github.com/leeyf2018/Openisland-Reimagine/archive/refs/heads/main.zip
```

## Build (debug)

```bash
swift build
swift run OpenIslandApp
```

## Package a `.app` (release)

From the repo root:

```bash
export OPEN_ISLAND_PACKAGE_ROOT="$PWD/output/package"

./scripts/package-app.sh
```

Output:

- `$OPEN_ISLAND_PACKAGE_ROOT/Open Island.app`
- Zip if the script produces one (DMG step may require `create-dmg`; `.app` is enough to run)

Install:

```bash
# Quit any running Open Island first
pkill -x OpenIslandApp 2>/dev/null || true
rm -rf "/Applications/Open Island.app"
ditto "$OPEN_ISLAND_PACKAGE_ROOT/Open Island.app" "/Applications/Open Island.app"
xattr -cr "/Applications/Open Island.app"
open -a "Open Island"
```

> **Note:** Unsigned local builds may need **System Settings → Privacy & Security** approval on first launch, or right-click → Open.

## What is *not* in this repository

- `.build/` and `output/` (local build artifacts — gitignored)
- API keys, `gh` tokens, or personal agent configs
- Upstream update metadata. Reimagine version, build, bundle ID, feed and public key live in `config/release.env`.

## License

GPL-3.0 — see `LICENSE` and `NOTICE`.
