---
layout: default
title: Daily Market Check (15 min)
parent: English
nav_order: 11
permalink: /en/playbooks/daily-market-check/
---

# Daily Market Check (15 minutes)

A one-command morning routine that answers a single question: **can I take new
swing-trade risk today, or should I stay defensive?** It is the runnable form of
the canonical [`market-regime-daily`](../../../workflows/market-regime-daily.yaml)
workflow.

It produces a market **posture**, not a buy/sell signal.

## What it runs

Three skills in sequence. The default path needs **no API key** (it reads public
CSV data):

| Step | Skill | Output |
|---|---|---|
| 1 | `market-breadth-analyzer` | Breadth health score 0–100 (how broad is participation) |
| 2 | `uptrend-analyzer` | Uptrend participation score 0–100 (zone: Bull / Neutral / Bear) |
| 3 | `exposure-coach` | Posture: `NEW_ENTRY_ALLOWED` / `REDUCE_ONLY` / `CASH_PRIORITY` + an exposure ceiling % |

## Quick start

From the repository root:

```bash
./scripts/run_daily_market_check.sh
```

Reports are written to `reports/daily-market-check-YYYY-MM-DD/`. The script
prints a summary like:

```
[3/3] Deciding exposure posture (exposure-coach)...
Exposure Ceiling: 33%
Recommendation: REDUCE_ONLY
Bias: NEUTRAL
Confidence: LOW
```

Options:

```bash
./scripts/run_daily_market_check.sh --help
./scripts/run_daily_market_check.sh --output-dir reports/today
./scripts/run_daily_market_check.sh --with-top-risk   # adds market-top-detector (needs FMP_API_KEY)
```

## Two ways to run it

**1. The runner script (above)** — best for a fast, repeatable daily check and
for cron automation.

**2. Conversationally in Claude** — just ask, in order, and the skills trigger
themselves and produce the same reports:

1. "Analyze market breadth"
2. "Analyze uptrend participation"
3. "Decide my exposure posture from those two reports"

Use the conversational path when you also want Claude's narrative interpretation;
use the script when you just want the numbers.

## Reading the output

**Recommendation** is the headline. It maps to the workflow's three postures:

| Recommendation | Meaning | Action |
|---|---|---|
| `NEW_ENTRY_ALLOWED` | Risk-on environment | New positions OK, up to the exposure ceiling |
| `REDUCE_ONLY` | Mixed / restricted | Manage existing positions; avoid new risk |
| `CASH_PRIORITY` | Risk-off | Raise cash; protect capital |

**Exposure Ceiling %** is the suggested maximum net equity exposure for the day.
**Confidence** reflects how many input signals were available.

> **Important nuance — the keyless path is intentionally conservative.**
> `exposure-coach` treats `breadth`, `regime`, and `top_risk` as *critical*
> inputs. The default run only supplies breadth (+ uptrend), so two critical
> inputs (`regime`, `top_risk`) are missing. With ≥2 critical inputs missing the
> coach caps the recommendation at `REDUCE_ONLY` and reports `LOW` confidence —
> by design, it will not green-light new risk on thin information.

To get a `NEW_ENTRY_ALLOWED` with higher confidence, add the missing critical
signals before step 3:

- **`top_risk`** — run `market-top-detector` (`--with-top-risk`). Requires `FMP_API_KEY`.
- **`regime`** — run `macro-regime-detector` and pass its JSON to
  `exposure-coach --regime <file>`. Requires `FMP_API_KEY` (cross-asset ratios
  via FMP; it has a per-symbol yfinance fallback, but that does *not* remove the
  key requirement).

## Daily automation (optional)

Run it automatically ~15 minutes before the US open (9:15 ET). Example cron entry
(adjust the path and your machine's timezone):

```cron
15 9 * * 1-5  cd /path/to/claude-trading-skills && ./scripts/run_daily_market_check.sh >> logs/daily-market-check.log 2>&1
```

## When to run / not run

- **Run:** before considering new swing-trade risk — pre-open or in the first 30
  minutes after the open.
- **Do not** treat the output as a standalone buy/sell signal. It is a posture
  (allow / restrict / cash-priority).

## Next steps

- If the posture is `NEW_ENTRY_ALLOWED`, proceed to the
  [`swing-opportunity-daily`](../../../workflows/swing-opportunity-daily.yaml)
  routine to find setups.
- Log the day's posture to `trader-memory-core` (the workflow's
  `journal_destination`) so later postmortems can correlate outcomes with regime.

## Reference

- Workflow manifest: [`workflows/market-regime-daily.yaml`](../../../workflows/market-regime-daily.yaml)
- Runner script: [`scripts/run_daily_market_check.sh`](../../../scripts/run_daily_market_check.sh)
- Skills: `market-breadth-analyzer`, `uptrend-analyzer`, `exposure-coach`
  (optional: `market-top-detector`, `macro-regime-detector`)
