#!/usr/bin/env bash
# ============================================================================
# start-services.sh — v7.0 (نسخه‌ی پاک)
#   استارت سرویس‌های ماندگار بعد از restore:
#     * sshd      (ورود با رمز برای root و Hamid)
#     * tailscaled (هویت/IP ثابت)
#     * x-ui      (فقط اگر نصب شده باشد — در نصب پاک هیچ کاری نمی‌کند)
#   همه idempotent و غیرکشنده (non-fatal).
# ============================================================================
set -uo pipefail

fail=0

start_system() {
  local u="$1"
  if [ ! -f "/etc/systemd/system/$u" ] && ! systemctl list-unit-files 2>/dev/null | grep -q "^$u"; then
    echo "[services] $u: unit file absent — skip"
    return 0
  fi
  systemctl daemon-reload >/dev/null 2>&1 || true
  systemctl enable "$u" >/dev/null 2>&1 || true
  if systemctl start "$u" >/dev/null 2>&1; then
    echo "[services] $u: started"
  else
    echo "[services] WARNING: $u failed to start (non-fatal, boot continues)"
    systemctl status "$u" --no-pager -l 2>/dev/null | tail -8 || true
    fail=1
  fi
}

echo "[services] ==== starting persistent services ===="

# --- SSH: ورود با رمز برای root و Hamid ---
systemctl enable ssh >/dev/null 2>&1 || systemctl enable sshd >/dev/null 2>&1 || true
systemctl restart ssh >/dev/null 2>&1 || systemctl restart sshd >/dev/null 2>&1 || service ssh restart >/dev/null 2>&1 || true
sleep 1
if pgrep -x sshd >/dev/null 2>&1; then
  echo "[services] sshd: running ($(ss -tlnp 2>/dev/null | grep -c ':22 ') listener on :22)"
else
  echo "[services] WARNING: sshd not running"
  fail=1
fi

# --- Tailscale: هویت پایدار (IP ثابت) ---
# نکته: در اولین بوت، بسته‌ی tailscale هنوز نصب نشده (نصب در قدم بعد انجام
# می‌شود) — بنابراین نبود آن در اینجا طبیعی است و هشدار محسوب نمی‌شود.
if ! command -v tailscaled >/dev/null 2>&1; then
  echo "[services] tailscaled: not installed yet (will be set up in the Tailscale step) — skip"
elif pgrep -x tailscaled >/dev/null 2>&1; then
  echo "[services] tailscaled: running"
else
  systemctl enable tailscaled >/dev/null 2>&1 || true
  systemctl start tailscaled >/dev/null 2>&1 || true
  sleep 2
  if pgrep -x tailscaled >/dev/null 2>&1; then
    echo "[services] tailscaled: started"
  else
    echo "[services] WARNING: tailscaled failed to start"
    fail=1
  fi
fi
if ! pgrep -x tailscaled >/dev/null 2>&1; then
  systemctl start tailscaled >/dev/null 2>&1 || true
  sleep 2
fi
if pgrep -x tailscaled >/dev/null 2>&1; then
  echo "[services] tailscaled: running (ip=$(tailscale ip -4 2>/dev/null | head -1 || echo pending))"
else
  echo "[services] WARNING: tailscaled not running"
  fail=1
fi

# --- 3x-ui: فقط اگر نصب شده باشد (در سیستم پاک رد می‌شود) ---
if [ -x /usr/local/x-ui/x-ui ] || [ -f /etc/systemd/system/x-ui.service ]; then
  if [ ! -f /etc/systemd/system/x-ui.service ] && [ -f /usr/local/x-ui/x-ui.service ]; then
    echo "[services] restoring x-ui.service from /usr/local/x-ui/x-ui.service"
    cp -f /usr/local/x-ui/x-ui.service /etc/systemd/system/x-ui.service
    systemctl daemon-reload >/dev/null 2>&1 || true
  fi
  start_system x-ui.service
  sleep 2
  if [ -f /etc/x-ui/x-ui.db ]; then
    echo "[services] x-ui: database present ($(stat -c%s /etc/x-ui/x-ui.db 2>/dev/null || echo '?') bytes)"
  else
    echo "[services] x-ui: no database yet"
  fi
else
  echo "[services] x-ui: not installed — skip (clean system)"
fi

echo "[services] ==== status ===="
systemctl is-active ssh 2>/dev/null || systemctl is-active sshd 2>/dev/null || true
systemctl is-active tailscaled 2>/dev/null || true
[ -f /etc/systemd/system/x-ui.service ] && { systemctl is-active x-ui 2>/dev/null || true; }

if [ "$fail" -ne 0 ]; then
  echo "[services] DONE with warnings (boot continues)"
else
  echo "[services] DONE — all requested services started"
fi
exit 0
