#!/bin/bash
# ============================================================================
# provision.sh — v7.0 (نسخه‌ی پاک برای vpshamid1-svg)
#
#   سیاست این نسخه: «لینوکس تمیز، آماده به کار»
#     * هیچ برنامه‌ای به‌طور خودکار نصب نمی‌شود (نه Hermes agent، نه 9router،
#       نه cloudflared/tunnel).
#     * 3x-ui فقط در صورتی نصب می‌شود که صریحاً درخواست شود
#       (ورودی install_xui=true در workflow_dispatch) — آن هم فقط نصب خام،
#       بدون هیچ تنظیم/کانفیگی؛ بعد از نصب، داده‌های آن
#       (/etc/x-ui و /usr/local/x-ui) توسط مکانیزم ماندگاری حفظ می‌شوند.
#     * اگر 3x-ui از قبل روی دیسک/state موجود باشد، فقط سرویس آن تضمین می‌شود
#       (نصب مجدد انجام نمی‌شود).
#
#   Non-fatal: هیچ خروجیِ غیرصفر باعث توقف بوت نمی‌شود.
# ============================================================================
set -uo pipefail

LOG_DIR=/tmp/provision
mkdir -p "$LOG_DIR"
log()  { echo "[provision $(date -u '+%T')] $*"; }
note() { echo "[provision] $*" | tee -a "${LOG_DIR}/summary.txt"; }
: > "${LOG_DIR}/summary.txt"

SUDO=""
[ "$(id -u)" -eq 0 ] || SUDO="sudo"

RESTORE_ROOT="/tmp/persist-restore"
INSTALL_XUI="${INSTALL_XUI:-false}"

XUI_DIR=/usr/local/x-ui
XUI_BIN="$XUI_DIR/x-ui"
XUI_ETC=/etc/x-ui

has_xui_binary() {
  [ -x "$XUI_BIN" ] || [ -x "$RESTORE_ROOT/usr/local/x-ui/x-ui" ]
}

has_xui_data() {
  [ -d "$XUI_ETC" ] || [ -d "$RESTORE_ROOT/etc/x-ui" ]
}

# --- نصب systemd unit در صورت نبود (بعد از restore هم idempotent است) ---
ensure_xui_unit() {
  if [ -f /etc/systemd/system/x-ui.service ]; then
    return 0
  fi
  if [ -f "$XUI_DIR/x-ui.service" ]; then
    $SUDO cp -f "$XUI_DIR/x-ui.service" /etc/systemd/system/x-ui.service
    $SUDO systemctl daemon-reload >/dev/null 2>&1 || true
    note "3x-ui: systemd unit restored from $XUI_DIR/x-ui.service"
  fi
}

provision_xui() {
  if has_xui_binary; then
    note "3x-ui: already present — kept (no reinstall, Mode 2)"
    ensure_xui_unit
    return 0
  fi

  if [ "$INSTALL_XUI" != "true" ]; then
    if has_xui_data; then
      note "3x-ui: data exists (live or staged) but binary missing — install skipped because install_xui != true"
    else
      note "3x-ui: not requested (install_xui=false) — clean system, nothing installed"
    fi
    return 0
  fi

  # ---- نصب خام (فقط برای تست ماندگاری داده)؛ بدون هیچ تنظیمی ----
  log "3x-ui: install requested (install_xui=true) — installing raw release (test mode, no config)..."
  local tmp="/tmp/xui.tar.gz"
  if ! curl -fsSL --max-time 120 \
       "https://github.com/MHSanaei/3x-ui/releases/latest/download/x-ui-linux-amd64.tar.gz" \
       -o "$tmp"; then
    note "3x-ui: download FAILED (network or release unavailable)"
    return 0
  fi
  $SUDO mkdir -p "$XUI_DIR"
  if ! $SUDO tar -xzf "$tmp" -C "$XUI_DIR"; then
    note "3x-ui: extract FAILED"
    return 0
  fi
  $SUDO chmod +x "$XUI_BIN" 2>/dev/null || true
  # بسته‌ی رسمی معمولاً شامل x-ui.sh / x-ui.service است
  [ -f "$XUI_DIR/x-ui.service" ] && $SUDO cp -f "$XUI_DIR/x-ui.service" /etc/systemd/system/x-ui.service
  $SUDO systemctl daemon-reload >/dev/null 2>&1 || true
  $SUDO systemctl enable x-ui >/dev/null 2>&1 || true
  # استارت اولیه فقط برای این‌که دیتابیس/پوشه‌ی تنظیمات ساخته شود (بدون تغییر تنظیمات)
  if [ -x "$XUI_BIN" ]; then
    $SUDO systemctl start x-ui >/dev/null 2>&1 \
      || $SUDO nohup "$XUI_BIN" run >/var/log/x-ui.log 2>&1 &
    sleep 3
  fi
  note "3x-ui: INSTALLED (raw, test mode — default panel, no configuration applied)"
}

log "=== provisioning start (v7.0 clean mode) ==="
provision_xui
log "=== provisioning done ==="
echo ""
echo "----- PROVISION SUMMARY (clean mode) -----"
cat "${LOG_DIR}/summary.txt"
echo "------------------------------------------"
exit 0
