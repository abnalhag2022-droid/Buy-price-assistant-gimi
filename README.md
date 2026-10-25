# Buy Price Assistant GIMI — v1.3.0

تطبيق Flutter محلي لإدارة مرجع أسعار شراء الأصناف وبيعها مع حفظ سجل الأسعار على الجهاز والعمل دون إنترنت.

## الجديد في 1.3.0+5

- استيراد وتصدير XLSX وCSV UTF-8 بعناوين عربية وإنجليزية.
- تصدير كل الأصناف النشطة والمؤرشفة وجميع سجلات الشراء والبيع التاريخية.
- معاينة الملف والتحقق من الصفوف قبل أي كتابة، مع عرض الأخطاء والتنبيهات.
- مطابقة الأصناف بالاسم الموحّد ووحدة القياس فقط، دون الاعتماد على الكود.
- الاستيراد إضافي داخل معاملة SQLite واحدة؛ لا يحذف البيانات ولا يستبدلها.
- لا تتغير بيانات الأصناف الموجودة. يحتاج الصنف الجديد إلى عملية شراء صحيحة واحدة على الأقل.
- يرفض المطابقة مع صنف مؤرشف أو تعارض الأصناف، ويطلب تأكيدًا صريحًا قبل إضافة العمليات المكررة.
- تظل استعادة النسخ الاحتياطية JSON منفصلة دون أي تعديل على سلوكها.
- صفحة دعم عبر WhatsApp والبريد الإلكتروني.

## الأعمدة

Type, Product Name, Unit, Code, Category, Brand, Product Notes, Date, Unit Price, Currency, Quantity, Supplier/Customer, Invoice Number, Entry Notes.

استخدم PURCHASE أو SALE لنوع العملية. العملات المدعومة: YER وSAR وUSD. إذا كانت العملة فارغة، يستخدم التطبيق العملة الافتراضية ويعرض ذلك في المعاينة.

## الصيغ المدعومة

يدعم XLSX وCSV UTF-8. لا تُقرأ ملفات XLS الثنائية القديمة مباشرة؛ افتحها في Excel أو LibreOffice ثم احفظها بصيغة XLSX أو CSV UTF-8. لا يجري التطبيق تحويلًا لأسعار الصرف.

## الفحوص

```bash
python3 tooling/validate_update_package.py
python3 tooling/verify_update_sqlite.py
flutter pub get
dart format lib test
flutter analyze
flutter test --reporter expanded
python3 tool/prepare_android.py
flutter build apk --release
```

يجب اجتياز اختبارات Dart/Flutter وGitHub Actions قبل اعتماد APK للنشر. لم يتغير ترحيل قاعدة البيانات v1-to-v2.
