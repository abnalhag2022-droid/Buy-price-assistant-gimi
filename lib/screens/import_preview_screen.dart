import 'package:flutter/material.dart';

import '../data/spreadsheet_exchange.dart';
import '../utils/app_helpers.dart';
import '../utils/app_text.dart';
import '../utils/error_messages.dart';

/// Full-page import preview. Nothing is written until the user presses
/// "Import" and every ambiguous product has an explicit decision.
class ImportPreviewScreen extends StatefulWidget {
  const ImportPreviewScreen({super.key, required this.preview, this.exchange});

  final SpreadsheetPreview preview;
  final SpreadsheetExchange? exchange;

  @override
  State<ImportPreviewScreen> createState() => _ImportPreviewScreenState();
}

class _ImportPreviewScreenState extends State<ImportPreviewScreen> {
  static const int _listLimit = 200;

  final Map<int, ImportDecision> _choices = <int, ImportDecision>{};
  ImportPlan? _plan;
  Object? _planError;
  bool _includeDuplicates = false;
  bool _acceptRejected = false;
  bool _importing = false;
  int _planRequest = 0;

  SpreadsheetExchange get _exchange => widget.exchange ?? SpreadsheetExchange.instance;
  SpreadsheetPreview get _preview => widget.preview;

  @override
  void initState() {
    super.initState();
    _refreshPlan();
  }

  Future<void> _refreshPlan() async {
    final request = ++_planRequest;
    try {
      final plan = await _exchange.buildPlan(_preview, _choices);
      if (!mounted || request != _planRequest) return;
      setState(() {
        _plan = plan;
        _planError = null;
      });
    } catch (error) {
      if (!mounted || request != _planRequest) return;
      setState(() => _planError = error);
    }
  }

  void _choose(ImportGroup group, ImportDecision decision) {
    setState(() => _choices[group.id] = decision);
    _refreshPlan();
  }

  void _chooseAll(ImportDecision decision) {
    setState(() {
      for (final g in _preview.groups.where((g) => g.status == ImportGroupStatus.needsDecision)) {
        _choices[g.id] = decision;
      }
    });
    _refreshPlan();
  }

  Future<void> _import() async {
    final plan = _plan;
    if (plan == null || _importing) return;
    final entries = plan.entriesToWrite(includeDuplicates: _includeDuplicates);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: AppText(ar: 'تأكيد الاستيراد', en: 'Confirm import'),
        content: Text(appTextValue(
          'سيُضاف ${plan.productsToCreate} صنف جديد و$entries عملية، ويُلغى أرشفة ${plan.productsToUnarchive.length} صنف. '
              'لن تُعدَّل بيانات الأصناف الموجودة ولن يُحذف أي سجل. ستُحفظ نسخة أمان قبل الكتابة، ويمكن التراجع عن هذا الاستيراد لاحقًا.',
          '${plan.productsToCreate} new products and $entries entries will be added, and ${plan.productsToUnarchive.length} products un-archived. '
              'Existing product details and records are not changed. A safety backup is saved first and this import can be undone later.',
        )),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: AppText(ar: 'إلغاء', en: 'Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true), child: AppText(ar: 'استيراد', en: 'Import')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _importing = true);
    try {
      final decisions = <int, ImportDecision>{..._preview.automaticDecisions, ..._choices};
      final result = await _exchange.importPreview(
        _preview,
        decisions,
        includeDuplicates: _includeDuplicates,
        acceptRejectedRows: _acceptRejected,
      );
      if (mounted) Navigator.of(context).pop(result);
    } catch (error) {
      if (!mounted) return;
      setState(() => _importing = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    final decisionGroups = _preview.groups.where((g) => g.status == ImportGroupStatus.needsDecision).toList();
    final newGroups = _preview.groups.where((g) => g.status == ImportGroupStatus.newProduct).toList();
    final matchedGroups = _preview.groups.where((g) => g.status == ImportGroupStatus.matched).toList();
    final rejected = _preview.rejectedRows;
    final canImport = plan != null &&
        plan.canImport(acceptRejectedRows: _acceptRejected, includeDuplicates: _includeDuplicates);
    return Scaffold(
      appBar: AppBar(
        title: AppText(ar: 'معاينة الاستيراد', en: 'Import preview'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text(ltrIsolate(_preview.fileName), maxLines: 2, overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          _SummaryCard(preview: _preview, plan: plan, includeDuplicates: _includeDuplicates),
          if (_planError != null) _Notice(text: friendlyError(_planError!), isError: true),
          for (final issue in _preview.parsed.fileIssues) _Notice(text: issue.message, isError: issue.isError),
          if (decisionGroups.isNotEmpty) ...[
            _SectionTitle(
              ar: 'أصناف تحتاج إلى قرار (${decisionGroups.length})',
              en: 'Products that need a decision (${decisionGroups.length})',
            ),
            AppText(
              ar: 'لم تُطابَق هذه الأصناف تلقائيًا لأن الاسم أو الكود أو ترتيب الكلمات لا يطابق صنفًا واحدًا بدقة. اختر لكل صنف: ربطه بصنف موجود، أو إنشاء صنف جديد، أو تخطيه.',
              en: 'These were not matched automatically because the name, code, or word order does not identify exactly one product. Choose for each: link to an existing product, create a new one, or skip it.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 4, children: [
              OutlinedButton(
                onPressed: () => _chooseAll(const ImportDecision.createNew()),
                child: AppText(ar: 'إنشاء الكل كأصناف جديدة', en: 'Create all as new'),
              ),
              OutlinedButton(
                onPressed: () => _chooseAll(const ImportDecision.skip()),
                child: AppText(ar: 'تخطي الكل', en: 'Skip all'),
              ),
            ]),
            for (final g in decisionGroups.take(_listLimit))
              _DecisionCard(group: g, choice: _choices[g.id], onChoose: (d) => _choose(g, d)),
            if (decisionGroups.length > _listLimit) _MoreLine(count: decisionGroups.length - _listLimit),
          ],
          if (newGroups.isNotEmpty)
            _GroupList(
              titleAr: 'أصناف جديدة ستُنشأ (${newGroups.length})',
              titleEn: 'New products to create (${newGroups.length})',
              groups: newGroups,
              limit: _listLimit,
              describe: (g) => _rowCounts(g),
            ),
          if (matchedGroups.isNotEmpty)
            _GroupList(
              titleAr: 'أصناف مطابقة بدقة (${matchedGroups.length})',
              titleEn: 'Exactly matched products (${matchedGroups.length})',
              groups: matchedGroups,
              limit: _listLimit,
              describe: (g) => '${_rowCounts(g)} · ${appTextValue('تُضاف سجلاتها إلى الصنف الموجود بالاسم نفسه', 'records go to the existing product with the same name')}',
            ),
          if (plan != null && plan.duplicateCount > 0) ...[
            _SectionTitle(ar: 'عمليات مكررة (${plan.duplicateCount})', en: 'Duplicate entries (${plan.duplicateCount})'),
            for (final e in plan.entries.where((e) => e.isDuplicate).take(_listLimit))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.content_copy_outlined, size: 20),
                title: Text('${appTextValue('صف', 'Row')} ${e.record.line}: ${e.group.name}'),
                subtitle: Text(
                  '${e.record.date} · ${formatMoney(e.record.price)} ${e.record.currency} · ${appTextValue(e.duplicateInDatabase ? 'موجودة مسبقًا' : 'مكررة داخل الملف', e.duplicateInDatabase ? 'already recorded' : 'repeated in file')}',
                ),
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _includeDuplicates,
              onChanged: (v) => setState(() => _includeDuplicates = v),
              title: AppText(ar: 'إضافة العمليات المكررة رغم ذلك', en: 'Add duplicate entries anyway'),
              subtitle: AppText(
                ar: 'الافتراضي تخطيها، فإعادة استيراد الملف نفسه لا تكرر السجلات.',
                en: 'Skipped by default, so re-importing the same file adds nothing twice.',
              ),
            ),
          ],
          if (rejected.isNotEmpty) ...[
            _SectionTitle(ar: 'صفوف مرفوضة (${rejected.length})', en: 'Rejected rows (${rejected.length})'),
            for (final r in rejected.take(_listLimit))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error, size: 20),
                title: Text('${appTextValue('صف', 'Row')} ${r.line}${r.name.isEmpty ? '' : ': ${r.name}'}'),
                subtitle: Text(r.errors.join('\n')),
              ),
            if (rejected.length > _listLimit) _MoreLine(count: rejected.length - _listLimit),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _acceptRejected,
              onChanged: (v) => setState(() => _acceptRejected = v ?? false),
              title: AppText(
                ar: 'استيراد الصفوف الصحيحة فقط وتجاهل الصفوف المرفوضة',
                en: 'Import valid rows only and ignore rejected rows',
              ),
            ),
          ],
          const SizedBox(height: 80),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (plan != null && !canImport)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(_blockingReason(plan), style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
              ),
            FilledButton.icon(
              onPressed: canImport && !_importing ? _import : null,
              icon: _importing
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.download_done_outlined),
              label: AppText(ar: _importing ? 'جارٍ الاستيراد...' : 'استيراد', en: _importing ? 'Importing...' : 'Import'),
            ),
          ]),
        ),
      ),
    );
  }

  String _rowCounts(ImportGroup g) => appTextValue(
        '${g.unit} · شراء ${g.purchaseCount} · بيع ${g.saleCount}',
        '${g.unit} · ${g.purchaseCount} purchases · ${g.saleCount} sales',
      );

  String _blockingReason(ImportPlan plan) {
    if (_preview.fileErrors.isNotEmpty) {
      return appTextValue('صحّح أخطاء الملف المذكورة أعلاه ثم أعد المعاينة.', 'Fix the file errors above and preview again.');
    }
    if (plan.undecidedGroups.isNotEmpty) {
      return appTextValue('بقي ${plan.undecidedGroups.length} صنف دون قرار.', '${plan.undecidedGroups.length} products still need a decision.');
    }
    if (_preview.rejectedRows.isNotEmpty && !_acceptRejected) {
      return appTextValue('وافق على تجاهل الصفوف المرفوضة أو صحّحها في الملف.', 'Accept ignoring rejected rows or fix them in the file.');
    }
    return appTextValue('لا يوجد ما يُستورد.', 'Nothing to import.');
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.preview, required this.plan, required this.includeDuplicates});
  final SpreadsheetPreview preview;
  final ImportPlan? plan;
  final bool includeDuplicates;

  @override
  Widget build(BuildContext context) {
    final p = plan;
    Widget line(String ar, String en, Object value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Expanded(child: AppText(ar: ar, en: en)),
            Text('$value', style: const TextStyle(fontWeight: FontWeight.w700)),
          ]),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          line('صفوف البيانات', 'Data rows', preview.rows.length),
          line('أصناف جديدة', 'New products', preview.newProducts),
          line('أصناف مطابقة بدقة', 'Exact matches', preview.matchedProducts),
          line('أصناف تحتاج إلى قرار', 'Need a decision', p == null ? preview.decisionsNeeded : p.undecidedGroups.length),
          line('عمليات ستُضاف', 'Entries to add', p == null ? '…' : p.entriesToWrite(includeDuplicates: includeDuplicates)),
          line('عمليات مكررة', 'Duplicates', p == null ? '…' : p.duplicateCount),
          line('صفوف مرفوضة', 'Rejected rows', preview.rejectedRows.length),
        ]),
      ),
    );
  }
}

class _DecisionCard extends StatelessWidget {
  const _DecisionCard({required this.group, required this.choice, required this.onChoose});
  final ImportGroup group;
  final ImportDecision? choice;
  final ValueChanged<ImportDecision> onChoose;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    Widget option({required ImportDecision decision, required Widget title, Widget? subtitle}) {
      final selected = choice == decision;
      return ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        leading: Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
            color: selected ? colors.primary : colors.outline),
        title: title,
        subtitle: subtitle,
        selected: selected,
        onTap: () => onChoose(decision),
      );
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(group.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 2),
          Text(appTextValue(
            'في الملف: ${group.unit}${group.code == null ? '' : ' · كود ${ltrIsolate(group.code!)}'} · شراء ${group.purchaseCount} · بيع ${group.saleCount}',
            'In file: ${group.unit}${group.code == null ? '' : ' · code ${group.code}'} · ${group.purchaseCount} purchases · ${group.saleCount} sales',
          ), style: Theme.of(context).textTheme.bodySmall),
          for (final n in group.notices)
            Padding(padding: const EdgeInsets.only(top: 4), child: Text(n, style: Theme.of(context).textTheme.bodySmall)),
          const Divider(),
          for (final c in group.candidates)
            option(
              decision: ImportDecision.link(c.productId),
              title: Text(appTextValue(
                'ربط بالصنف «${c.name}»${c.archived ? ' (مؤرشف — ستُلغى أرشفته)' : ''}',
                'Link to “${c.name}”${c.archived ? ' (archived — will be un-archived)' : ''}',
              )),
              subtitle: Text([
                _reasonText(c.reasons),
                ...c.differences,
              ].join('\n')),
            ),
          option(
            decision: const ImportDecision.createNew(),
            title: AppText(ar: 'إنشاء صنف جديد بهذا الاسم', en: 'Create a new product with this name'),
          ),
          option(
            decision: const ImportDecision.skip(),
            title: AppText(
              ar: 'تخطي هذا الصنف (${group.rows.length} صف)',
              en: 'Skip this product (${group.rows.length} rows)',
            ),
          ),
        ]),
      ),
    );
  }

  String _reasonText(Set<CandidateReason> reasons) {
    final parts = <String>[
      if (reasons.contains(CandidateReason.sameCode)) appTextValue('الكود نفسه', 'same code'),
      if (reasons.contains(CandidateReason.sameName)) appTextValue('الاسم نفسه', 'same name'),
      if (reasons.contains(CandidateReason.reorderedName))
        appTextValue('الكلمات نفسها بترتيب مختلف — تحقق من الأرقام والمقاسات', 'same words in a different order — check numbers and sizes'),
    ];
    return parts.join(' · ');
  }
}

class _GroupList extends StatelessWidget {
  const _GroupList({required this.titleAr, required this.titleEn, required this.groups, required this.limit, required this.describe});
  final String titleAr, titleEn;
  final List<ImportGroup> groups;
  final int limit;
  final String Function(ImportGroup group) describe;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(top: 12),
        child: ExpansionTile(
          title: AppText(ar: titleAr, en: titleEn, style: const TextStyle(fontWeight: FontWeight.w700)),
          children: [
            for (final g in groups.take(limit))
              ListTile(
                dense: true,
                title: Text(g.name),
                subtitle: Text([describe(g), ...g.notices].join('\n')),
              ),
            if (groups.length > limit) _MoreLine(count: groups.length - limit),
          ],
        ),
      );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.ar, required this.en});
  final String ar, en;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 6),
        child: AppText(ar: ar, en: en, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
      );
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, required this.isError});
  final String text;
  final bool isError;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isError ? colors.errorContainer : colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(isError ? Icons.error_outline : Icons.info_outline, size: 20,
            color: isError ? colors.onErrorContainer : colors.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: TextStyle(color: isError ? colors.onErrorContainer : null))),
      ]),
    );
  }
}

class _MoreLine extends StatelessWidget {
  const _MoreLine({required this.count});
  final int count;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(8),
        child: AppText(ar: 'و$count أخرى غير معروضة.', en: '$count more not shown.', style: Theme.of(context).textTheme.bodySmall),
      );
}
