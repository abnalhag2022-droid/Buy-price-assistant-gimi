import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../utils/app_helpers.dart';
import '../../utils/app_text.dart';
import '../tokens.dart';

/// Number input that accepts Latin and Arabic-Indic digits and Arabic or
/// Latin separators, and validates the parsed value.
class AmountField extends StatelessWidget {
  const AmountField({
    super.key,
    required this.controller,
    required this.label,
    this.suffixText,
    this.helperText,
    this.mustBePositive = false,
    this.onChanged,
    this.textInputAction = TextInputAction.next,
  });

  final TextEditingController controller;
  final String label;
  final String? suffixText;
  final String? helperText;

  /// Quantities must be > 0; prices may be 0 but never negative.
  final bool mustBePositive;
  final ValueChanged<String>? onChanged;
  final TextInputAction textInputAction;

  String? _validate(String? value) {
    final parsed = parseLocalizedNumber(value ?? '');
    if (parsed == null) return appTextValue('أدخل رقمًا صحيحًا، مثل 1250 أو 12.5', 'Enter a number, e.g. 1250 or 12.5');
    if (mustBePositive && parsed <= 0) {
      return appTextValue('يجب أن تكون القيمة أكبر من صفر.', 'The value must be greater than zero.');
    }
    if (parsed < 0) return appTextValue('لا يمكن أن تكون القيمة سالبة.', 'The value cannot be negative.');
    return null;
  }

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textInputAction: textInputAction,
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9٠-٩۰-۹.,٫٬]'))],
        decoration: InputDecoration(labelText: label, suffixText: suffixText, helperText: helperText),
        validator: _validate,
        onChanged: onChanged,
      );
}

/// Search box that reports changes after the user pauses typing, so a fast
/// typist does not start one database query per key press.
class DebouncedSearchField extends StatefulWidget {
  const DebouncedSearchField({super.key, required this.onChanged, required this.hintText, this.controller});

  final ValueChanged<String> onChanged;
  final String hintText;
  final TextEditingController? controller;

  @override
  State<DebouncedSearchField> createState() => _DebouncedSearchFieldState();
}

class _DebouncedSearchFieldState extends State<DebouncedSearchField> {
  late final TextEditingController _controller = widget.controller ?? TextEditingController();
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  void _changed(String value) {
    _timer?.cancel();
    _timer = Timer(AppDurations.searchDebounce, () => widget.onChanged(value));
    setState(() {});
  }

  void _clear() {
    _timer?.cancel();
    _controller.clear();
    setState(() {});
    widget.onChanged('');
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: _controller,
        onChanged: _changed,
        onSubmitted: (value) {
          _timer?.cancel();
          widget.onChanged(value);
        },
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: widget.hintText,
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _controller.text.isEmpty
              ? null
              : IconButton(
                  tooltip: appTextValue('مسح البحث', 'Clear search'),
                  onPressed: _clear,
                  icon: const Icon(Icons.close),
                ),
        ),
      );
}

/// Centres screen content and caps its width on tablets and landscape.
class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Sizes.maxContentWidth),
          child: child,
        ),
      );
}

class ChoiceOption<T> {
  const ChoiceOption({required this.value, required this.label, this.subtitle});
  final T value;
  final String label;
  final String? subtitle;
}

/// Vertical single-choice list for options whose labels are too long for a
/// segmented button on small phones.
class ChoiceList<T> extends StatelessWidget {
  const ChoiceList({super.key, required this.options, required this.selected, required this.onChanged});

  final List<ChoiceOption<T>> options;
  final T? selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(children: [
      for (final option in options)
        Semantics(
          inMutuallyExclusiveGroup: true,
          checked: option.value == selected,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: Space.xs),
            leading: Icon(
              option.value == selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              color: option.value == selected ? colors.primary : colors.outline,
            ),
            title: Text(option.label),
            subtitle: option.subtitle == null ? null : Text(option.subtitle!),
            selected: option.value == selected,
            onTap: () => onChanged(option.value),
          ),
        ),
    ]);
  }
}
