import 'package:flutter/material.dart';

import '../theme.dart';

/// Pilihan generik untuk SearchSelect.
class SelectItem<T> {
  const SelectItem(this.value, this.label);

  final T value;
  final String label;
}

/// Pengganti Multiselect/SelectInput web: field yang membuka bottom sheet ber-search.
class SearchSelect<T> extends StatelessWidget {
  const SearchSelect({
    super.key,
    required this.label,
    required this.items,
    required this.value,
    required this.onChanged,
    this.required = false,
    this.enabled = true,
    this.errorText,
    this.hint,
  });

  final String label;
  final List<SelectItem<T>> items;
  final T? value;
  final ValueChanged<T> onChanged;
  final bool required;
  final bool enabled;
  final String? errorText;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final selected = items.where((i) => i.value == value).firstOrNull;
    return InkWell(
      onTap: enabled ? () => _open(context) : null,
      child: InputDecorator(
        isEmpty: selected == null,
        decoration: InputDecoration(
          labelText: required ? '$label *' : label,
          hintText: hint ?? 'Pilih…',
          errorText: errorText,
          enabled: enabled,
          suffixIcon: const Icon(Icons.arrow_drop_down),
        ),
        child: selected == null
            ? null
            : Text(selected.label, maxLines: 2, overflow: TextOverflow.ellipsis),
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    // Lepas fokus field teks dulu — kalau tidak, Flutter mengembalikan fokus (dan
    // keyboard) ke field terakhir begitu sheet ditutup.
    FocusManager.instance.primaryFocus?.unfocus();
    final picked = await showModalBottomSheet<SelectItem<T>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _SelectSheet<T>(title: label, items: items, selected: value),
    );
    if (picked != null) onChanged(picked.value);
  }
}

class _SelectSheet<T> extends StatefulWidget {
  const _SelectSheet({required this.title, required this.items, this.selected});

  final String title;
  final List<SelectItem<T>> items;
  final T? selected;

  @override
  State<_SelectSheet<T>> createState() => _SelectSheetState<T>();
}

class _SelectSheetState<T> extends State<_SelectSheet<T>> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.items
        .where((i) => i.label.toLowerCase().contains(_q.toLowerCase()))
        .toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(widget.title,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            ),
            if (widget.items.length > 7)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'Cari…',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (v) => setState(() => _q = v),
                ),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.separated(
                itemCount: filtered.length,
                separatorBuilder: (_, _) => const Divider(),
                itemBuilder: (_, i) {
                  final item = filtered[i];
                  final isSel = item.value == widget.selected;
                  return ListTile(
                    title: Text(item.label),
                    trailing: isSel ? const Icon(Icons.check, color: ApmColors.primary) : null,
                    onTap: () => Navigator.pop(context, item),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// TextField yang menyimpan nilai ke model tanpa controller eksternal.
class ModelTextField extends StatefulWidget {
  const ModelTextField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.required = false,
    this.enabled = true,
    this.maxLines = 1,
    this.keyboardType,
    this.errorText,
  });

  final String label;
  final String? value;
  final ValueChanged<String> onChanged;
  final bool required;
  final bool enabled;
  final int maxLines;
  final TextInputType? keyboardType;
  final String? errorText;

  @override
  State<ModelTextField> createState() => _ModelTextFieldState();
}

class _ModelTextFieldState extends State<ModelTextField> {
  late final TextEditingController _c = TextEditingController(text: widget.value ?? '');

  @override
  void didUpdateWidget(ModelTextField old) {
    super.didUpdateWidget(old);
    // Nilai diubah dari luar (mis. onParameterSelected mengisi method/unit).
    if ((widget.value ?? '') != _c.text) _c.text = widget.value ?? '';
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _c,
      enabled: widget.enabled,
      maxLines: widget.maxLines,
      minLines: 1,
      keyboardType: widget.keyboardType,
      onChanged: widget.onChanged,
      decoration: InputDecoration(
        labelText: widget.required ? '${widget.label} *' : widget.label,
        errorText: widget.errorText,
      ),
    );
  }
}

/// Pemilih tanggal + jam (format web: yyyy-MM-dd HH:mm), maksimal besok seperti web.
class DateTimeField extends StatelessWidget {
  const DateTimeField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    required this.format,
    this.required = false,
    this.enabled = true,
    this.minDate,
    this.errorText,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime> onChanged;
  final String Function(DateTime) format;
  final bool required;
  final bool enabled;
  final DateTime? minDate;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? () => _pick(context) : null,
      child: InputDecorator(
        isEmpty: value == null,
        decoration: InputDecoration(
          labelText: required ? '$label *' : label,
          errorText: errorText,
          enabled: enabled,
          suffixIcon: const Icon(Icons.event),
        ),
        child: value == null ? null : Text(format(value!)),
      ),
    );
  }

  Future<void> _pick(BuildContext context) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final now = DateTime.now();
    final last = DateTime(now.year, now.month, now.day + 1, 23, 59);
    final first = minDate ?? DateTime(now.year - 2);
    final init = value ?? (minDate != null && minDate!.isAfter(now) ? minDate! : now);
    final d = await showDatePicker(
      context: context,
      firstDate: DateTime(first.year, first.month, first.day),
      lastDate: last,
      initialDate: init.isAfter(last) ? last : (init.isBefore(first) ? first : init),
    );
    if (d == null || !context.mounted) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(init));
    if (t == null) return;
    onChanged(DateTime(d.year, d.month, d.day, t.hour, t.minute));
  }
}

/// Pilihan sedikit (≤ ~5) sebagai chip sekali-tap — pengganti dropdown agar tidak
/// perlu membuka sheet. [colors] opsional per nilai (mis. warna Evaluation).
class ChipChoice<T> extends StatelessWidget {
  const ChipChoice({
    super.key,
    required this.label,
    required this.items,
    required this.value,
    required this.onChanged,
    this.required = false,
    this.enabled = true,
    this.errorText,
    this.colors = const {},
  });

  final String label;
  final List<SelectItem<T>> items;
  final T? value;
  final ValueChanged<T> onChanged;
  final bool required;
  final bool enabled;
  final String? errorText;
  final Map<T, Color> colors;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(required ? '$label *' : label,
            style: const TextStyle(fontSize: 12, color: ApmColors.muted)),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final i in items)
              ChoiceChip(
                label: Text(i.label),
                selected: i.value == value,
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
                labelStyle: TextStyle(
                  fontSize: 13,
                  fontWeight: i.value == value ? FontWeight.w600 : FontWeight.w400,
                  color: i.value == value ? (colors[i.value] ?? ApmColors.primary) : ApmColors.dark,
                ),
                selectedColor: (colors[i.value] ?? ApmColors.primary).withValues(alpha: 0.15),
                side: BorderSide(
                  color: i.value == value
                      ? (colors[i.value] ?? ApmColors.primary)
                      : const Color(0xFFCED4DA),
                ),
                onSelected: enabled
                    ? (_) {
                        FocusManager.instance.primaryFocus?.unfocus();
                        onChanged(i.value);
                      }
                    : null,
              ),
          ],
        ),
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(errorText!, style: const TextStyle(color: ApmColors.danger, fontSize: 12)),
          ),
      ],
    );
  }
}
