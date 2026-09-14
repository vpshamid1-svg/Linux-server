# Linux-server (v7.0) — نسخه‌ی پاک برای `vpshamid1-svg`

سرور Ubuntu پایدار روی GitHub Actions: **داده‌ی ماندگار، هویت Tailscale ثابت (IP ثابت)، SSH با رمز، بدون تلگرام و بدون Hermes/9router**.

این ریپو یک کپیِ پاک‌شده از `hrgh3d/Linux-server` است با این تفاوت‌ها:

| مورد | وضعیت در این نسخه |
|---|---|
| Hermes agent / 9router / cloudflared tunnel | ❌ حذف کامل (نصب نمی‌شوند) |
| تلگرام (ربات‌ها، chat_id، وب‌هوک) | ❌ حذف کامل — اعلان‌ها فقط در Step Summary |
| 3x-ui | ⚪ نصب پیش‌فرض: خیر. فقط با `install_xui=true` (نصب خام، بدون کانفیگ) |
| ورود SSH | ✅ با **رمز** برای `root` و `Hamid` (`HAMID_PASSWORD`) — بدون نیاز به کلید |
| IP سرور | ✅ ثابت (نود Tailscale غیر-ephemeral + node key در state) |
| کلیدهای Tailscale | ✅ کلیدهای مخصوص این حساب (`TAILSCALE_AUTH_KEY` / `TAILSCALE_API_TOKEN`) |

## چطور کار می‌کند
- هر Run یک runner موقت است (~۵.۸ ساعت عمر). ۲۰ دقیقه قبل از پایان، خودِ Run جانشین را dispatch می‌کند (زنجیره؛ قطعی هر دست‌به‌دست‌سازی = فقط چند دقیقه بوت).
- تیک ساعته کرون فقط **backstop** است (اگر زنجیره پاره شود).
- در ابتدای هر بوت: دانلود state از ریپوی خصوصی `Linux-server-state` → بازنصب پکیج‌های کاربر → اعمال داده/تنظیمات → استارت سرویس‌ها.
- هر ۵ دقیقه state در صورت تغییر ذخیره می‌شود (rolling؛ ۲ نسخه‌ی آخر برای rollback).

## چه چیزهایی ماندگار است
- `/root` ،`/home/Hamid` ،`/opt` ،`/srv` ،`/etc` ،`/usr/local/bin|sbin` ،**`/usr/local/x-ui`** ،`/var/www` ،`/var/lib` ،`/var/opt` ،cron
- پکیج‌های apt/pip کاربر با نسخه‌ی دقیق (کاتالوگ در state)
- هویت Tailscale (`/var/lib/tailscale`) → **IP ثابت**
- کلیدهای Host SSH (fingerprint ثابت)
- دیتابیس‌های SQLite به‌صورت snapshot سازگار (online backup) — شامل `x-ui.db`

## اتصال SSH
```bash
ssh root@100.x.y.z        # رمز: مقدار secret HAMID_PASSWORD
ssh Hamid@100.x.y.z       # همان رمز + sudo بدون رمز
```
IP را بعد از اولین بوت از لاگ قدم `Setup Tailscale` یا Step Summary بگیرید (ثابت می‌ماند).

## 3x-ui
- به‌طور پیش‌فرض **نصب نمی‌شود** (سیستم تمیز).
- برای نصب (فقط تست/استفاده‌ی شخصی): `Actions → Linux-server → Run workflow` با `install_xui = true`.
  نصب به‌صورت **خام** انجام می‌شود و هیچ تنظیمی روی آن اعمال نمی‌شود.
- بعد از نصب، داده‌ها کاملاً ماندگارند: `/usr/local/x-ui` (binary) و `/etc/x-ui` (دیتابیس) هر دو در
  `persist.list` هستند و دیتابیس SQLite با snapshot سازگار بکاپ می‌شود.
- حذف در صورت نیاز: `x-ui uninstall` (روی خود سرور).

## Secretهای این ریپو (۵ مورد)
| Secret | توضیح |
|---|---|
| `PERSIST_TOKEN` | PAT همین حساب (دسترسی به ریپوی state + dispatch) |
| `HAMID_PASSWORD` | رمز ورود `root` و `Hamid` |
| `TAILSCALE_AUTH_KEY` | کلید اتصال اولیه (reusable, **non-ephemeral**, preauthorized) |
| `TAILSCALE_API_TOKEN` | توکن API تیل‌اسکیل (پاکسازی نود یتیم + چک انقضا + pin کردن IP) |
| `TAILSCALE_FIXED_IP` | IP ثابت موردنظر (اختیاری؛ فقط برای pin کردن) |

> هیچ secret مربوط به تلگرام/داشبورد در این نسخه وجود ندارد.

## ساختار ریپو
```
.github/
  workflows/
    main.yml               # چرخه‌ی بوت + keepalive + زنجیره‌ی جانشین
    watchdog.yml / -b.yml  # نگهبان (هر ۱۰ دقیقه) — ثبت وضعیت، بدون ارسال
    keepalive-monthly.yml  # نگه داشتن PAT/فعالیت ماهانه
    ops-exec.yml           # اجرای دستور روی سرور از طریق Actions
    ops-server-check.yml   # چک سلامت سرور از بیرون (tailnet + SSH)
  scripts/
    save.sh / restore.sh   # اسنپ‌شات و بازیابی (rolling 2 نسخه)
    state_sync.py          # آپلود/دانلود اتمیک + keep-2
    payload.py             # فیلتر مسیرها (چه چیزی بکاپ می‌شود)
    sqlite_stage.py        # snapshot سازگار دیتابیس‌های زنده
    tailscale-setup.sh     # اتصال/بازاتصال Tailscale (IP ثابت)
    ssh_configure.sh       # sshd (ورود با رمز) + کلیدهای Host
    ssh_selftest.sh        # تست ورود با رمز برای root و Hamid
    provision.sh           # نصب 3x-ui فقط در صورت درخواست
    start-services.sh      # استارت sshd/tailscale/x-ui (در صورت وجود)
    server_report.sh       # گزارش بوت (Step Summary)
    notify.sh              # ثبت خطا (بدون ارسال شبکه‌ای)
  config/sshd_config       # کانفیگ ثابت sshd
  key-dates.json           # تاریخ انقضای توکن‌ها
README.md / OPS.md / ARCHITECTURE.md
```

## ⚠️ مصرف دقیقه Actions
ریپو **public** و اکانت **Free** → سقف رایگان **۲۰۰۰ دقیقه/ماه**. مصرف ≈ **۱۴۵۰ دقیقه/روز**
(سرورِ همیشه‌روشن) یعنی سقف ماهانه در حدود ۱.۴ روز پر می‌شود. پایش:
`Settings → Billing and plans → Usage → Actions`.
گزینه‌ی پایدار: پلن Team یا مهاجرت به VPS واقعی.
