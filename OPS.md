# OPS — راهنمای عملیاتی سرور (v7.0 — نسخه‌ی پاک)

> چرخه عادی: هر Run ~۳۵۰ دقیقه؛ ۲۰ دقیقه قبل از پایان، خودِ Run جانشین را dispatch می‌کند.
> تیک ساعته کرون فقط backstop است. قطعی هر دست‌به‌دست‌سازی = چند دقیقه (بوت + بازیابی state).

## ۱) کارهای روزمره
- **وضعیت سریع:** Actions ← آخرین Run باید `in_progress` و قدم `Keep server alive` باشد.
- **جایگزینی دستی (ریبیلد):** Actions ← Run workflow (`lifetime_min` پیش‌فرض ۳۵۰).
- **تست سریع:** Run workflow با `lifetime_min=3` (رانر تست؛ زیر ۴ دقیقه می‌ماند و جانشین dispatch نمی‌کند).
- **خاموش کردن کامل:** کنسل Run فعال + Disable ورکفلو (وگرنه کرون ساعته دوباره روشنش می‌کند).
- **وصل SSH:** `ssh root@<IP-ثابت>` با رمز `HAMID_PASSWORD` (نیازی به کلید نیست).
- **چک سلامت از بیرون:** ورکفلو `ops-server-check` (وضعیت نود در tailnet + سرویس‌ها روی سرور).

## ۱٫۵) محافظت از «همیشه یک رانر در چرخه باشد» (دو حالت)

| حالت | مکانیزم | زمان واکنش |
|---|---|---|
| ۱) تعویض عادی (پایان عمر ~۵.۸ ساعته / سقف ۶ ساعتهٔ job) | خودِ ران، **۲۰ دقیقه قبل از پایان**، رانِ جانشین را dispatch می‌کند (زنجیره) | قطعی فقط چند دقیقه (بوت + بازیابی state) |
| ۲) مرگ ناگهانی (خطا / کنسل / تایم‌اوت / کرش runner) | قدم **Auto-recover** در پایان همان ران، بلافاصله جانشین می‌سازد | **چند ثانیه** (بدون انتظار برای نگهبان) |
| لایهٔ پشتیبان | ۴ نگهبان زمان‌بند (A / B / C / D) در یک concurrency group | تیک هر ~۲-۳ دقیقه |
| لایهٔ آخر | کرون ساعتیِ خودِ `main.yml` | حداکثر ۱ ساعت |

نکته‌ها:
- قدم Auto-recover فقط وقتی اقدام می‌کند که جانشین از قبل ساخته نشده باشد **و** رانِ زنده/در صفِ دیگری
  وجود نداشته باشد (جلوگیری از دیسپچ دوتایی).
- در ران‌های تست (`lifetime_min < 60`) بازیابی غیرفعال است تا بعد از تست، سرور خودبه‌خود بالا نیاید.
- **خاموش کردن عمدی:** متغیر ریپو را `SERVER_ENABLED = false` کنید
  (Settings → Secrets and variables → Actions → Variables). در این حالت نه Auto-recover و نه نگهبان‌ها
  رانری روشن نمی‌کنند. برای روشن کردن دوباره: مقدار را `true` کنید و یک ران دستی بزنید
  (یا کل ورکفلو را Disable کنید).

## ۲) قرارداد ایجنت
- اگر `/root/agent-autostart.sh` موجود باشد، آخر هر بوت با **root** اجرا می‌شود (غیرfatal؛ لاگ `/var/log/agent-autostart.log`).
- باید **idempotent** و سریع باشد؛ کار طولانی را به background بسپارد.
- فقط مسیرهای `persist.list` بین ریبیلدها می‌مانند → workspace را زیر `/root` یا `/home/Hamid` نگه دار.
- کلیدهای API فقط از طریق **GitHub Secrets** (env)؛ هرگز در فایل/آرشیو.

## ۳) کلیدها و توکن‌ها
| مورد | کجا | وضعیت/چرخه |
|---|---|---|
| Tailscale Auth Key | Secret `TAILSCALE_AUTH_KEY` | ۹۰ روزه. **باید non-ephemeral باشد** وگرنه نود بعد از قطعی حذف و IP عوض می‌شود. ساخت: `POST /api/v2/tailnet/-/keys` با `capabilities.devices.create {reusable:true, ephemeral:false, preauthorized:true}` |
| Tailscale API Token | Secret `TAILSCALE_API_TOKEN` | زمان‌دار؛ تاریخ انقضا در `key-dates.json`. بدون آن: pin IP + پاکسازی نود یتیم غیرفعال می‌شود (بوت نمی‌شکند) |
| PAT | Secret `PERSIST_TOKEN` | دسترسی به ریپوی state + fallback دیسپچ (زنجیره با `GITHUB_TOKEN` خود ران کار می‌کند) |
| رمز سرور | Secret `HAMID_PASSWORD` | برای `root` و `Hamid`؛ در هر بوت اعمال می‌شود |
| `.github/key-dates.json` | داخل ریپو | با هر تعویض توکن به‌روز شود (هر بوت چک می‌شود) |

## ۴) 3x-ui
- پیش‌فرض نصب نمی‌شود. برای نصب: Run workflow با `install_xui=true` (نصب خام، بدون کانفیگ).
- ماندگاری: داده‌ها در `/etc/x-ui` (شامل `x-ui.db`) در هر اسنپ‌شات ذخیره می‌شوند؛ باینری در ریبیلد
  خودکار بازنصب می‌شود (recovery وقتی داده وجود داشته باشد).
- برای حذف: داخل سرور `x-ui uninstall`.

## ۵) خرابی‌های رایج
| علامت | واکنش |
|---|---|
| قدم بوت قرمز | لاگ همان قدم؛ معمولاً گذراست → یک Run دستی جدید |
| dispatch جانشین شکست (لاگ `[successor]`) | Run جدید دستی بزن؛ سلامت توکن‌ها را چک کن؛ کرون ساعته backstop است |
| نود تیل‌اسکیل آفلاین >۱۵ دقیقه | وسط ریبیلد؟ اگر نه: Run فعلی را چک کن (قدم Setup Tailscale) |
| **IP سرور عوض شده** | بررسی کن auth key غیر-ephemeral باشد و `/var/lib/tailscale` در state باشد؛ مقدار `TAILSCALE_FIXED_IP` را هم چک کن |
| ورود SSH با رمز کار نکرد | قدم `SSH local self-test` را ببین؛ `HAMID_PASSWORD` ست شده باشد و `sshd_config` دارای `PasswordAuthentication yes` باشد |
| داده‌ی برنامه‌ای بعد از ریبیلد نماند | مسیر آن در `.github/scripts/persist.list` نیست → اضافه کن |

## ۶) محدودیت‌ها و ریسک‌های واقعی
- **مصرف دقیقه: نامحدود** — ریپو **public** است و روی پلن Free اجرای Actions برای ریپوهای عمومی رایگان و
  بی‌سقف است (سقف ۲۰۰۰ دقیقه فقط برای ریپوهای **خصوصی** است). ریپوی state خصوصی است اما Actions روی آن
  اجرا نمی‌شود، پس مصرفی ندارد. پایش: `Settings → Billing and plans → Usage → Actions`.
- **سقف ۶ ساعت برای هر job** → عمر هر ران ۳۵۰ دقیقه است و زنجیره‌ی جانشین ۲۰ دقیقه زودتر ران بعدی را می‌سازد.
- **تأخیر زمان‌بند کرون** (گه‌گاه چند دقیقه تا بیش از یک ساعت) → دو نگهبان با زمان‌بند متفاوت (A و B) آن را جبران می‌کنند.
- **انقضای PAT / کلید تیل‌اسکیل** → چک هر بوت + `key-dates.json`؛ انقضا باعث توقف زنجیره می‌شود.

## ۷) بکاپ
- کد: `git clone https://github.com/vpshamid1-svg/Linux-server`
- state: ریپوی private `Linux-server-state`؛ **۲ اسنپ‌شات آخر** روی Release با تگ `state`:
```bash
curl -s -H "Authorization: Bearer $PAT" \
  "https://api.github.com/repos/vpshamid1-svg/Linux-server-state/releases/tags/state" \
  | python3 -c "import json,sys; [print(a['name'], a['size']) for a in json.load(sys.stdin)['assets']]"
```
- همیشه یک کلون محلی از هر دو ریپو نگه دار.

## ۸) امنیت
- سرور فقط از طریق IP خصوصی Tailscale (100.x) در دسترس است.
- ورود با رمز برای `root` فعال است؛ چون دسترسی فقط از داخل tailnet است ریسکِ brute-force اینترنتی ندارد،
  اما رمز را قوی نگه دار و در صورت لو رفتن `HAMID_PASSWORD` را عوض کن.
- لاگ‌ها secret چاپ نمی‌کنند.
