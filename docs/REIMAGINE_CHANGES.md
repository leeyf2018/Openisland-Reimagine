# Reimagine fork changes

This document lists **user-facing deltas** in `Openisland-Reimagine` relative to upstream [Open Island](https://github.com/Octane0411/open-vibe-island).

## Usage chips (notch header)

| Chip | Source | Primary number | Notes |
|------|--------|----------------|-------|
| **C** | Codex local usage (rollout / existing Open Island path) | Used **%** of window | Reset days as `(N)` under the number |
| **G** | Grok CLI billing log `~/.grok/logs/unified.jsonl` | Used **%** | Poll ~15s + log watch |
| **O** | GitHub Copilot via `gh api /copilot_internal/user` | **Credits used** (raw) | Business seats: do not trust `percent_remaining` alone when `unlimited=true`; color may still use plan-relative % |

Layout notes:

- Single-letter titles: C / G / O
- Vertical chip: letter → metric → `(resetDays)`
- No trailing `%` on the chip (hover / help still explains %)
- Notch-aware leading inset so the leading digit is not clipped by the island corner

## Build / package

Same packaging entry as upstream:

```bash
./scripts/package-app.sh
```

See [BUILDING.md](./BUILDING.md).

## Requirements for full C/G/O display

| Chip | Needs on the user machine |
|------|---------------------------|
| C | Codex usage data (as upstream) |
| G | Grok CLI writing billing lines to `~/.grok/logs/unified.jsonl` |
| O | [GitHub CLI](https://cli.github.com/) (`gh`) installed and `gh auth login` completed |

## Non-goals of this fork publish

- No bundled API keys, tokens, or personal config
- No prebuilt `.app` in the default source tree (optional Releases can be added later)
- Not a claim of sole authorship of Open Island — this is a GPL-3.0 **derivative**
