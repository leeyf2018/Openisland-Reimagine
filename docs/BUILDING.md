# Building Openisland-Reimagine

## Requirements

- macOS 14+ (recommended; project targets macOS 14)
- Xcode Command Line Tools (or full Xcode) with Swift 6.x toolchain
- Network on first build (SwiftPM resolves MarkdownUI + Sparkle)

Optional for the **O** (Copilot credits) chip after install:

- [`gh`](https://cli.github.com/) authenticated (`gh auth login`)

## Clone / download ZIP

```bash
# Git
git clone https://github.com/leeyf2018/Openisland-Reimagine.git
cd Openisland-Reimagine

# Or: GitHub → Code → Download ZIP, then unzip and cd into the folder
```

## Build (debug)

```bash
swift build
swift run OpenIslandApp
```

## Package a `.app` (release)

From the repo root:

```bash
export OPEN_ISLAND_VERSION="1.1.6-reimagine"
export OPEN_ISLAND_BUILD_NUMBER="$(date +%Y%m%d%H)"
export OPEN_ISLAND_BUNDLE_ID="app.openisland.reimagine"   # optional; default is app.openisland.dev
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
- Upstream appcast / auto-update pointing at someone else’s releases (treat Sparkle as optional)

## License

GPL-3.0 — see `LICENSE` and `NOTICE`.
