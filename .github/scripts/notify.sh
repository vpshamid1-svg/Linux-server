#!/bin/bash
# ============================================================================
# notify.sh — v7.0 (نسخه‌ی پاک؛ بدون تلگرام/وب‌هوک)
#
#   ثبت اعلان «Failure» برای چرخه‌های Backup/Restore/Server:
#     - همیشه یک نشانگر JSON در /tmp/failure-notify.json می‌نویسد (قدم پایانی
#       workflow آن را می‌خواند تا اعلان از دست نرود).
#     - خروجی را به GITHUB_STEP_SUMMARY اضافه می‌کند.
#     - هیچ ارسال شبکه‌ای انجام نمی‌دهد: نه تلگرام، نه Discord، نه وب‌هوک.
#       (اطلاع‌رسانی از طریق اعلان/ایمیل خود گیت‌هاب انجام می‌شود.)
#
# Usage: notify.sh --type <backup|restore|server|workflow> \
#                  --stage <نام مرحله> \
#                  --error <متن خطا>
# ============================================================================
set -uo pipefail

TYPE="unknown"
STAGE="unknown"
ERR=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --type)  TYPE="${2:-unknown}"; shift 2 ;;
    --stage) STAGE="${2:-unknown}"; shift 2 ;;
    --error) shift; ERR="$*"; break ;;
    *) shift ;;
  esac
done
[ -n "$ERR" ] || ERR="(no error text provided)"

RUN="${GITHUB_RUN_ID:-?}"
ATT="${GITHUB_RUN_ATTEMPT:-1}"
TS="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

# --- نشانگر JSON برای قدم پایانی workflow -------------------------------
python3 - "$TYPE" "$STAGE" "$ERR" "$RUN" "$ATT" "$TS" <<'PY'
import json, os, sys
t, s, e, r, a, ts = sys.argv[1:7]
path = "/tmp/failure-notify.json"
try:
    obj = json.load(open(path))
except Exception:
    obj = {"run": r, "attempt": a}
obj.setdefault("events", []).append(
    {"type": t, "stage": s, "error": e, "run": r, "attempt": a, "ts": ts})
with open(path, "w") as fh:
    json.dump(obj, fh, indent=2)
PY

echo "[notify] FAILURE type=${TYPE} stage=${STAGE} run=${RUN}#${ATT} ts=${TS}"
echo "[notify] error: ${ERR}"

# --- خلاصه‌ی قدم (Step Summary) ------------------------------------------
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo ""
    echo "## ❌ Linux-server failure"
    echo ""
    echo "| Item | Value |"
    echo "|---|---|"
    echo "| Operation | \`${TYPE}\` |"
    echo "| Stage | \`${STAGE}\` |"
    echo "| Run | \`${RUN}\` (attempt ${ATT}) |"
    echo "| Time | \`${TS}\` |"
    echo ""
    echo '```'
    echo "${ERR}"
    echo '```'
  } >> "$GITHUB_STEP_SUMMARY" 2>/dev/null || true
fi

echo "[notify] notification recorded locally (no telegram/webhook configured by design)"
exit 0
