# Reimagine fork changes

This document lists **user-facing deltas** in `Openisland-Reimagine` relative to upstream [Open Island](https://github.com/Octane0411/open-vibe-island).

## Usage chips (notch header)

| Chip | Source | Primary number | Notes |
|------|--------|----------------|-------|
| **C** | Codex local usage (rollout / existing Open Island path) | Used **%** of window | Reset days as `(N)` under the number |
| **G** | Grok CLI billing log `~/.grok/logs/unified.jsonl` | Used **%** | Poll ~15s + log watch; overall SuperGrok pool |
| **GB** | Live `cli-chat-proxy.grok.com/v1/billing?format=credits` → `productUsage.GrokChat` | Used **%** | Grok Bot / grok.com Chat slice; same weekly window as G; cache `~/Library/Application Support/OpenIsland/grokbot-chat-usage.json` |
| **W** | WorkBuddy accessibility UI | **Points remaining** (whole number) | No reset-day row; startup/click refresh plus a 10-minute background poll |

Layout notes:

- Titles: C / G / GB / W
- **O** (GitHub Copilot credits) is removed from the island header. The OpenCode loader remains in source for rollback.
- Vertical chip: letter → metric → `(resetDays)`
- No trailing `%` on the chip (hover / help still explains %)
- Notch-aware leading inset so the leading digit is not clipped by the island corner

## Build / package

Same packaging entry as upstream:

```bash
./scripts/package-app.sh
```

See [BUILDING.md](./BUILDING.md).

## Requirements for full C/G/GB/W display

| Chip | Needs on the user machine |
|------|---------------------------|
| C | Codex usage data (as upstream) |
| G | Grok CLI writing billing lines to `~/.grok/logs/unified.jsonl` |
| GB | `grok login` so `~/.grok/auth.json` has a non-expired SuperGrok token (same account as grok.com Chat / Grok Bot) |
| W | WorkBuddy running and Open Island granted macOS Accessibility access |

## Releases (prebuilt)

Prebuilt macOS app zips are published under GitHub **Releases** (not inside the source tree):

- Asset pattern: `OpenIsland-Reimagine-<version>.app.zip`
- Signing: stable Reimagine self-signed identity; Apple Developer ID remains an optional paid upgrade
- Source of truth for code remains the `main` branch (GPL-3.0)

### Single Latest package policy (hard)

**Reimagine** policy **2026-08-04**: this repo keeps **only one** GitHub Release with a prebuilt install zip — always the current good build (Latest).

| Do | Don't |
|----|--------|
| Publish/replace **one** Latest prebuilt after a verified fix | Leave multiple installable zips as “which one do I download?” |
| Delete previous prebuilt Release(s) after the new Latest is published | Keep known-buggy install packages as Latest or as tempting parallel downloads |
| Point docs at `releases/latest` only | Re-ask each time whether to keep old packages |

Source history remains in `main` git; only the **downloadable .app.zip surface** is single-slot.

### GB chip replaces O (1.1.6-reimagine.34)

| Chip | Change |
|------|--------|
| **O** | Removed from the island header (GitHub Copilot credits). Loader kept in source. |
| **GB** | New chip immediately right of **G**. Live SuperGrok `productUsage.GrokChat` (Grok Bot / grok.com Chat). Same weekly used% + remaining-days layout as G. |

### Usage loader fixes (1.1.6-grok1.21 / 1.1.6-grok1.22)

| Chip | Issue | Fix |
|------|--------|-----|
| **C** | Stale Codex % from `~/.codex/sessions` only | Also scan `archived_sessions`; pick newest rate_limits **event** time |
| **G** | After weekly reset, last log line can keep high % until CLI re-fetches | Period rollover → 0% used; multi `unified.jsonl*` candidates |
| **G** | Mid-period usage reset omits `creditUsagePercent`; island stayed at 100% | Missing/null percent on a newer billing fetch = **0%** (1.1.6-grok1.27) |
| **O** | Sept 1 Copilot reset may keep `credits_used` (e.g. 2981) while only `quota_reset_date` moves | Stale timestamp / reset-date-advanced-but-credits-unchanged → **0** (1.1.6-grok1.28) |
| **C** | Live RPC down after window end left JSONL at 100% | Window `resetsAt` in the past → **0%** |
| **O** | Live `gh` fail + old cache after monthly reset can freeze credits | `period_reset` zero + 7-day offline cache max |

Codex usage now also prefers the read-only `account/rateLimits/read` snapshot
from the already-running local app-server connection. This closes the remaining
early-reset gap where the server starts a new window before any fresh rollout
`token_count` line exists; JSONL scanning remains the offline fallback.

### Sessions auto-popup fix (1.1.6-grok1.23)

| Issue | Root cause | Fix |
|-------|------------|-----|
| SESSIONS panel drops unprompted when Grok finishes | Completion cards **bypassed** `suppressFrontmostNotifications` ("前台会话不弹出通知") by design for "Grok L1 done signal" | Completions now honor the same suppress path as permission/question |
| Full SESSIONS list appears and **stays** open | New Grok session discovery called `notchOpen(reason: .click)` — click-opened lists do not auto-collapse on mouse leave | No longer auto-open the list on new session; notch still updates counts; open manually via click/hover |

### Codex session Done while still running (1.1.6-grok1.24)

| Issue | Root cause | Fix |
|-------|------------|-----|
| C chip **100%** while Codex is mid-turn → Island shows **Done** | `token_count` with `used_percent >= 100` + “Thinking.” auto-`markRateLimitReached` | Only complete on explicit `rate_limit_reached_type` or terminal quota copy; **C 100% is quota only** |
| After false Done, later tools never show Running | `isCompleted` blocked tool/thinking reopen | Soft “Rate limit reached.” may resume on tool / non-terminal assistant activity; hard `task_complete` still does not reopen |

## Non-goals of this fork publish

- No bundled API keys, tokens, or personal config
- Prebuilt `.app` is only on **Releases**, never required to exercise GPL rights (source ZIP always available)
- Not a claim of sole authorship of Open Island — this is a GPL-3.0 **derivative**
