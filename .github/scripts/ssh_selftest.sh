#!/bin/bash
# ============================================================================
# ssh_selftest.sh — v7.0: تست end-to-end محلی SSH با **رمز** (بدون نیاز به کلید)
#
#   بررسی می‌کند:
#     1) sshd در حال اجراست
#     2) ورود root@127.0.0.1 با رمز (HAMID_PASSWORD) کار می‌کند
#     3) ورود Hamid@127.0.0.1 با رمز کار می‌کند
#     4) sudo بدون رمز برای Hamid کار می‌کند
#
#   نیاز: بسته‌ی sshpass (در قدم «Setup base system» نصب می‌شود).
# ============================================================================
set -uo pipefail

echo "[ssh-test] ====== SSH self test (localhost, password auth) ======"

PASS="${HAMID_PASSWORD:-}"
if [ -z "$PASS" ]; then
  echo "[ssh-test] SKIP: HAMID_PASSWORD not set — cannot test password login"
  exit 0
fi

if ! command -v sshpass >/dev/null 2>&1; then
  echo "[ssh-test] sshpass missing — installing..."
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq sshpass >/dev/null 2>&1 || {
    echo "[ssh-test] WARN: cannot install sshpass — skipping password test"
    exit 0
  }
fi

SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null
          -o ConnectTimeout=10 -o LogLevel=ERROR -o PreferredAuthentications=password
          -o PubkeyAuthentication=no)

FAIL=0

# 0) sshd در حال اجرا
if pgrep -x sshd >/dev/null 2>&1; then
  echo "[ssh-test] 0) sshd process: running"
else
  echo "[ssh-test] 0) FAIL: sshd process not found"
  FAIL=1
fi

# 1) ورود root با رمز
echo "[ssh-test] 1) ssh root@127.0.0.1 (password) ..."
OUT=$(sshpass -p "$PASS" ssh "${SSH_OPTS[@]}" root@127.0.0.1 'id -u; whoami' 2>&1) \
  && echo "   ok: $OUT" || { echo "   FAIL: $OUT"; FAIL=1; }

# 2) ورود Hamid با رمز
echo "[ssh-test] 2) ssh Hamid@127.0.0.1 (password) ..."
OUT=$(sshpass -p "$PASS" ssh "${SSH_OPTS[@]}" Hamid@127.0.0.1 'id -un' 2>&1) \
  && echo "   ok: user=$OUT" || { echo "   FAIL: $OUT"; FAIL=1; }

# 3) sudo بدون رمز برای Hamid
echo "[ssh-test] 3) passwordless sudo for Hamid ..."
OUT=$(sshpass -p "$PASS" ssh "${SSH_OPTS[@]}" Hamid@127.0.0.1 'sudo -n id -u' 2>&1) \
  && echo "   ok: uid=$OUT" || { echo "   FAIL: $OUT"; FAIL=1; }

# 4) تأیید تنظیمات کلیدی sshd
echo "[ssh-test] 4) sshd effective settings:"
grep -E '^(PermitRootLogin|PasswordAuthentication|AllowUsers)' /etc/ssh/sshd_config 2>/dev/null | sed 's/^/   /' || true

echo "[ssh-test] result: $([ $FAIL -eq 0 ] && echo PASS || echo FAIL)"
exit $FAIL
