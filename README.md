# Buy Price Assistant HJI — مرجع أسعار الأصناف

تطبيق Android يعمل دون إنترنت لحفظ أسعار شراء الأصناف وبيعها والرجوع إلى آخر سعر في ثوانٍ. البيانات محفوظة على الجهاز فقط في قاعدة SQLite.

An offline Android app (Flutter) for recording item purchase and sale prices and finding the latest price in seconds. Data stays on the device in SQLite.

| | |
|---|---|
| الإصدار / Version | **1.5.0+8** ([CHANGELOG](CHANGELOG.md)) |
| معرّف التطبيق / Application ID | `com.abnalhag.gimi.buy_price_assistant_gimi` (ثابت لا يتغير / permanent) |
| Android | minSdk 24 (Android 7.0) · targetSdk 36 |
| قاعدة البيانات / Database | schema v5 · backup format v3 |

## الوظائف

- **البحث**: بالاسم أو الكود أو التصنيف أو العلامة أو الملاحظات أو المورد أو العميل أو التاريخ أو السعر، بأرقام عربية أو إنجليزية، مع تصفية حسب التصنيف والعلامة والمورد. النتائج مرتبة (المفضلة أولًا) ومجزأة إلى صفحات مع العدد الكلي.
- **بطاقة الصنف**: آخر سعر شراء وآخر سعر بيع، كلٌّ بعملته وتاريخه والمورد أو العميل؛ وعند عدم وجود سعر تظهر عبارة «لا يوجد سعر مسجل»، ولا يُقدَّر أي سعر.
- **السجل الكامل**: كل عمليات الشراء والبيع مع التعديل والحذف المؤكد، وفرق آخر بيع عن آخر شراء فقط عندما يكونان بالعملة نفسها.
- **الأرشفة**: إخفاء الصنف مع الاحتفاظ بسجله، وعرض المؤرشفة وإلغاء أرشفتها.
- **الاستيراد والتصدير**: XLSX وCSV UTF-8 بمعاينة كاملة قبل الكتابة، وقرار صريح لكل صنف ملتبس، ونسخة أمان تلقائية، وإمكانية التراجع عن أي استيراد. راجع [سياسة مطابقة الأصناف](docs/IMPORT_MATCHING_POLICY.md).
- **النسخ الاحتياطي**: ملف JSON مع بصمة تحقق SHA-256؛ الاستعادة تعرض ملخص الملف قبل التأكيد وتحفظ نسخة أمان من البيانات الحالية أولًا.
- **الواجهة**: عربية (من اليمين لليسار) وإنجليزية، مظهر فاتح وداكن، وتصميم موحّد موصوف في [نظام التصميم](docs/DESIGN_SYSTEM.md).

## Features (English)

Search across every field with Arabic or Latin digits; product cards with the latest purchase and sale price, currency, date and supplier/customer (never an estimated value); full history with edit/delete; archive and restore; spreadsheet import with preview, explicit decisions for ambiguous products, safety snapshot and undo; checksummed JSON backups; Arabic RTL and English LTR; light and dark themes.

## سلامة البيانات / Data safety

- لا تُدمج الأسماء المختلفة تلقائيًا عند الاستيراد: «كابل 2 خط 4 ملم» و«كابل 4 خط 2 ملم» صنفان مختلفان.
- لا تُحوَّل الأسعار بين العملات، ولا يُطرح سعران بعملتين مختلفتين.
- كل ترحيل لقاعدة البيانات إضافي ويمكن تكراره بأمان؛ ويرفض التطبيق فتح قاعدة أنشأها إصدار أحدث بدل إتلافها.
- الاستيراد والاستعادة يحفظان نسخة أمان تلقائية قبل أي كتابة (آخر 5 نسخ داخل التطبيق).
- النسخ الاحتياطية وملفات التصدير غير مشفّرة وتحتوي أسماء الموردين والعملاء؛ احفظها في مكان آمن.

## البناء والاختبار / Build and test

المتطلبات: Flutter 3.47.5 (Dart 3.13)، وJDK 17 وAndroid SDK للبناء.

```bash
flutter pub get --enforce-lockfile
flutter analyze
flutter test                        # unit, database, import, widget tests
GIMI_BENCHMARK=1 flutter test test/benchmark/          # optional search timing
GIMI_SCREENSHOTS=1 flutter test test/screenshots/      # optional design renders → .screenshots/
python3 tool/prepare_android.py     # generates android/ (pinned SDK levels, icon, signing hook)
flutter build apk --release
flutter build appbundle --release
```

`android/` غير محفوظ في المستودع؛ يُنشأ في كل بناء بواسطة `tool/prepare_android.py`، الذي يثبّت مستويات SDK ويتحقق من معرّف التطبيق ويضيف الأيقونة ويهيّئ التوقيع من `android/key.properties` (يوفّره CI من الأسرار فقط).

### CI

[`.github/workflows/android-ci.yml`](.github/workflows/android-ci.yml) يعمل عند كل دفع إلى الفروع المدرجة:
تحليل → اختبارات → توليد Android → بناء APK وAAB موقّعين → فحص الحزمة والإصدار ومستويات SDK والأذونات (aapt2) → فحص محاذاة 16 KB → مطابقة شهادة التوقيع مع مفتاح الإصدار → رفع APK وAAB كـ artifacts. طلبات الدمج تُبنى دون أسرار ولا تُرفع مخرجاتها.

## هيكل المشروع / Layout

```
lib/
  data/      app_database.dart (SQLite, search index, backup), spreadsheet_exchange.dart (import/export),
             backup_service.dart, backup_validator.dart, file_access.dart
  screens/   one file per screen
  ui/        design tokens, themes and shared components
  utils/     number/date helpers, currencies, bilingual messages, error log, app info
test/        unit, database migration, import, search, widget and on-demand tests
tool/        prepare_android.py, android_res/ (icon), brand/ (icon generator, SVG)
docs/        policies, decisions, test matrix, release preparation, reports
```

## الوثائق / Documentation

- [CHANGELOG.md](CHANGELOG.md)
- [docs/IMPORT_MATCHING_POLICY.md](docs/IMPORT_MATCHING_POLICY.md) — كيف تُطابق صفوف الاستيراد بالأصناف
- [docs/DESIGN_SYSTEM.md](docs/DESIGN_SYSTEM.md) — الألوان والمسافات والمكونات
- [docs/TEST_MATRIX.md](docs/TEST_MATRIX.md) — ما يُختبر آليًا وما يحتاج تجربة على جهاز
- [docs/DECISIONS.md](docs/DECISIONS.md) — قرارات بانتظار موافقة المالك
- [docs/release/](docs/release/) — تجهيز Google Play (لم يُنشر شيء)
- [docs/reports/REMEDIATION_REPORT_AR.md](docs/reports/REMEDIATION_REPORT_AR.md) — تقرير المعالجة الكامل
- [docs/archive/](docs/archive/) — وثائق الإصدارات السابقة (للتاريخ فقط)

## الدعم / Support

واتساب ‎+967773436537 · abnalhag2022@gmail.com

الترخيص: [MIT](LICENSE).
