import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/form_submit.dart';
import '../../core/theme.dart';
import '../../core/widgets/attachment_picker.dart';
import '../../core/widgets/form_fields.dart';
import '../workorder/confirmation/confirmation_form.dart' show formatDateTime;
import 'general_data_form.dart';
import 'general_data_repository.dart';

/// General Data — langkah 2: form Create Logbook Equipment, padanan
/// Transaction/General-Logbook/Create.vue (prefill, autofill parameter, grade,
/// Kegiatan Pemeliharaan, Unsafe Condition e-Posh).
class GeneralDataCreatePage extends ConsumerStatefulWidget {
  const GeneralDataCreatePage({super.key, required this.equipmentId});

  final int equipmentId;

  @override
  ConsumerState<GeneralDataCreatePage> createState() => _GeneralDataCreatePageState();
}

class _GeneralDataCreatePageState extends ConsumerState<GeneralDataCreatePage> {
  GeneralDataForm? _f;
  Object? _loadError;
  bool _saving = false;
  final List<AttachmentFile> _files = [];
  Map<String, List<String>> _errors = {};

  GdItemRow? _open;
  final Map<GdItemRow, GlobalKey> _itemKeys = {};

  EposhMaster _master = EposhMaster.empty();
  bool _masterLoaded = false;

  /// Bagian per department_id (null = belum di-fetch, [] = memang kosong).
  final Map<int, List<EposhOption>> _bagian = {};

  GeneralDataRepository get _repo => ref.read(generalDataRepositoryProvider);

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
      final f = await _repo.loadForm(widget.equipmentId);
      if (!mounted) return;
      setState(() {
        _f = f;
        _open = f.items.first;
      });
      _fetchDescriptions();
    } catch (e) {
      if (mounted) setState(() => _loadError = e);
    }
  }

  Future<void> _fetchDescriptions() async {
    final id = _f?.classificationId;
    if (id == null) return;
    try {
      final d = await _repo.evaluationDescriptions(id);
      if (mounted && d.isNotEmpty) setState(() => _f!.evaluationDescriptions = d);
    } catch (_) {
      // Web: fallback ke deskripsi hardcoded.
    }
  }

  // ---------------- e-Posh ----------------
  Future<void> _ensureMaster() async {
    if (_masterLoaded) return;
    _masterLoaded = true;
    try {
      final m = await _repo.eposhMaster();
      if (mounted) setState(() => _master = m);
    } catch (_) {
      if (mounted) {
        setState(() => _master = EposhMaster(<String, dynamic>{'degraded': true}));
      }
    }
    final dep = _f?.eposhDepartmentPrefill;
    if (dep != null) _fetchBagian(dep);
  }

  Future<void> _fetchBagian(int departmentId) async {
    if (_bagian.containsKey(departmentId)) return;
    try {
      final list = await _repo.bagian(departmentId);
      if (mounted) setState(() => _bagian[departmentId] = list);
    } catch (_) {
      // Jangan cache kegagalan — dicoba lagi saat department dipilih ulang (web).
    }
  }

  Future<void> _onDepartmentChanged(GdItemRow row, int id) async {
    setState(() => row.departmentId = id);
    await _fetchBagian(id);
    final valid = (_bagian[id] ?? const []).any((o) => o.value == row.partId);
    if (!valid && mounted) setState(() => row.partId = null);
  }

  Future<void> _refreshRisk(GdItemRow row) async {
    final l = row.likelihood, c = row.consequence;
    if (l == null || c == null) {
      setState(() {
        row.riskCategory = null;
        row.riskLoading = false;
      });
      return;
    }
    final token = ++row.riskToken;
    setState(() => row.riskLoading = true);
    try {
      final cat = await _repo.riskCategory(l, c, row.affectedObject);
      if (!mounted || row.riskToken != token) return;
      setState(() => row.riskCategory = cat);
    } catch (_) {
      if (mounted && row.riskToken == token) setState(() => row.riskCategory = null);
    } finally {
      if (mounted && row.riskToken == token) setState(() => row.riskLoading = false);
    }
  }

  String? _err(String key) => _errors[key]?.first;

  // ---------------- build ----------------
  @override
  Widget build(BuildContext context) {
    final f = _f;
    return Scaffold(
      appBar: AppBar(title: Text(f == null ? 'Create Logbook' : 'Logbook ${f.equipmentName}')),
      body: _buildBody(),
      bottomNavigationBar: f == null ? null : _buildActions(),
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

    final complete = f.items.where((r) => f.missingFor(r).isEmpty).length;
    final canAdd = !(f.unsafe && f.items.isNotEmpty);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        if (_errors.isNotEmpty) ...[
          const _Alert(
              text: 'Periksa kembali isian yang ditandai merah.',
              color: ApmColors.danger,
              icon: Icons.error_outline),
          const SizedBox(height: 12),
        ],
        _EquipmentHeader(f),
        const SizedBox(height: 16),
        _section('Data Logbook', _mainFields(f)),
        const SizedBox(height: 16),
        _section(
          'Item Parameter',
          [
            for (final (i, row) in f.items.indexed)
              _GdItemTile(
                key: _itemKeys.putIfAbsent(row, GlobalKey.new),
                index: i,
                row: row,
                form: f,
                expanded: identical(_open, row),
                hasError: _errors.keys.any((k) => k.startsWith('item_parameter.$i.')),
                canDelete: f.items.length > 1,
                err: (k) => _err('item_parameter.$i.$k'),
                master: _master,
                bagian: row.departmentId == null ? null : _bagian[row.departmentId],
                onToggle: () => _openItem(identical(_open, row) ? null : row),
                onChanged: () => setState(() {}),
                onDepartmentChanged: (id) => _onDepartmentChanged(row, id),
                onRiskInputsChanged: () => _refreshRisk(row),
                onDelete: () => setState(() {
                  f.items.removeAt(i);
                  _itemKeys.remove(row);
                }),
                onNext: () {
                  final rest = [...f.items.skip(i + 1), ...f.items.take(i)];
                  _openItem(rest.where((r) => f.missingFor(r).isNotEmpty).firstOrNull);
                },
              ),
            if (_err('item_parameter') != null)
              Text(_err('item_parameter')!, style: const TextStyle(color: ApmColors.danger, fontSize: 12)),
          ],
          subtitle: '$complete/${f.items.length} lengkap',
          action: canAdd
              ? IconButton(
                  tooltip: 'Tambah item',
                  icon: const Icon(Icons.add),
                  onPressed: () {
                    final row = f.addItem();
                    if (row != null) _openItem(row);
                  },
                )
              : null,
        ),
      ],
    );
  }

  List<Widget> _mainFields(GeneralDataForm f) {
    final activities = f.maintenanceActivities;
    final selectedActivity =
        activities.where((a) => a['value'] == f.maintenanceActivityId).firstOrNull;
    final photoMissing =
        f.unsafe && !_files.any((x) => isPhotoFile(x.name, f.photoExtensions));

    return [
      DateTimeField(
        label: 'Date',
        required: true,
        value: f.date,
        format: formatDateTime,
        errorText: _err('date'),
        onChanged: (d) => setState(() => f.date = d),
      ),
      if (f.isAJG)
        ModelTextField(
          label: 'No Work Order',
          value: f.workOrder,
          errorText: _err('work_order'),
          onChanged: (v) => f.workOrder = v,
        ),
      AttachmentPicker(
        files: _files,
        required: f.unsafe,
        errorText: _err('file') ??
            (photoMissing
                ? 'Unsafe Condition wajib memiliki minimal 1 foto (${f.photoExtensions.join('/')}).'
                : null),
        onChanged: () => setState(() {}),
      ),
      SearchSelect<int>(
        label: 'Executor',
        required: true,
        items: [for (final o in f.executorOptions) SelectItem(int.parse('${o.value}'), o.label)],
        value: f.executorId,
        errorText: _err('executor_id'),
        onChanged: (v) => setState(() => f.executorId = v),
      ),
      SearchSelect<int>(
        label: 'Classification',
        required: true,
        items: [for (final o in f.classificationOptions) SelectItem(int.parse('${o.value}'), o.label)],
        value: f.classificationId,
        errorText: _err('classification_id') ??
            (f.costCenterBlocked ? 'Cost Center tidak ditemukan. Silahkan hubungi admin.' : null),
        onChanged: (v) {
          setState(() => f.classificationId = v);
          _fetchDescriptions();
        },
      ),
      if (activities.isEmpty)
        const Text('Kegiatan Pemeliharaan: tidak ada kegiatan yang belum tertaut untuk equipment ini.',
            style: TextStyle(color: ApmColors.muted, fontSize: 12))
      else ...[
        SearchSelect<int>(
          label: 'Kegiatan Pemeliharaan (opsional)',
          items: [
            for (final a in activities) SelectItem(a['value'] as int, a['label']?.toString() ?? '-')
          ],
          value: f.maintenanceActivityId,
          onChanged: (v) => setState(() {
            f.applyMaintenanceActivity(activities.firstWhere((a) => a['value'] == v));
            _open = f.items.first;
          }),
        ),
        if (selectedActivity != null)
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: ApmColors.light, borderRadius: BorderRadius.circular(6)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(selectedActivity['item']?.toString() ?? '-',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                InkWell(
                  onTap: () => setState(() => f.maintenanceActivityId = null),
                  child: const Icon(Icons.close, size: 18, color: ApmColors.muted),
                ),
              ]),
              Text(selectedActivity['description']?.toString() ?? '',
                  style: const TextStyle(color: ApmColors.muted, fontSize: 12)),
              Text(
                [
                  selectedActivity['unit_label'],
                  '${selectedActivity['session_date'] ?? ''} Shift ${selectedActivity['shift'] ?? ''}',
                ].whereType<Object>().join(' · '),
                style: const TextStyle(color: ApmColors.muted, fontSize: 12),
              ),
            ]),
          ),
      ],
      if (f.unsafeEnabled)
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Unsafe Condition'),
          subtitle: Text(
            !f.unsafe && f.items.length > 1
                ? 'Hapus item parameter hingga tersisa 1 untuk menandai Unsafe Condition.'
                : 'Temuan dikirim ke e-Posh (wajib foto, 1 item).',
          ),
          value: f.unsafe,
          onChanged: !f.unsafe && f.items.length > 1
              ? null
              : (v) {
                  setState(() => f.unsafe = v);
                  if (v) _ensureMaster();
                },
        ),
      if (f.unsafe && _master.degraded)
        const _Alert(
          text: 'Data master e-Posh sedang tidak lengkap (koneksi e-Posh terganggu). '
              'Sebagian pilihan mungkin kosong.',
          color: ApmColors.warning,
          icon: Icons.cloud_off,
        ),
    ];
  }

  void _openItem(GdItemRow? row) {
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

  Widget _buildActions() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Submit'),
        ),
      ),
    );
  }

  /// Cek sama dengan web (computed disabled + submit()).
  Future<void> _submit() async {
    final f = _f!;
    FocusManager.instance.primaryFocus?.unfocus();

    if (f.classificationId == null) {
      return _alert('Classification wajib diisi', 'Pilih classification terlebih dahulu.');
    }
    if (f.costCenterBlocked) {
      return _alert('Tidak bisa submit', 'Cost Center equipment tidak ditemukan. Silahkan hubungi admin.');
    }
    final incomplete = f.items.where((r) => f.missingFor(r).isNotEmpty).firstOrNull;
    if (incomplete != null) {
      _openItem(incomplete);
      return _alert('Item belum lengkap',
          'Item ${f.items.indexOf(incomplete) + 1}: ${f.missingFor(incomplete).join(', ')}.');
    }
    if (f.unsafe && !_files.any((x) => isPhotoFile(x.name, f.photoExtensions))) {
      return _alert('Foto wajib diisi',
          'Unsafe Condition wajib memiliki minimal 1 foto (${f.photoExtensions.join('/')}).');
    }
    if (f.isSce && f.classificationLabel?.toLowerCase() == 'bypass interlock') {
      return _alert('Tidak bisa submit', 'Equipment SCE tidak boleh di-bypass!');
    }

    setState(() {
      _saving = true;
      _errors = {};
    });
    try {
      final saved = await _repo.submit(f.toPayload(), _files);
      if (!mounted) return;
      await _success(saved);
      if (mounted) Navigator.of(context).pop(true);
    } on ValidationError catch (e) {
      if (!mounted) return;
      setState(() => _errors = e.errors);
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

  /// Web: SweetAlert "Data has been saved" + No. Register dengan tombol Copy.
  Future<void> _success(SavedLogbook saved) {
    final followUp = switch (saved.next) {
      'bypass' => 'Lanjutkan pengisian form Bypass Interlock di APM web.',
      'moc' => 'Lanjutkan pengisian form MOC di APM web.',
      _ => null,
    };
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        icon: const Icon(Icons.check_circle, color: ApmColors.success, size: 40),
        title: const Text('Data berhasil disimpan'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('No. Register', style: TextStyle(color: ApmColors.muted)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
            decoration: BoxDecoration(color: ApmColors.light, borderRadius: BorderRadius.circular(6)),
            child: Row(children: [
              Expanded(
                child: SelectableText(saved.no,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              ),
              IconButton(
                tooltip: 'Salin',
                icon: const Icon(Icons.copy, size: 20),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: saved.no));
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('No. Register disalin.')));
                },
              ),
            ]),
          ),
          if (followUp != null) ...[
            const SizedBox(height: 12),
            Text(followUp, textAlign: TextAlign.center, style: const TextStyle(color: ApmColors.warning)),
          ],
        ]),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
            onPressed: () => Navigator.pop(c),
            child: const Text('OK'),
          ),
        ],
      ),
    );
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

class _EquipmentHeader extends StatelessWidget {
  const _EquipmentHeader(this.f);

  final GeneralDataForm f;

  @override
  Widget build(BuildContext context) {
    final eq = f.equipment;
    final plant = (eq['section'] as Map?)?['plant'] as Map?;
    final rows = <String, Object?>{
      'Equipment': eq['name'],
      'Pabrik': '${(plant?['factory'] as Map?)?['name'] ?? '-'} / ${plant?['name'] ?? '-'}',
      'Effect Value': eq['effect_value'],
      'ABC Indikator': eq['abc_indicator'],
      'Deskripsi': eq['description'],
    };
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        title: Text('${eq['name'] ?? '-'}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text(f.session, style: const TextStyle(fontSize: 12, color: ApmColors.muted)),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          for (final e in rows.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                  width: 110,
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

/// Item parameter accordion (pola sama dengan form Report WO).
class _GdItemTile extends StatelessWidget {
  const _GdItemTile({
    super.key,
    required this.index,
    required this.row,
    required this.form,
    required this.expanded,
    required this.hasError,
    required this.canDelete,
    required this.err,
    required this.master,
    required this.bagian,
    required this.onToggle,
    required this.onChanged,
    required this.onDepartmentChanged,
    required this.onRiskInputsChanged,
    required this.onDelete,
    required this.onNext,
  });

  final int index;
  final GdItemRow row;
  final GeneralDataForm form;
  final bool expanded;
  final bool hasError;
  final bool canDelete;
  final String? Function(String) err;
  final EposhMaster master;
  final List<EposhOption>? bagian;
  final VoidCallback onToggle;
  final VoidCallback onChanged;
  final ValueChanged<int> onDepartmentChanged;
  final VoidCallback onRiskInputsChanged;
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
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(onTap: onToggle, child: _summary()),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.topCenter,
          child: expanded ? _editor(context) : const SizedBox(width: double.infinity),
        ),
      ]),
    );
  }

  Widget _summary() {
    final missing = form.missingFor(row);
    final done = missing.isEmpty;
    final hasil = (row.value?.isNotEmpty ?? false) || (row.unit?.isNotEmpty ?? false)
        ? '${row.value ?? ''} ${row.unit ?? ''}'.trim()
        : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(
          hasError ? Icons.error : (done ? Icons.check_circle : Icons.radio_button_unchecked),
          size: 20,
          color: hasError ? ApmColors.danger : (done ? ApmColors.success : ApmColors.muted),
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
                if (row.rtTa != null) SoftBadge(row.rtTa!, color: ApmColors.muted),
                if (hasil != null) SoftBadge(hasil, color: ApmColors.info),
                if (row.evaluation != null)
                  SoftBadge('${row.evaluation} ${_fmt(row.grade)}',
                      color: evalColors[row.evaluation] ?? ApmColors.muted),
                if (!done)
                  Text('Belum: ${missing.join(', ')}',
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

  Widget _editor(BuildContext context) {
    final params = form.itemParameterType;
    final desc = row.evaluation == null ? null : form.evaluationDescriptions[row.evaluation];
    const gap = SizedBox(height: 12);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Web: select dari tasklist PPM bila ada, selain itu teks bebas.
        if (params.isNotEmpty)
          Row(children: [
            Expanded(
              child: SearchSelect<String>(
                label: 'Parameter',
                required: true,
                items: [for (final p in params) SelectItem(p['value'].toString(), p['label'].toString())],
                value: row.parameter,
                errorText: err('parameter'),
                onChanged: (v) {
                  form.onParameterSelected(row, v);
                  onChanged();
                },
              ),
            ),
            if (row.parameter != null)
              IconButton(
                tooltip: 'Kosongkan',
                icon: const Icon(Icons.close),
                onPressed: () {
                  form.clearParameter(row);
                  onChanged();
                },
              ),
          ])
        else
          ModelTextField(
            label: 'Parameter',
            required: true,
            value: row.parameter,
            errorText: err('parameter'),
            onChanged: (v) {
              final wasEmpty = row.parameter?.trim().isEmpty ?? true;
              row.parameter = v;
              if (wasEmpty != v.trim().isEmpty) onChanged();
            },
          ),
        gap,
        ModelTextField(
          label: 'Method',
          value: row.method,
          errorText: err('method'),
          onChanged: (v) => row.method = v,
        ),
        gap,
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            flex: 3,
            child: ModelTextField(
              label: 'Value',
              value: row.value,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              errorText: err('value'),
              onChanged: (v) => row.value = v.replaceAll(',', '.'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: ModelTextField(
              label: 'UoM',
              value: row.unit,
              errorText: err('unit'),
              onChanged: (v) => row.unit = v,
            ),
          ),
        ]),
        if (row.unitChoices.isNotEmpty) ...[
          const SizedBox(height: 8),
          // Tasklist bertipe pilihan (mis. Comply/Not Comply): tap untuk mengisi UoM.
          ChipChoice<String>(
            label: 'Hasil',
            items: [for (final u in row.unitChoices) SelectItem(u, u)],
            value: row.unitChoices.contains(row.unit) ? row.unit : null,
            onChanged: (v) {
              row.unit = v;
              onChanged();
            },
          ),
        ],
        gap,
        ChipChoice<String>(
          label: 'RT / TA',
          required: true,
          items: [for (final o in form.typeRtOptions) SelectItem(o.value.toString(), o.label)],
          value: row.rtTa,
          errorText: err('rt_ta'),
          onChanged: (v) {
            row.rtTa = v;
            onChanged();
          },
        ),
        gap,
        ModelTextField(
          label: 'Analysis',
          required: true,
          maxLines: 3,
          value: row.analysis,
          errorText: err('analysis'),
          onChanged: (v) {
            final wasEmpty = row.analysis?.trim().isEmpty ?? true;
            row.analysis = v;
            if (wasEmpty != v.trim().isEmpty) onChanged();
          },
        ),
        gap,
        ModelTextField(
          label: 'Recommendation',
          maxLines: 3,
          value: row.recommendation,
          errorText: err('recommendation'),
          onChanged: (v) => row.recommendation = v,
        ),
        gap,
        ChipChoice<String>(
          label: 'Evaluation',
          required: true,
          colors: evalColors,
          items: [for (final o in form.evaluationOptions) SelectItem(o.value.toString(), o.label)],
          value: row.evaluation,
          errorText: err('evaluation'),
          onChanged: (v) {
            row
              ..evaluation = v
              ..grade = form.gradeFor(v);
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
            SoftBadge('Grade ${_fmt(row.grade)}', color: evalColors[row.evaluation] ?? ApmColors.muted),
          ]),
        ],
        if (form.unsafe) ...[
          const SizedBox(height: 16),
          _UnsafeFields(
            row: row,
            form: form,
            master: master,
            bagian: bagian,
            err: err,
            onChanged: onChanged,
            onDepartmentChanged: onDepartmentChanged,
            onRiskInputsChanged: onRiskInputsChanged,
          ),
        ],
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
            icon: Icon(form.items.length > 1 ? Icons.arrow_downward : Icons.check, size: 18),
            label: Text(form.items.length > 1 ? 'Berikutnya' : 'Selesai'),
          ),
        ]),
      ]),
    );
  }

  static String _fmt(num g) => g == g.roundToDouble() ? g.toInt().toString() : g.toString();
}

/// Detail Unsafe Condition per item (eposh.unsafe_condition_details).
class _UnsafeFields extends StatelessWidget {
  const _UnsafeFields({
    required this.row,
    required this.form,
    required this.master,
    required this.bagian,
    required this.err,
    required this.onChanged,
    required this.onDepartmentChanged,
    required this.onRiskInputsChanged,
  });

  final GdItemRow row;
  final GeneralDataForm form;
  final EposhMaster master;
  final List<EposhOption>? bagian;
  final String? Function(String) err;
  final VoidCallback onChanged;
  final ValueChanged<int> onDepartmentChanged;
  final VoidCallback onRiskInputsChanged;

  List<EposhOption> get _likelihood => master.likelihood.isNotEmpty
      ? master.likelihood
      : [for (final l in form.likelihoodFallback) EposhOption(l, l)];

  List<EposhOption> _consequenceFor(String? object) {
    final byObject = object == null ? null : master.consequenceByObject[object];
    return byObject != null && byObject.isNotEmpty
        ? byObject
        : [for (final c in form.consequenceFallback) EposhOption(c, c)];
  }

  @override
  Widget build(BuildContext context) {
    final consequences = _consequenceFor(row.affectedObject);
    final likelihoodInfo = _likelihood.where((o) => o.value == row.likelihood).firstOrNull;
    final consequenceInfo = consequences.where((o) => o.value == row.consequence).firstOrNull;
    const gap = SizedBox(height: 12);
    const hint = TextStyle(color: ApmColors.muted, fontSize: 12);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: ApmColors.danger.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: ApmColors.danger.withValues(alpha: 0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Detail Unsafe Condition',
            style: TextStyle(fontWeight: FontWeight.w700, color: ApmColors.danger)),
        gap,
        SearchSelect<String>(
          label: 'Sumber Temuan',
          items: [for (final o in master.sumberTemuan) SelectItem(o.value.toString(), o.label)],
          value: row.source,
          errorText: err('source'),
          onChanged: (v) {
            row.source = v;
            onChanged();
          },
        ),
        gap,
        ChipChoice<String>(
          label: 'Objek Terdampak',
          required: true,
          items: [for (final o in master.affectedObject) SelectItem(o.value.toString(), o.label)],
          value: row.affectedObject,
          errorText: err('affected_object') ??
              (master.affectedObject.isEmpty ? 'Daftar objek terdampak belum tersedia.' : null),
          onChanged: (v) {
            row.affectedObject = v;
            // Tangga severity berbeda per objek — consequence lama bisa tidak valid lagi.
            if (!_consequenceFor(v).any((o) => o.value == row.consequence)) row.consequence = null;
            onChanged();
            onRiskInputsChanged();
          },
        ),
        gap,
        SearchSelect<String>(
          label: 'Likelihood',
          required: true,
          items: [for (final o in _likelihood) SelectItem(o.value.toString(), o.label)],
          value: row.likelihood,
          errorText: err('likelihood'),
          onChanged: (v) {
            row.likelihood = v;
            onChanged();
            onRiskInputsChanged();
          },
        ),
        if (likelihoodInfo?.meta != null || likelihoodInfo?.description != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
                [likelihoodInfo!.meta, likelihoodInfo.description].whereType<String>().join(' — '),
                style: hint),
          ),
        gap,
        SearchSelect<String>(
          label: 'Consequence',
          required: true,
          items: [for (final o in consequences) SelectItem(o.value.toString(), o.label)],
          value: row.consequence,
          errorText: err('consequence'),
          onChanged: (v) {
            row.consequence = v;
            onChanged();
            onRiskInputsChanged();
          },
        ),
        if (consequenceInfo?.description != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(consequenceInfo!.description!, style: hint),
          ),
        const SizedBox(height: 8),
        Row(children: [
          const Text('Risk Category: ', style: hint),
          if (row.riskLoading)
            const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
          else if (row.riskCategory != null)
            SoftBadge(row.riskCategory!['name']?.toString() ?? '-', color: _riskColor(row.riskCategory!))
          else
            const Text('-', style: hint),
        ]),
        gap,
        SearchSelect<int>(
          label: 'Department',
          required: true,
          items: [for (final o in master.departments) SelectItem(int.parse('${o.value}'), o.label)],
          value: row.departmentId,
          errorText: err('department_id') ??
              (master.departments.isEmpty ? 'Daftar department e-Posh tidak tersedia.' : null),
          onChanged: onDepartmentChanged,
        ),
        gap,
        SearchSelect<int>(
          label: 'Bagian',
          items: [for (final o in bagian ?? const <EposhOption>[]) SelectItem(int.parse('${o.value}'), o.label)],
          value: row.partId,
          enabled: row.departmentId != null,
          errorText: err('part_id'),
          hint: row.departmentId == null ? 'Pilih department dulu' : null,
          onChanged: (v) {
            row.partId = v;
            onChanged();
          },
        ),
        if (bagian != null && bagian!.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('Department ini tidak memiliki Bagian.', style: hint),
          ),
        gap,
        _DateOnlyField(
          label: 'Due Date',
          value: row.dueDate,
          errorText: err('due_date'),
          onChanged: (d) {
            row.dueDate = d;
            onChanged();
          },
        ),
      ]),
    );
  }

  /// Warna dari e-Posh (hex) bila ada, selain itu per nama kategori.
  static Color _riskColor(Map<String, dynamic> c) {
    final hex = c['color']?.toString().replaceAll('#', '') ?? '';
    if (hex.length == 6) {
      final v = int.tryParse(hex, radix: 16);
      if (v != null) return Color(0xFF000000 | v);
    }
    return switch (c['name']?.toString().toLowerCase()) {
      'low' => ApmColors.success,
      'medium' => ApmColors.warning,
      'high' => ApmColors.secondary,
      _ => ApmColors.danger,
    };
  }
}

class _DateOnlyField extends StatelessWidget {
  const _DateOnlyField({required this.label, required this.value, required this.onChanged, this.errorText});

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        FocusManager.instance.primaryFocus?.unfocus();
        final now = DateTime.now();
        final d = await showDatePicker(
          context: context,
          firstDate: DateTime(now.year - 1),
          lastDate: DateTime(now.year + 5),
          initialDate: value ?? now,
        );
        if (d != null) onChanged(d);
      },
      child: InputDecorator(
        isEmpty: value == null,
        decoration: InputDecoration(
          labelText: label,
          errorText: errorText,
          suffixIcon: value == null
              ? const Icon(Icons.event)
              : IconButton(icon: const Icon(Icons.close), onPressed: () => onChanged(null)),
        ),
        child: value == null
            ? null
            : Text('${value!.year}-${value!.month.toString().padLeft(2, '0')}-${value!.day.toString().padLeft(2, '0')}'),
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
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: TextStyle(color: color, fontSize: 13))),
      ]),
    );
  }
}
