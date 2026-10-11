# تجهيز Termux — ارفع الملفات الجديدة فقط

## قبل الرفع

- أنشئ مستودع GitHub فارغًا باسم `Buy-price-assistant-gimi` من حسابك.
- لا تضف README أو License أثناء إنشاء المستودع لأنهما موجودان هنا.
- في Termux، انقل ملف ZIP إلى مجلد `Download` أو اعرف مساره قبل فك الضغط.

## أوامر Termux بعد تنزيل ZIP إلى مجلد Download

استبدل `/sdcard/Download/Buy-price-assistant-gimi.zip` بالمسار الفعلي إذا كان مختلفًا.

```bash
pkg update
pkg install git unzip python -y
termux-setup-storage
cd "$HOME"
if [ -e "$HOME/Buy-price-assistant-gimi" ]; then
  echo "مجلد Buy-price-assistant-gimi موجود بالفعل؛ أوقف العملية وافحصه قبل المتابعة حتى لا تختلط أي ملفات قديمة بالمشروع الجديد."
  exit 1
fi
mkdir Buy-price-assistant-gimi
unzip /sdcard/Download/Buy-price-assistant-gimi.zip -d "$HOME"
cd "$HOME/Buy-price-assistant-gimi"
```

تأكد أنك داخل مجلد المشروع الجديد وأن ملفات `pubspec.yaml` و`.github/workflows/android-ci.yml` موجودة:

```bash
pwd
ls -la
find lib test .github tool -maxdepth 3 -type f
```

ثم ارفع إلى المستودع الجديد (وليس أي مستودع سابق):

```bash
git init
git branch -M main
git add .
git status --short
git commit -m "Initial clean build: Buy Price Assistant GIMI"
git remote add origin https://github.com/abnalhag2022-droid/Buy-price-assistant-gimi.git
git push -u origin main
```

إذا طلب GitHub كلمة مرور عند `git push`، لا تستخدم كلمة مرور حسابك العادية. أكمل مصادقة GitHub عبر طريقة موثوقة سبق أن أعددتها (مثل PAT محفوظ بأمان أو SSH). لا تضع رمز الوصول داخل ملف أو أمر قابل للمشاركة.

إذا أخبر Git أن `origin` موجود مسبقًا، لا تستبدله عشوائيًا. افحصه أولًا:

```bash
git remote -v
```

لا تنفذ `git push --force` على هذا المشروع. إذا ظهر خطأ في أي أمر، أرسل مخرجاته قبل تجربة أوامر إضافية.
