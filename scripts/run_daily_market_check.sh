#!/usr/bin/env bash
# Run the "15-minute daily market check" — the market-regime-daily workflow.
#
# Chains three keyless skills (public CSV data, no API key required) and prints
# the resulting market posture:
#   1) market-breadth-analyzer  -> breadth health score (0-100)
#   2) uptrend-analyzer         -> participation breadth score (0-100)
#   3) exposure-coach           -> posture: NEW_ENTRY_ALLOWED / REDUCE_ONLY / CASH_PRIORITY
#
# Each step's timestamped JSON is located automatically and fed to the next step,
# so you only run one command. The optional --with-top-risk flag adds the
# market-top-detector signal (this one requires FMP_API_KEY; it is skipped
# gracefully if the key is missing or the call fails).
#
# NOTE: This produces a market POSTURE, not a buy/sell signal. Requires internet
# access to fetch the public CSV data.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

OUTPUT_DIR="reports/daily-market-check-$(date +%F)"
WITH_TOP_RISK=0

usage() {
  cat <<'EOF'
Run the 15-minute daily market check (market-regime-daily workflow).

Steps (all keyless, public CSV data):
  1) market-breadth-analyzer  -> breadth health score (0-100)
  2) uptrend-analyzer         -> participation breadth score (0-100)
  3) exposure-coach           -> posture: NEW_ENTRY_ALLOWED / REDUCE_ONLY / CASH_PRIORITY

Usage:
  scripts/run_daily_market_check.sh [options]

Options:
  --output-dir DIR   Directory for reports
                     (default: reports/daily-market-check-YYYY-MM-DD)
  --with-top-risk    Also run market-top-detector and feed its signal to
                     exposure-coach. NOTE: this step requires FMP_API_KEY; if the
                     key is missing it is skipped (a warning is printed) and the
                     run still completes on the keyless breadth+uptrend path.
  -h, --help         Show this help

Output files (in the output dir):
  market_breadth_*.{json,md}
  uptrend_analysis_*.{json,md}
  exposure_posture_*.{json,md}

Reminder: the output is a market POSTURE, not a buy/sell signal. Requires
internet access for the public CSV fetch.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir) OUTPUT_DIR="${2:?--output-dir requires a value}"; shift 2 ;;
    --output-dir=*) OUTPUT_DIR="${1#*=}"; shift ;;
    --with-top-risk) WITH_TOP_RISK=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; echo >&2; usage >&2; exit 2 ;;
  esac
done

# The breadth history writer expects the output dir to already exist.
mkdir -p "$OUTPUT_DIR"

echo "=================================================="
echo " 15-Minute Daily Market Check (market-regime-daily)"
echo " Output: $OUTPUT_DIR"
echo "=================================================="

# --- Step 1/3: market breadth -------------------------------------------------
echo
echo "[1/3] Analyzing market breadth (market-breadth-analyzer)..."
if ! python3 skills/market-breadth-analyzer/scripts/market_breadth_analyzer.py \
      --output-dir "$OUTPUT_DIR"; then
  echo "ERROR: market breadth step failed (network/CSV unavailable?). Aborting." >&2
  exit 1
fi
BREADTH_JSON="$(ls -t "$OUTPUT_DIR"/market_breadth_*.json 2>/dev/null | head -1 || true)"
if [[ -z "$BREADTH_JSON" ]]; then
  echo "ERROR: no breadth JSON was produced in $OUTPUT_DIR. Aborting." >&2
  exit 1
fi

# --- Step 2/3: uptrend participation ------------------------------------------
echo
echo "[2/3] Analyzing uptrend participation (uptrend-analyzer)..."
if ! python3 skills/uptrend-analyzer/scripts/uptrend_analyzer.py \
      --output-dir "$OUTPUT_DIR"; then
  echo "ERROR: uptrend step failed (network/CSV unavailable?). Aborting." >&2
  exit 1
fi
UPTREND_JSON="$(ls -t "$OUTPUT_DIR"/uptrend_analysis_*.json 2>/dev/null | head -1 || true)"
if [[ -z "$UPTREND_JSON" ]]; then
  echo "ERROR: no uptrend JSON was produced in $OUTPUT_DIR. Aborting." >&2
  exit 1
fi

# --- Optional: market top risk (requires FMP_API_KEY; advisory) ---------------
# Build exposure-coach args incrementally so the array is never empty (safe
# under `set -u` on older bash).
EXPOSURE_ARGS=(--breadth "$BREADTH_JSON" --uptrend "$UPTREND_JSON")
if [[ "$WITH_TOP_RISK" -eq 1 ]]; then
  echo
  echo "[opt] Checking market top risk (market-top-detector)..."
  if python3 skills/market-top-detector/scripts/market_top_detector.py \
        --output-dir "$OUTPUT_DIR"; then
    TOP_RISK_JSON="$(ls -t "$OUTPUT_DIR"/market_top_*.json 2>/dev/null | head -1 || true)"
    if [[ -n "$TOP_RISK_JSON" ]]; then
      EXPOSURE_ARGS+=(--top-risk "$TOP_RISK_JSON")
    fi
  else
    echo "WARNING: market-top-detector failed; continuing without top-risk signal." >&2
  fi
fi

# --- Step 3/3: exposure posture -----------------------------------------------
echo
echo "[3/3] Deciding exposure posture (exposure-coach)..."
python3 skills/exposure-coach/scripts/calculate_exposure.py \
  "${EXPOSURE_ARGS[@]}" \
  --output-dir "$OUTPUT_DIR"

echo
echo "=================================================="
echo " Done. Full reports in: $OUTPUT_DIR"
echo " Reminder: this is a market POSTURE, not a buy/sell signal."
echo " If new entry is allowed, the next routine is swing-opportunity-daily."
echo "=================================================="
