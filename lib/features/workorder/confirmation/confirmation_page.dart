import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_client.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/attachment_picker.dart';
import '../../../core/widgets/form_fields.dart';
import 'confirmation_form.dart';
import 'confirmation_repository.dart';

/// Report (Confirmation) Workorder per operation — padanan halaman web
/// Workorder/ConfirmationWorkorder/Index.vue.
class ConfirmationPage extends ConsumerStatefulWidget {
  const ConfirmationPage({super.key, required this.workOrder, required this.operationId});

  final String workOrder;
  final String operationId;

  @override
  ConsumerState<ConfirmationPage> createState() => _ConfirmationPageState();
}

class _ConfirmationPageState extends ConsumerState<ConfirmationPage> {
  ConfirmationForm? _f;
  Object? _loadError;
  bool _saving = false;
  final List<AttachmentFile> _files = [];
  Map<String, List<String>> _errors = {};

  /// Item yang sedang dibuka (accordion: satu item terbuka).
  ItemParamRow? _open;
  final Map<ItemParamRow, GlobalKey> _itemKeys = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loadError = null;
      _f = null;
    });
    try {
      final f = await ref.read(confirmationRepositoryProvider).load(widget.workOrder, widget.operationId);
      if (!mounted) return;
      setState(() {
        _f = f;
        // Form 1 item (korektif) langsung dibuka; banyak item cukup daftar ringkas.
        if (f.items.length == 1) _open = f.items.first;
      });
      _fetchDescriptions(); // web: dipanggil di mounted + watcher classification
    } catch (e) {
      if (mounted) setState(() => _loadError = e);
    }
  }

  Future<void> _fetchDescriptions() async {
    final id = _f?.classificationId;
    if (id == null) return;
    try {
      final d = await ref.read(confirmationRepositoryProvider).evaluationDescriptions(id);
      if (mounted) setState(() => _f!.evaluationDescriptions = d);
    } catch (_) {
      // Web: fallback ke deskripsi yang sudah ada / hardcoded.
    }
  }

  bool get _readOnly => !(_f?.canReport ?? false) || !(_f?.canReportOperation ?? false);

  String? _err(String key) => _errors[key]?.first;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Report WO ${widget.workOrder}')),
      body: _buildBody(),
      bottomNavigationBar: _f == null || _readOnly ? null : _buildActions(),
    );
  }

  Widget _buildBody() {
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(apiErrorMessage(_loadError!), textAlign: TextAlign.center),
            TextButton(onPressed: _load, child: const Text('Coba lagi')),
          ]),
        ),
      );
    }
    final f = _f;
    if (f == null) return const Center(child: CircularProgressIndicator());

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        ..._banners(f),
        _HeaderCard(f),
        const SizedBox(height: 16),
        _section('Data Report', _mainFields(f)),
        if (f.executed) ...[
          const SizedBox(height: 16),
          _section(
            'Item Parameter',
            _itemParams(f),
            subtitle: '${f.items.where((r) => r.isComplete).length}/${f.items.length} lengkap',
            action: _readOnly
                ? null
                : Row(mainAxisSize: MainAxisSize.min, children: [
                    if (f.items.length > 1)
                      IconButton(
                        tooltip: 'Isi massal',
                        icon: const Icon(Icons.playlist_add_check),
                        onPressed: () => _bulkFill(f),
                      ),
                    IconButton(
                      tooltip: 'Tambah item',
                      icon: const Icon(Icons.add),
                      onPressed: () => setState(() {
                        final row = ItemParamRow()..editInfo = true;
                        f.items.add(row);
                        _open = row;
                      }),
                    ),
                  ]),
          ),
          const SizedBox(height: 16),
          _section('Confirmation Personil', _personel(f),
              action: _readOnly
                  ? null
                  : TextButton.icon(
                      onPressed: () => setState(() => f.personel.add(PersonelRow())),
                      icon: const Icon(Icons.add),
                      label: const Text('Tambah'),
                    )),
        ],
      ],
    );
  }

  // ---------------- banner ----------------
  List<Widget> _banners(ConfirmationForm f) {
    final out = <Widget>[];
    void add(String text, Color color, IconData icon) {
      out
        ..add(_Alert(text: text, color: color, icon: icon))
        ..add(const SizedBox(height: 12));
    }

    if (!f.canReport) {
      add('Anda tidak memiliki izin "report workorder" — form hanya bisa dilihat.', ApmColors.info,
          Icons.lock_outline);
    } else if (!f.canReportOperation) {
      add('Operation ini bukan milik PIC Anda — form hanya bisa dilihat.', ApmColors.info,
          Icons.lock_outline);
    }
    if (f.isUnsafe) {
      add('WO ini berasal dari laporan Unsafe Condition (e-Posh). Foto setelah perbaikan wajib dilampirkan.',
          ApmColors.danger, Icons.warning_amber);
    }
    final rev = f.eposhRevision;
    if (rev != null) {
      add(
          'Revisi dari e-Posh: ${rev['note'] ?? '-'}'
          '${rev['awaitingEvidence'] == true ? '\nTambahkan foto setelah perbaikan.' : ''}',
          ApmColors.warning,
          Icons.history);
    }
    if (f.parkedEposhPhotos.isNotEmpty) {
      add('Ada ${f.parkedEposhPhotos.length} foto setelah perbaikan dari e-Posh yang akan dilampirkan otomatis.',
          ApmColors.info, Icons.photo_library_outlined);
    }
    if (_errors.isNotEmpty) {
      add('Periksa kembali isian yang ditandai merah.', ApmColors.danger, Icons.error_outline);
    }
    return out;
  }

  // ---------------- data utama ----------------
  List<Widget> _mainFields(ConfirmationForm f) {
    final mainWorkCenterMissing = (f.equipment['main_work_center'] ?? '').toString().isEmpty;
    final photoMissing = f.executed && f.isUnsafe && !f.hasRequiredPhoto('append', _fileNames);

    return [
      DateTimeField(
        label: 'Tanggal',
        required: true,
        enabled: !_readOnly,
        value: f.date,
        format: formatDateTime,
        errorText: _err('date'),
        onChanged: (d) => setState(() => f.date = d),
      ),
      if (f.form['isAJG'] == true)
        ModelTextField(
          label: 'No Work Order',
          value: f.workOrder,
          enabled: !_readOnly,
          onChanged: (v) => f.workOrder = v,
        ),
      _attachmentsField(f),
      SearchSelect<int>(
        label: 'Executor',
        required: true,
        enabled: !_readOnly,
        items: [for (final o in f.executorOptions) SelectItem(o.value as int, o.label)],
        value: f.executorId,
        errorText: _err('executor_id'),
        onChanged: (v) => setState(() => f.executorId = v),
      ),
      if (mainWorkCenterMissing)
        const Text(
          'Equipment tersebut tidak memiliki Main Work Center. Hubungi helpdesk APM!',
          style: TextStyle(color: ApmColors.danger, fontSize: 12),
        ),
      SearchSelect<int>(
        label: 'Classification',
        required: true,
        enabled: !_readOnly,
        items: [for (final o in f.classificationOptions) SelectItem(o.value as int, o.label)],
        value: f.classificationId,
        errorText: _err('classification_id'),
        onChanged: (v) {
          setState(() => f.classificationId = v);
          _fetchDescriptions();
        },
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Not Executed'),
        subtitle: const Text('Aktifkan jika WO tidak dikerjakan'),
        value: !f.executed,
        onChanged: _readOnly ? null : (v) => setState(() => f.executed = !v),
      ),
      if (!f.executed)
        ModelTextField(
          label: 'Alasan tidak dikerjakan',
          required: true,
          maxLines: 3,
          enabled: !_readOnly,
          value: f.reasonNotExecuted,
          errorText: _err('reason_not_executed'),
          onChanged: (v) => f.reasonNotExecuted = v,
        ),
      if (photoMissing)
        const Text('Foto setelah perbaikan wajib — akan dikirim ke e-Posh',
            style: TextStyle(color: ApmColors.danger, fontSize: 12))
      else if (f.parkedEposhPhotos.isNotEmpty && f.executed)
        Text('${f.parkedEposhPhotos.length} foto dari e-Posh sudah tersedia',
            style: const TextStyle(color: ApmColors.success, fontSize: 12)),
    ];
  }

  List<String> get _fileNames => _files.map((e) => e.name).toList();

  Widget _attachmentsField(ConfirmationForm f) {
    return AttachmentPicker(
      files: _files,
      onChanged: () => setState(() {}),
      required: f.isUnsafe && f.parkedEposhPhotos.isEmpty,
      enabled: !_readOnly,
      errorText: _err('file'),
      helper: f.attachments.isEmpty
          ? null
          : Text('${f.attachments.length} lampiran tersimpan',
              style: const TextStyle(color: ApmColors.muted, fontSize: 12)),
    );
  }

  // ---------------- item parameter ----------------
  List<Widget> _itemParams(ConfirmationForm f) {
    final params = f.itemParameterType;
    return [
      for (final (i, row) in f.items.indexed)
        _ItemTile(
          key: _itemKeys.putIfAbsent(row, GlobalKey.new),
          index: i,
          row: row,
          form: f,
          readOnly: _readOnly,
          expanded: identical(_open, row),
          hasError: _errors.keys.any((k) => k.startsWith('item_parameter.$i.')),
          parameterOptions: [
            for (final p in params) SelectItem(p['value'].toString(), p['label'].toString()),
          ],
          canDelete: f.items.length > 1 && !(row.id != null && f.reportedItemIds.contains(row.id)),
          err: (k) => _err('item_parameter.$i.$k'),
          onToggle: () => _openItem(identical(_open, row) ? null : row),
          onChanged: () => setState(f.recalcGrades),
          onDelete: () => setState(() {
            f.items.removeAt(i);
            _itemKeys.remove(row);
          }),
          onNext: () {
            // Lanjut ke item berikutnya yang belum lengkap; tutup bila semua lengkap.
            final rest = [...f.items.skip(i + 1), ...f.items.take(i)];
            _openItem(rest.where((r) => !r.isComplete).firstOrNull);
          },
        ),
    ];
  }

  void _openItem(ItemParamRow? row) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _open = row);
    if (row == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _itemKeys[row]?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 250), alignment: 0.05);
      }
    });
  }

  /// Isi field yang sama untuk banyak item sekaligus (mis. semua Comply + GOOD).
  Future<void> _bulkFill(ConfirmationForm f) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final hasilOptions = {for (final r in f.items.where((r) => r.isOption)) ...r.unitOptions}.toList();
    final result = await showModalBottomSheet<_BulkFill>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _BulkFillSheet(form: f, hasilOptions: hasilOptions),
    );
    if (result == null) return;
    bool canSet(String? current) => !result.onlyEmpty || current == null || current.trim().isEmpty;
    var touched = 0;
    setState(() {
      for (final r in f.items) {
        var changed = false;
        if (result.hasil != null &&
            r.isOption &&
            r.unitOptions.contains(result.hasil) &&
            canSet(r.unitSelected)) {
          r.unitSelected = result.hasil;
          changed = true;
        }
        if (result.evaluation != null && canSet(r.evaluation)) {
          r.evaluation = result.evaluation;
          changed = true;
        }
        if (result.analysis != null && canSet(r.analysis)) {
          r.analysis = result.analysis;
          changed = true;
        }
        if (changed) touched++;
      }
      f.recalcGrades();
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$touched item diperbarui.')));
    }
  }

  // ---------------- personil ----------------
  List<Widget> _personel(ConfirmationForm f) {
    if (f.personel.isEmpty) {
      return [const Text('Belum ada personil.', style: TextStyle(color: ApmColors.muted))];
    }
    return [
      for (final (i, p) in f.personel.indexed)
        Card(
          key: ObjectKey(p),
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  Text('Personil ${i + 1}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  const Spacer(),
                  if (!_readOnly)
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: ApmColors.danger),
                      onPressed: () => setState(() => f.personel.removeAt(i)),
                    ),
                ]),
                SearchSelect<int>(
                  label: 'Personel',
                  required: true,
                  enabled: !_readOnly,
                  items: [for (final o in f.personelOptions) SelectItem(o.value as int, o.label)],
                  value: p.personel,
                  errorText: _err('personel_workorder.$i.personel'),
                  onChanged: (v) => setState(() => p.personel = v),
                ),
                const SizedBox(height: 10),
                ChipChoice<String>(
                  label: 'Shift',
                  required: true,
                  enabled: !_readOnly,
                  items: [for (final o in f.shiftOptions) SelectItem(o.value.toString(), o.label)],
                  value: p.shift,
                  errorText: _err('personel_workorder.$i.shift'),
                  onChanged: (v) => setState(() => p.shift = v),
                ),
                const SizedBox(height: 10),
                DateTimeField(
                  label: 'Start Date',
                  required: true,
                  enabled: !_readOnly,
                  value: p.startDate,
                  format: formatDateTime,
                  errorText: _err('personel_workorder.$i.start_date'),
                  onChanged: (d) => setState(() => p.startDate = d),
                ),
                const SizedBox(height: 10),
                DateTimeField(
                  label: 'Finish Date',
                  required: true,
                  enabled: !_readOnly,
                  value: p.finishDate,
                  minDate: p.startDate,
                  format: formatDateTime,
                  errorText: _err('personel_workorder.$i.finish_date'),
                  onChanged: (d) => setState(() => p.finishDate = d),
                ),
                const SizedBox(height: 10),
                ModelTextField(
                  label: 'Note',
                  maxLines: 3,
                  enabled: !_readOnly,
                  value: p.note,
                  onChanged: (v) => p.note = v,
                ),
              ],
            ),
          ),
        ),
    ];
  }

  // ---------------- simpan ----------------
  Widget _buildActions() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(children: [
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
              onPressed: _saving ? null : () => _submit(isFinal: false),
              child: const Text('Temp. Save'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              onPressed: _saving ? null : () => _submit(isFinal: true),
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Save'),
            ),
          ),
        ]),
      ),
    );
  }

  /// Urutan cek sama dengan web submit() :1328.
  Future<void> _submit({required bool isFinal}) async {
    final f = _f!;
    if (!f.executed && (f.reasonNotExecuted?.trim().isEmpty ?? true)) {
      return _alert('Alasan wajib diisi', 'Isi alasan mengapa WO tidak dikerjakan.');
    }

    var mode = 'append';
    if (f.executed && _files.isNotEmpty && f.attachments.isNotEmpty) {
      final picked = await showDialog<String>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Lampiran sudah ada'),
          content: Text('Logbook ini sudah punya ${f.attachments.length} lampiran. '
              'Tambahkan lampiran baru atau ganti semua lampiran lama?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Batal')),
            TextButton(onPressed: () => Navigator.pop(c, 'replace'), child: const Text('Ganti')),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
              onPressed: () => Navigator.pop(c, 'append'),
              child: const Text('Tambahkan'),
            ),
          ],
        ),
      );
      if (picked == null) return;
      mode = picked;
    }

    if (f.executed && f.isUnsafe && !f.hasRequiredPhoto(mode, _fileNames)) {
      return _alert(
        'Foto wajib diisi',
        f.afterRepairPhotoRequired
            ? 'Lampirkan minimal 1 foto setelah perbaikan (${f.photoExtensions.join('/')}).'
            : 'Laporan Unsafe Condition wajib memiliki minimal 1 foto (${f.photoExtensions.join('/')}).',
      );
    }

    setState(() {
      _saving = true;
      _errors = {};
    });
    try {
      final msg = await ref.read(confirmationRepositoryProvider).submit(
            widget.workOrder,
            widget.operationId,
            f.toPayload(isFinal: isFinal, attachmentMode: mode),
            f.executed ? _files : const [],
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      Navigator.of(context).pop(true);
    } on ConfirmationValidationError catch (e) {
      if (!mounted) return;
      setState(() => _errors = e.errors);
      // Buka item pertama yang error supaya pesan langsung terlihat.
      final bad = e.errors.keys
          .map((k) => RegExp(r'^item_parameter\.(\d+)\.').firstMatch(k))
          .whereType<RegExpMatch>()
          .map((m) => int.parse(m.group(1)!))
          .where((i) => i < f.items.length)
          .firstOrNull;
      if (bad != null) _openItem(f.items[bad]);
      if (e.errors.isEmpty) _alert('Gagal menyimpan', e.message);
    } catch (e) {
      if (mounted) _alert('Gagal menyimpan', apiErrorMessage(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _alert(String title, String message) => showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
        ),
      );

  Widget _section(String title, List<Widget> children, {Widget? action, String? subtitle}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              if (subtitle != null) ...[
                const SizedBox(width: 8),
                Text(subtitle, style: const TextStyle(color: ApmColors.muted, fontSize: 12)),
              ],
              const Spacer(),
              if (action != null) action else const SizedBox(height: 40),
            ]),
            const SizedBox(height: 4),
            for (final c in children) ...[c, const SizedBox(height: 12)],
          ],
        ),
      ),
    );
  }
}

// =====================================================================

/// Satu item parameter sebagai accordion: ringkas saat tertutup (parameter, hasil,
/// evaluation, status kelengkapan), form lengkap saat dibuka. Info dari PPM
/// (parameter/method/rekomendasi) tampil sebagai teks; "Ubah" untuk mengeditnya.
class _ItemTile extends StatelessWidget {
  const _ItemTile({
    super.key,
    required this.index,
    required this.row,
    required this.form,
    required this.readOnly,
    required this.expanded,
    required this.hasError,
    required this.parameterOptions,
    required this.canDelete,
    required this.err,
    required this.onToggle,
    required this.onChanged,
    required this.onDelete,
    required this.onNext,
  });

  final int index;
  final ItemParamRow row;
  final ConfirmationForm form;
  final bool readOnly;
  final bool expanded;
  final bool hasError;
  final List<SelectItem<String>> parameterOptions;
  final bool canDelete;
  final String? Function(String) err;
  final VoidCallback onToggle;
  final VoidCallback onChanged;
  final VoidCallback onDelete;
  final VoidCallback onNext;

  static const evalColors = {
    'GOOD': ApmColors.success,
    'CONSIDERABLE': ApmColors.info,
    'WARNING': ApmColors.warning,
    'BAD': ApmColors.secondary,
    'BREAKDOWN': ApmColors.danger,
  };

  @override
  Widget build(BuildContext context) {
    final reported = row.id != null && form.reportedItemIds.contains(row.id);
    final borderColor = hasError
        ? ApmColors.danger
        : expanded
            ? ApmColors.primary
            : ApmColors.border;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor, width: expanded || hasError ? 1.5 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(onTap: onToggle, child: _summary(reported)),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            alignment: Alignment.topCenter,
            child: expanded ? _editor(context) : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  // ---------- tampilan ringkas ----------
  Widget _summary(bool reported) {
    final done = row.isComplete;
    final hasil = row.isOption
        ? row.unitSelected
        : (row.value == null || row.value!.isEmpty ? null : '${row.value} ${row.unit ?? ''}'.trim());

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(
            hasError
                ? Icons.error
                : done
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked,
            size: 20,
            color: hasError
                ? ApmColors.danger
                : done
                    ? ApmColors.success
                    : ApmColors.muted,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              '${index + 1}. ${row.parameter?.isNotEmpty == true ? row.parameter : 'Parameter baru'}',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            if (row.method?.isNotEmpty == true)
              Text(row.method!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: ApmColors.muted, fontSize: 12)),
            if (!expanded) ...[
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 4, children: [
                if (reported) const SoftBadge('e-Posh', color: ApmColors.danger),
                if (row.rtTa != null) SoftBadge(row.rtTa!, color: ApmColors.muted),
                if (hasil != null) SoftBadge(hasil, color: ApmColors.info),
                if (row.evaluation != null)
                  SoftBadge(row.evaluation!, color: evalColors[row.evaluation] ?? ApmColors.muted),
                if (!done)
                  Text('Belum: ${row.missing.join(', ')}',
                      style: const TextStyle(color: ApmColors.warning, fontSize: 12)),
              ]),
            ],
          ]),
        ),
        Icon(expanded ? Icons.expand_less : Icons.expand_more, color: ApmColors.muted),
        const SizedBox(width: 4),
      ]),
    );
  }

  // ---------- form lengkap ----------
  Widget _editor(BuildContext context) {
    final desc = row.evaluation == null ? null : form.evaluationDescriptions[row.evaluation];
    final showInfoAsText = !row.editInfo && row.parameter?.isNotEmpty == true;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showInfoAsText)
            _InfoBlock(
              recommendation: row.recommendation,
              onEdit: readOnly
                  ? null
                  : () {
                      row.editInfo = true;
                      onChanged();
                    },
              errorText: err('parameter') ?? err('method') ?? err('recommendation'),
            )
          else ...[
            // Web: select bila ada opsi PPM, selain itu teks bebas.
            if (parameterOptions.isNotEmpty)
              SearchSelect<String>(
                label: 'Parameter',
                required: true,
                enabled: !readOnly,
                items: parameterOptions,
                value: row.parameter,
                errorText: err('parameter'),
                onChanged: (v) {
                  form.onParameterSelected(row, v);
                  onChanged();
                },
              )
            else
              ModelTextField(
                label: 'Parameter',
                required: true,
                enabled: !readOnly,
                value: row.parameter,
                errorText: err('parameter'),
                onChanged: (v) {
                  row.parameter = v;
                },
              ),
            const SizedBox(height: 10),
            ModelTextField(
              label: 'Method',
              enabled: !readOnly,
              value: row.method,
              errorText: err('method'),
              onChanged: (v) => row.method = v,
            ),
            const SizedBox(height: 10),
            ModelTextField(
              label: 'Recommendation',
              maxLines: 4,
              enabled: !readOnly,
              value: row.recommendation,
              errorText: err('recommendation'),
              onChanged: (v) => row.recommendation = v,
            ),
          ],
          const SizedBox(height: 12),
          if (row.isOption)
            ChipChoice<String>(
              label: 'Hasil',
              enabled: !readOnly,
              items: [for (final u in row.unitOptions) SelectItem(u, u)],
              value: row.unitSelected,
              errorText: err('unit'),
              onChanged: (v) {
                row.unitSelected = v;
                onChanged();
              },
            )
          else
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                flex: 3,
                child: ModelTextField(
                  label: 'Value',
                  enabled: !readOnly,
                  value: row.value,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  errorText: err('value'),
                  // web handleCommaToDot
                  onChanged: (v) => row.value = v.replaceAll(',', '.'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: ModelTextField(
                  label: 'UoM',
                  enabled: !readOnly,
                  value: row.unit,
                  errorText: err('unit'),
                  onChanged: (v) => row.unit = v,
                ),
              ),
            ]),
          const SizedBox(height: 12),
          ChipChoice<String>(
            label: 'RT / TA',
            required: true,
            enabled: !readOnly,
            items: [for (final o in form.typeRtOptions) SelectItem(o.value.toString(), o.label)],
            value: row.rtTa,
            errorText: err('rt_ta'),
            onChanged: (v) {
              row.rtTa = v;
              onChanged();
            },
          ),
          const SizedBox(height: 12),
          ModelTextField(
            label: 'Analysis',
            required: true,
            maxLines: 3,
            enabled: !readOnly,
            value: row.analysis,
            errorText: err('analysis'),
            onChanged: (v) {
              final wasEmpty = row.analysis?.trim().isEmpty ?? true;
              row.analysis = v;
              // Perbarui indikator kelengkapan hanya saat status kosong/terisi berubah.
              if (wasEmpty != v.trim().isEmpty) onChanged();
            },
          ),
          const SizedBox(height: 12),
          ChipChoice<String>(
            label: 'Evaluation',
            required: true,
            enabled: !readOnly,
            colors: evalColors,
            items: [for (final o in form.evaluationOptions) SelectItem(o.value.toString(), o.label)],
            value: row.evaluation,
            errorText: err('evaluation'),
            onChanged: (v) {
              row.evaluation = v;
              onChanged();
            },
          ),
          if (desc != null && desc.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(desc, style: const TextStyle(color: ApmColors.muted, fontSize: 12)),
          ],
          if (row.evaluation != null) ...[
            const SizedBox(height: 6),
            Row(children: [
              SoftBadge('Grade ${_fmtGrade(row.grade)}',
                  color: evalColors[row.evaluation] ?? ApmColors.muted),
            ]),
          ],
          if (row.unsafeDetail != null) ...[
            const SizedBox(height: 10),
            _UnsafeDetail(row.unsafeDetail!),
          ],
          if (!readOnly) ...[
            const SizedBox(height: 8),
            Row(children: [
              if (canDelete)
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: ApmColors.danger),
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Hapus'),
                ),
              const Spacer(),
              FilledButton.tonalIcon(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 38)),
                onPressed: onNext,
                icon: const Icon(Icons.arrow_downward, size: 18),
                label: const Text('Berikutnya'),
              ),
            ]),
          ],
        ],
      ),
    );
  }

  static String _fmtGrade(num g) => g == g.roundToDouble() ? g.toInt().toString() : g.toString();
}

/// Rekomendasi dari tasklist PPM sebagai teks (dipendekkan, tap untuk lengkap).
class _InfoBlock extends StatefulWidget {
  const _InfoBlock({required this.recommendation, this.onEdit, this.errorText});

  final String? recommendation;
  final VoidCallback? onEdit;
  final String? errorText;

  @override
  State<_InfoBlock> createState() => _InfoBlockState();
}

class _InfoBlockState extends State<_InfoBlock> {
  bool _full = false;

  @override
  Widget build(BuildContext context) {
    final rec = widget.recommendation?.trim() ?? '';
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
      decoration: BoxDecoration(
        color: ApmColors.light,
        borderRadius: BorderRadius.circular(6),
        border: widget.errorText == null ? null : Border.all(color: ApmColors.danger),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('Rekomendasi tasklist',
              style: TextStyle(fontSize: 12, color: ApmColors.muted, fontWeight: FontWeight.w600)),
          const Spacer(),
          if (widget.onEdit != null)
            TextButton(
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              onPressed: widget.onEdit,
              child: const Text('Ubah', style: TextStyle(fontSize: 12)),
            ),
        ]),
        GestureDetector(
          onTap: () => setState(() => _full = !_full),
          child: Text(
            rec.isEmpty ? '-' : rec,
            maxLines: _full ? null : 3,
            overflow: _full ? null : TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13),
          ),
        ),
        if (widget.errorText != null)
          Text(widget.errorText!, style: const TextStyle(color: ApmColors.danger, fontSize: 12)),
      ]),
    );
  }
}

class _BulkFill {
  _BulkFill({this.hasil, this.evaluation, this.analysis, required this.onlyEmpty});

  final String? hasil;
  final String? evaluation;
  final String? analysis;
  final bool onlyEmpty;
}

class _BulkFillSheet extends StatefulWidget {
  const _BulkFillSheet({required this.form, required this.hasilOptions});

  final ConfirmationForm form;
  final List<String> hasilOptions;

  @override
  State<_BulkFillSheet> createState() => _BulkFillSheetState();
}

class _BulkFillSheetState extends State<_BulkFillSheet> {
  String? _hasil;
  String? _evaluation;
  String _analysis = '';
  bool _onlyEmpty = true;

  @override
  Widget build(BuildContext context) {
    final nothing = _hasil == null && _evaluation == null && _analysis.trim().isEmpty;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Isi massal item parameter',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 4),
            Text('Diterapkan ke ${widget.form.items.length} item. Kosongkan yang tidak ingin diubah.',
                style: const TextStyle(color: ApmColors.muted, fontSize: 12)),
            const SizedBox(height: 16),
            if (widget.hasilOptions.isNotEmpty) ...[
              ChipChoice<String>(
                label: 'Hasil (item pilihan)',
                items: [for (final u in widget.hasilOptions) SelectItem(u, u)],
                value: _hasil,
                onChanged: (v) => setState(() => _hasil = _hasil == v ? null : v),
              ),
              const SizedBox(height: 14),
            ],
            ChipChoice<String>(
              label: 'Evaluation',
              colors: _ItemTile.evalColors,
              items: [
                for (final o in widget.form.evaluationOptions) SelectItem(o.value.toString(), o.label)
              ],
              value: _evaluation,
              onChanged: (v) => setState(() => _evaluation = _evaluation == v ? null : v),
            ),
            const SizedBox(height: 14),
            TextField(
              maxLines: 3,
              minLines: 1,
              decoration: const InputDecoration(labelText: 'Analysis'),
              onChanged: (v) => setState(() => _analysis = v),
            ),
            const SizedBox(height: 6),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _onlyEmpty,
              onChanged: (v) => setState(() => _onlyEmpty = v ?? true),
              title: const Text('Hanya isi yang masih kosong', style: TextStyle(fontSize: 14)),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: nothing
                  ? null
                  : () => Navigator.pop(
                        context,
                        _BulkFill(
                          hasil: _hasil,
                          evaluation: _evaluation,
                          analysis: _analysis.trim().isEmpty ? null : _analysis.trim(),
                          onlyEmpty: _onlyEmpty,
                        ),
                      ),
              child: const Text('Terapkan'),
            ),
          ],
        ),
      ),
    );
  }
}

class _UnsafeDetail extends StatelessWidget {
  const _UnsafeDetail(this.d);

  final Json d;

  @override
  Widget build(BuildContext context) {
    final rows = {
      'Objek terdampak': d['affected_object'],
      'Likelihood': d['likelihood'],
      'Sumber': d['source'],
      'Consequence': d['consequence'],
      'Due date': d['due_date']?.toString().split('T').first,
    };
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: ApmColors.danger.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Detail Unsafe Condition',
              style: TextStyle(fontWeight: FontWeight.w600, color: ApmColors.danger)),
          for (final e in rows.entries)
            if (e.value != null) Text('${e.key}: ${e.value}', style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard(this.f);

  final ConfirmationForm f;

  @override
  Widget build(BuildContext context) {
    final wo = f.workorder;
    final ppm = wo['ppm'] as Map?;
    final ucNumbers = (f.unsafeContext['reports'] as List? ?? const [])
        .map((r) => (r as Map)['report_number'])
        .whereType<Object>()
        .join(', ');
    final rows = <String, Object?>{
      'No. Workorder': wo['WorkOrder'],
      'Notification': wo['Notification'],
      if (f.unsafeEnabled) 'No. Laporan UC': ucNumbers.isEmpty ? '-' : ucNumbers,
      'Maintenance Plan': ppm?['maintenance_plan'],
      'Grup Tasklist / Counter':
          ppm == null ? null : '${ppm['grup'] ?? '-'} / ${ppm['grup_counter'] ?? '-'}',
      'Object Type APM': (f.workorder['equipment'] as Map?)?['object_type_apm']?['name'],
      'Equipment': wo['Equipment'],
      'Deskripsi': wo['Description'],
      'Oprshorttext': wo['Oprshorttext'],
      'OprWorkcenter': wo['OprWorkcenter'],
      'Deskripsi Workcenter': (wo['workcenter'] as Map?)?['description'],
      'Normal Duration': wo['Normalduration'],
      'Effect Value': f.equipment['effect_value'],
    };

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        title: Text(f.form['session']?.toString() ?? '-',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text('No Reg: ${f.form['label'] ?? ''}. ${f.form['no'] ?? ''} (perkiraan)',
            style: const TextStyle(fontSize: 12, color: ApmColors.muted)),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          for (final e in rows.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                  width: 130,
                  child: Text(e.key, style: const TextStyle(color: ApmColors.muted, fontSize: 12)),
                ),
                Expanded(
                  child: Text('${e.value ?? '-'}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                ),
              ]),
            ),
        ],
      ),
    );
  }
}

class _Alert extends StatelessWidget {
  const _Alert({required this.text, required this.color, required this.icon});

  final String text;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: TextStyle(color: color, fontSize: 13))),
      ]),
    );
  }
}
