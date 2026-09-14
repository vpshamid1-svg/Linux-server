#!/bin/bash
# ============================================================================
# provision.sh — v7.0 (نسخه‌ی پاک برای vpshamid1-svg)
#
#   سیاست: «لینوکس تمیز، آماده به کار»
#     * هیچ برنامه‌ای به‌طور خودکار نصب نمی‌شود (نه Hermes agent، نه 9router،
#       نه cloudflared/tunnel).
#     * 3x-ui:
#         - پیش‌فرض نصب نمی‌شود (install_xui=false).
#         - با install_xui=true نصبِ خام انجام می‌شود (بدون هیچ کانفیگی).
#         - اگر داده‌ی 3x-ui (/etc/x-ui) از state برگشته باشد ولی باینری نباشد،
#           باینری به‌طور خودکار بازنصب می‌شود (recovery) تا پنل با همان داده
#           بالا بیاید — این همان «حفظ اطلاعات برنامه» است.
#     * باینری حجیم 3x-ui (~200MB) وارد آرشیو state نمی‌شود (فقط داده/دیتابیس
#       در /etc/x-ui ماندگار است) تا اسنپ‌شات‌ها سبک بمانند.
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
XUI_DB="$XUI_ETC/x-ui.db"

has_xui_binary() {
  [ -x "$XUI_BIN" ] || [ -x "$RESTORE_ROOT/usr/local/x-ui/x-ui" ]
}

has_xui_data() {
  [ -d "$XUI_ETC" ] || [ -d "$RESTORE_ROOT/etc/x-ui" ] || [ -f "$XUI_DB" ]
}

# --- نصب systemd unit در صورت نبود (بعد از restore هم idempotent است) ---
ensure_xui_unit() {
  if [ ! -f /etc/systemd/system/x-ui.service ] && [ -f "$XUI_DIR/x-ui.service" ]; then
    $SUDO cp -f "$XUI_DIR/x-ui.service" /etc/systemd/system/x-ui.service
    $SUDO systemctl daemon-reload >/dev/null 2>&1 || true
    log "3x-ui: systemd unit installed from $XUI_DIR/x-ui.service"
  fi
  if [ -f "$XUI_DIR/x-ui.sh" ]; then
    $SUDO cp -f "$XUI_DIR/x-ui.sh" /usr/local/bin/x-ui 2>/dev/null || true
    $SUDO chmod +x /usr/local/bin/x-ui 2>/dev/null || true
  fi
}

# --- نصب خام (فقط باینری + سرویس؛ بدون هیچ تنظیمی) ---
do_install_xui() {
  local tmp="/tmp/xui.tar.gz"
  log "3x-ui: downloading release (raw install — no configuration applied)..."
  if ! curl -fsSL --max-time 180 \
       "https://github.com/MHSanaei/3x-ui/releases/latest/download/x-ui-linux-amd64.tar.gz" \
       -o "$tmp"; then
    note "3x-ui: download FAILED (network or release unavailable)"
    return 1
  fi
  # بسته‌ی رسمی شامل پوشه‌ی x-ui/ است؛ مقصد استخراج /usr/local است تا
  # مسیر نهایی /usr/local/x-ui/x-ui (باینری) باشد — مطابق چیدمان رسمی.
  $SUDO mkdir -p /usr/local
  if ! $SUDO tar -xzf "$tmp" -C /usr/local; then
    note "3x-ui: extract FAILED"
    return 1
  fi
  $SUDO chmod +x "$XUI_BIN" 2>/dev/null || true
  ensure_xui_unit
  $SUDO systemctl daemon-reload >/dev/null 2>&1 || true
  $SUDO systemctl enable x-ui >/dev/null 2>&1 || true

  # استارت اولیه فقط برای ساخته شدن پوشه‌ی تنظیمات/دیتابیس (بدون تغییر تنظیمات)
  if [ -x "$XUI_BIN" ]; then
    $SUDO systemctl start x-ui >/dev/null 2>&1
    if ! $SUDO systemctl is-active --quiet x-ui 2>/dev/null; then
      $SUDO nohup "$XUI_BIN" run >/var/log/x-ui.log 2>&1 &
    fi
    for _i in 1 2 3 4 5 6; do
      sleep 3
      [ -f "$XUI_DB" ] && break
    done
  fi
  if [ -f "$XUI_DB" ]; then
    note "3x-ui: INSTALLED (raw) — database present at $XUI_DB ($(stat -c%s "$XUI_DB" 2>/dev/null || echo '?') bytes)"
  else
    note "3x-ui: INSTALLED (raw) — database not created yet (panel will create it on first start)"
  fi
  return 0
}

provision_xui() {
  if has_xui_binary; then
    note "3x-ui: binary present — kept (no reinstall)"
    ensure_xui_unit
    return 0
  fi

  if has_xui_data; then
    note "3x-ui: data found (live or staged) but binary missing — auto-recovery install (data preserved)"
    do_install_xui
    return 0
  fi

  if [ "$INSTALL_XUI" != "true" ]; then
    note "3x-ui: not requested (install_xui=false) — clean system, nothing installed"
    return 0
  fi

  note "3x-ui: install requested (install_xui=true) — raw install, no configuration"
  do_install_xui
  return 0
}

log "=== provisioning start (v7.0 clean mode) ==="
provision_xui
log "=== provisioning done ==="
echo ""
echo "----- PROVISION SUMMARY (clean mode) -----"
cat "${LOG_DIR}/summary.txt"
echo "------------------------------------------"
exit 0
