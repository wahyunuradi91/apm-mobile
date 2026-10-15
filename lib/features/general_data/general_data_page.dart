import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import 'general_data_repository.dart';

/// General Data — langkah 1: pilih equipment (web: general-logbook.createNotif).
/// Ketik ≥ 3 karakter, pilih equipment, lihat detail & temuan terbuka, lalu buat logbook.
class GeneralDataPage extends ConsumerStatefulWidget {
  const GeneralDataPage({super.key});

  @override
  ConsumerState<GeneralDataPage> createState() => _GeneralDataPageState();
}

class _GeneralDataPageState extends ConsumerState<GeneralDataPage> {
  final _search = TextEditingController();
  Timer? _debounce;
  CancelToken? _cancel;

  List<EquipmentHit> _hits = [];
  bool _loading = false;
  Object? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _cancel?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    setState(() {}); // tombol clear
    _debounce = Timer(const Duration(milliseconds: 300), () => _run(q.trim()));
  }

  Future<void> _run(String q) async {
    _cancel?.cancel();
    if (q.length < 3) {
      setState(() {
        _hits = [];
        _loading = false;
        _error = null;
      });
      return;
    }
    final token = _cancel = CancelToken();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final hits = await ref.read(generalDataRepositoryProvider).searchEquipment(q, cancelToken: token);
      if (mounted && !token.isCancelled) setState(() => _hits = hits);
    } catch (e) {
      if (e is DioException && CancelToken.isCancel(e)) return;
      if (mounted && !token.isCancelled) setState(() => _error = e);
    } finally {
      if (mounted && !token.isCancelled) setState(() => _loading = false);
    }
  }

  Future<void> _openEquipment(EquipmentHit hit) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final create = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _EquipmentSheet(hit: hit),
    );
    if (create == true && mounted) context.push('/general-data/create/${hit.id}');
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.text.trim();
    return Scaffold(
      appBar: AppBar(title: const Text('Create General Data')),
      body: Column(children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: TextField(
            controller: _search,
            onChanged: _onChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Kode, nama, atau deskripsi equipment…',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: q.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _search.clear();
                        _onChanged('');
                      },
                    ),
            ),
          ),
        ),
        if (_loading) const LinearProgressIndicator(minHeight: 2) else const Divider(),
        Expanded(child: _body(q)),
      ]),
    );
  }

  Widget _body(String q) {
    if (_error != null) {
      return _Hint(icon: Icons.cloud_off, text: apiErrorMessage(_error!));
    }
    if (q.length < 3) {
      return const _Hint(
        icon: Icons.precision_manufacturing_outlined,
        text: 'Ketik minimal 3 karakter untuk mencari equipment, lalu pilih untuk membuat logbook.',
      );
    }
    if (_hits.isEmpty) {
      return _loading
          ? const SizedBox.shrink()
          : const _Hint(icon: Icons.search_off, text: 'Equipment tidak ditemukan.');
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _hits.length,
      separatorBuilder: (_, _) => const Divider(indent: 16, endIndent: 16),
      itemBuilder: (_, i) {
        final h = _hits[i];
        return ListTile(
          title: Text(h.name, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: h.description.isEmpty ? null : Text(h.description),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _openEquipment(h),
        );
      },
    );
  }
}

/// Detail equipment + Equipment History (temuan terbuka) seperti panel kanan web.
class _EquipmentSheet extends ConsumerWidget {
  const _EquipmentSheet({required this.hit});

  final EquipmentHit hit;

  static final _date = DateFormat('d MMM yyyy', 'id_ID');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(_equipmentProvider(hit.id));
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, scroll) => Column(children: [
        Expanded(
          child: ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            children: [
              Text(hit.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
              if (hit.description.isNotEmpty)
                Text(hit.description, style: const TextStyle(color: ApmColors.muted)),
              const SizedBox(height: 12),
              ...detail.when(
                loading: () => [
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ],
                error: (e, _) => [Text(apiErrorMessage(e), style: const TextStyle(color: ApmColors.danger))],
                data: (eq) => _details(eq),
              ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: FilledButton.icon(
              onPressed: detail.hasValue ? () => Navigator.pop(context, true) : null,
              icon: const Icon(Icons.edit_note),
              label: const Text('Buat Logbook'),
            ),
          ),
        ),
      ]),
    );
  }

  List<Widget> _details(EquipmentSummary eq) {
    Widget info(IconData icon, String label, String? value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Icon(icon, size: 16, color: ApmColors.primary),
            const SizedBox(width: 8),
            SizedBox(width: 110, child: Text(label, style: const TextStyle(color: ApmColors.muted, fontSize: 13))),
            Expanded(child: Text(value == null || value.isEmpty ? '-' : value, style: const TextStyle(fontSize: 13))),
          ]),
        );

    final history = eq.history;
    return [
      info(Icons.place_outlined, 'Lokasi', eq.location),
      info(Icons.insights_outlined, 'ABC Indicator', eq.abcIndicator),
      const SizedBox(height: 16),
      Row(children: [
        const Text('Temuan terbuka', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(width: 8),
        SoftBadge('${history.length}', color: history.isEmpty ? ApmColors.muted : ApmColors.warning),
      ]),
      const SizedBox(height: 8),
      if (history.isEmpty)
        const Text('Tidak ada temuan terbuka untuk equipment ini.',
            style: TextStyle(color: ApmColors.muted, fontSize: 13)),
      for (final h in history) _HistoryTile(h, _date),
    ];
  }
}

final _equipmentProvider = FutureProvider.autoDispose.family<EquipmentSummary, int>(
  (ref, id) => ref.read(generalDataRepositoryProvider).equipment(id),
);

class _HistoryTile extends StatelessWidget {
  const _HistoryTile(this.h, this.fmt);

  final Map<String, dynamic> h;
  final DateFormat fmt;

  static const _eval = {
    'GOOD': ApmColors.success,
    'CONSIDERABLE': ApmColors.info,
    'WARNING': ApmColors.warning,
    'BAD': ApmColors.secondary,
    'BREAKDOWN': ApmColors.danger,
  };

  @override
  Widget build(BuildContext context) {
    final created = DateTime.tryParse(h['created_at']?.toString() ?? '');
    final eval = h['evaluation']?.toString();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: ApmColors.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SoftBadge(h['no_reg']?.toString() ?? '-', color: ApmColors.info),
          if (h['rtta'] != null) SoftBadge(h['rtta'].toString(), color: ApmColors.muted),
          if (eval != null) SoftBadge('$eval ${h['grade'] ?? ''}'.trim(), color: _eval[eval] ?? ApmColors.muted),
          if (created != null)
            Text(fmt.format(created.toLocal()), style: const TextStyle(color: ApmColors.muted, fontSize: 12)),
        ]),
        const SizedBox(height: 6),
        Text(h['analysis']?.toString() ?? '-', maxLines: 2, overflow: TextOverflow.ellipsis),
        if (h['recommendation'] != null)
          Text('Rekomendasi: ${h['recommendation']}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: ApmColors.muted, fontSize: 12)),
        Text('Notif: ${h['notif'] ?? '-'} · Oleh ${h['created_by'] ?? '-'}',
            style: const TextStyle(color: ApmColors.muted, fontSize: 12)),
      ]),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 44, color: ApmColors.muted),
          const SizedBox(height: 10),
          Text(text, textAlign: TextAlign.center, style: const TextStyle(color: ApmColors.muted)),
        ]),
      ),
    );
  }
}
