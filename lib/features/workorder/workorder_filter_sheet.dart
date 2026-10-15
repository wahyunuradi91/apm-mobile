import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../core/widgets/form_fields.dart';
import 'workorder_repository.dart';

/// Nilai filter terpilih — padanan panel filter (filter-panel-card) halaman web.
/// single: `String`, multiple: `Set<String>`, rentang tanggal: `Map` {start, end}.
class WoFilterState {
  final Map<String, Object> values = {};

  WoFilterState copy() => WoFilterState()..values.addAll(values.map((k, v) => MapEntry(k, v is Set ? {...v} : v)));

  int get activeCount => values.length;

  /// Query string sama dengan web: multiple & tanggal dikirim sebagai JSON
  /// (Filter::applyFilter membaca string berawalan '[' / objek JSON).
  Map<String, String> toParams() => values.map((k, v) {
        if (v is Set<String>) return MapEntry(k, jsonEncode(v.toList()));
        if (v is Map) return MapEntry(k, jsonEncode(v));
        return MapEntry(k, v.toString());
      });
}

Future<WoFilterState?> showWorkorderFilterSheet(
  BuildContext context, {
  required List<WoFilterDef> defs,
  required WoFilterState current,
}) {
  return showModalBottomSheet<WoFilterState>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _FilterSheet(defs: defs, state: current.copy()),
  );
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.defs, required this.state});

  final List<WoFilterDef> defs;
  final WoFilterState state;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  static final _fmt = DateFormat('yyyy-MM-dd');

  Map<String, Object> get v => widget.state.values;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.85,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
            child: Row(children: [
              const Text('Filter Workorder', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const Spacer(),
              TextButton(onPressed: () => setState(v.clear), child: const Text('Reset')),
            ]),
          ),
          const Divider(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final d in widget.defs) ...[_field(d), const SizedBox(height: 14)],
              ],
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: FilledButton(
                onPressed: () => Navigator.pop(context, widget.state),
                child: const Text('Terapkan'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(WoFilterDef d) {
    if (d.isDateRange) return _dateRange(d);
    if (d.isMultiple) return _multi(d);

    return Row(children: [
      Expanded(
        child: SearchSelect<String>(
          label: d.label,
          items: [for (final o in d.options) SelectItem(o.key, o.value)],
          value: v[d.paramName] as String?,
          onChanged: (x) => setState(() => v[d.paramName] = x),
        ),
      ),
      if (v.containsKey(d.paramName))
        IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => setState(() => v.remove(d.paramName)),
        ),
    ]);
  }

  Widget _multi(WoFilterDef d) {
    final selected = (v[d.paramName] as Set<String>?) ?? <String>{};
    return InputDecorator(
      decoration: InputDecoration(labelText: d.label),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final o in d.options)
            FilterChip(
              label: Text(o.value, style: const TextStyle(fontSize: 12)),
              selected: selected.contains(o.key),
              selectedColor: ApmColors.primary.withValues(alpha: 0.18),
              onSelected: (on) => setState(() {
                final s = {...selected};
                on ? s.add(o.key) : s.remove(o.key);
                s.isEmpty ? v.remove(d.paramName) : v[d.paramName] = s;
              }),
            ),
        ],
      ),
    );
  }

  Widget _dateRange(WoFilterDef d) {
    final range = (v[d.paramName] as Map<String, String>?) ?? <String, String>{};

    Future<void> pick(String key) async {
      final now = DateTime.now();
      final init = DateTime.tryParse(range[key] ?? '') ?? now;
      final picked = await showDatePicker(
        context: context,
        firstDate: DateTime(now.year - 5),
        lastDate: DateTime(now.year + 2),
        initialDate: init,
      );
      if (picked == null) return;
      setState(() {
        final r = {...range, key: _fmt.format(picked)};
        v[d.paramName] = r;
      });
    }

    return InputDecorator(
      decoration: InputDecoration(labelText: d.label),
      child: Row(children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => pick('start'),
            child: Text(range['start'] ?? 'Mulai'),
          ),
        ),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Text('–')),
        Expanded(
          child: OutlinedButton(
            onPressed: () => pick('end'),
            child: Text(range['end'] ?? 'Selesai'),
          ),
        ),
        if (range.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => setState(() => v.remove(d.paramName)),
          ),
      ]),
    );
  }
}
