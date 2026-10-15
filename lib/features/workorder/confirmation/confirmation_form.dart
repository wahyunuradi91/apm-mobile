import 'package:intl/intl.dart';

/// Model form Report (Confirmation) Workorder — meniru
/// apm/resources/js/Pages/Workorder/ConfirmationWorkorder/Index.vue.
/// Sumber data: GET /workorders/{wo}/operations/{id}/confirmation → `form`
/// (= props halaman web dari WorkorderConfirmationService::formData).

typedef Json = Map<String, dynamic>;

final _dateFmt = DateFormat('yyyy-MM-dd HH:mm');

String formatDateTime(DateTime d) => _dateFmt.format(d);

DateTime? parseDateTime(Object? v) {
  if (v == null || v.toString().isEmpty) return null;
  return DateTime.tryParse(v.toString().replaceFirst(' ', 'T'))?.toLocal();
}

class Option {
  const Option(this.value, this.label);

  final Object value;
  final String label;

  static List<Option> listFrom(Object? raw) => (raw as List? ?? const [])
      .map((e) => Option((e as Map)['value'] as Object, e['label']?.toString() ?? '-'))
      .toList();
}

/// Satu baris tabel Item Parameter (`item_parameter[i]`).
class ItemParamRow {
  int? id;
  String? parameter;
  int? gruptasklistId;
  String? method;
  String? value = '0';
  String? unit;
  String? rtTa;
  String? analysis;
  String? recommendation;
  String? evaluation;
  num grade = 0;

  // Hanya untuk UI (web: is_option / unitOptions / unitSelected / unsafe_detail).
  bool isOption = false;
  List<String> unitOptions = [];
  String? unitSelected;
  Json? unsafeDetail;

  /// UI mobile: info PPM (parameter/method/rekomendasi) ditampilkan sebagai teks
  /// sampai user menekan "Ubah".
  bool editInfo = false;

  /// Field wajib yang belum diisi — untuk indikator kelengkapan di daftar item.
  List<String> get missing => [
        if (_blankStr(parameter)) 'Parameter',
        if (isOption && _blankStr(unitSelected)) 'Hasil',
        if (_blankStr(rtTa)) 'RT/TA',
        if (_blankStr(analysis)) 'Analysis',
        if (_blankStr(evaluation)) 'Evaluation',
      ];

  bool get isComplete => missing.isEmpty;
}

bool _blankStr(String? s) => s == null || s.trim().isEmpty;

/// Satu baris Confirmation Personil (`personel_workorder[i]`).
class PersonelRow {
  int? id;
  int? personel;
  String? shift;
  DateTime? startDate;
  DateTime? finishDate;
  String? note;
}

class ConfirmationForm {
  ConfirmationForm._(this.data, this.form);

  /// Respons `data` lengkap (form + can_report + photo_extensions ...).
  final Json data;

  /// Props halaman web.
  final Json form;

  Json get workorder => Map<String, dynamic>.from(form['workorder'] as Map);
  Json get equipment => Map<String, dynamic>.from(form['equipment'] as Map);
  Json? get dataParameter =>
      form['data_parameter'] == null ? null : Map<String, dynamic>.from(form['data_parameter'] as Map);
  Json get unsafeContext => Map<String, dynamic>.from(form['unsafeContext'] as Map);

  bool get canReport => data['can_report'] == true;
  bool get canReportOperation => data['can_report_operation'] == true;
  bool get unsafeEnabled => data['unsafe_condition_enabled'] == true;
  bool get isUnsafe => unsafeEnabled && unsafeContext['isUnsafe'] == true;
  bool get afterRepairPhotoRequired => form['afterRepairPhotoRequired'] == true;
  List<String> get photoExtensions =>
      (data['photo_extensions'] as List? ?? const []).map((e) => e.toString().toLowerCase()).toList();
  List get parkedEposhPhotos => form['parkedEposhPhotos'] as List? ?? const [];
  List<Json> get attachments => (form['attachments'] as List? ?? const [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
  Json? get eposhRevision =>
      form['eposhRevision'] == null ? null : Map<String, dynamic>.from(form['eposhRevision'] as Map);

  List<Option> get personelOptions => Option.listFrom(form['pic']);
  List<Option> get shiftOptions => Option.listFrom(form['shift']);
  List<Option> get executorOptions => Option.listFrom(form['executors']);
  List<Option> get classificationOptions => Option.listFrom(form['classification']);
  List<Option> get typeRtOptions => Option.listFrom(form['typeRT']);
  List<Option> get evaluationOptions => Option.listFrom(form['evaluationType']);

  /// itemParameterType = PPMService::findPPM (+ parameter tersimpan bila tanpa MP).
  List<Json> get itemParameterType => (form['itemParameterType'] as List? ?? const [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
  List<Json> get tasklistOptions => (form['tasklistOptions'] as List? ?? const [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();

  num get effectValue => num.tryParse('${equipment['effect_value'] ?? 0}') ?? 0;
  String? get maintenancePlan {
    final mp = workorder['MaintenancePlan']?.toString();
    return (mp == null || mp.isEmpty) ? null : mp;
  }

  /// Nomor laporan e-Posh (UC) yang terkait item tertentu.
  Set<int> get reportedItemIds => (unsafeContext['reports'] as List? ?? const [])
      .map((r) => (r as Map)['item_parameter_id'])
      .whereType<int>()
      .toSet();

  // ---------------- state yang diedit ----------------
  DateTime? date;
  String workOrder = '';
  int? executorId;
  int? classificationId;
  bool executed = true;
  String? reasonNotExecuted;
  final List<ItemParamRow> items = [];
  final List<PersonelRow> personel = [];
  Map<String, String> evaluationDescriptions = {};

  factory ConfirmationForm.fromResponse(Json data) {
    final f = ConfirmationForm._(data, Map<String, dynamic>.from(data['form'] as Map));
    f._init();
    return f;
  }

  void _init() {
    final wo = workorder;
    final dp = dataParameter;

    // created() web :846-897
    workOrder = form['no_work_order']?.toString() ?? '';
    date = parseDateTime(dp?['date']) ?? DateTime.now();
    executorId = _int(dp?['executor_id']) ?? _int(form['currentExecutor']);
    classificationId = _int(dp?['classification_id']) ?? _defaultClassification();
    executed = wo['executed'] == null ? true : (wo['executed'] == true || wo['executed'] == 1);
    reasonNotExecuted = wo['reason_not_executed']?.toString();
    evaluationDescriptions = _descriptions(form['evaluationDescriptions']);

    for (final k in (wo['konfirmasi'] as List? ?? const [])) {
      final m = k as Map;
      personel.add(PersonelRow()
        ..id = _int(m['id'])
        ..personel = _int((m['personil'] as Map?)?['id'])
        ..shift = m['shift']?.toString()
        ..startDate = parseDateTime(m['start_date'])
        ..finishDate = parseDateTime(m['end_date'])
        ..note = m['note']?.toString());
    }

    // Prefill dari logbook tersimpan (web :858-893).
    for (final raw in (dp?['item_parameters'] as List? ?? const [])) {
      final item = Map<String, dynamic>.from(raw as Map);
      final tasklist = tasklistOptions.where((t) => t['parameter'] == item['parameter']).firstOrNull;
      final itemIsOption = _bool(item['is_option']);
      final isOption = tasklist != null ? _bool(tasklist['is_option']) : itemIsOption;
      final groupUnit = (item['group_task_list'] as Map?)?['unit']?.toString();

      List<String> unitOptions = [];
      if (itemIsOption && groupUnit != null) {
        unitOptions = groupUnit.split('/');
      } else if (tasklist != null && _bool(tasklist['is_option'])) {
        unitOptions = (tasklist['unit']?.toString() ?? '').split('/');
      }

      items.add(ItemParamRow()
        ..id = _int(item['id'])
        ..parameter = item['parameter']?.toString()
        ..gruptasklistId = _int(item['grup_task_list_id'])
        ..method = item['method']?.toString()
        ..value = item['value']?.toString()
        ..unit = item['unit']?.toString()
        ..rtTa = item['RTTA']?.toString()
        ..analysis = item['analysis']?.toString()
        ..recommendation = item['recommendation']?.toString()
        ..evaluation = item['evaluation']?.toString()
        // Opsi tunggal (mis. "°C") = satuan, bukan pilihan — tampilkan input Value.
        ..isOption = isOption && unitOptions.length > 1
        ..unitOptions = unitOptions
        ..unitSelected = isOption && unitOptions.length > 1 ? item['unit']?.toString() : null
        ..unsafeDetail = item['unsafe_detail'] == null
            ? null
            : Map<String, dynamic>.from(item['unsafe_detail'] as Map));
    }

    // Auto-load parameter PPM bila belum ada item (web mounted :1016-1051).
    if (items.isEmpty) {
      if (maintenancePlan != null && itemParameterType.isNotEmpty) {
        for (final p in itemParameterType) {
          final it = Map<String, dynamic>.from((p['item'] as Map?) ?? const {});
          final unit = it['unit']?.toString();
          final unitOptions =
              _bool(it['is_option']) && unit != null ? unit.split('/') : <String>[];
          items.add(ItemParamRow()
            ..parameter = p['value']?.toString()
            ..method = it['pgpr']?.toString()
            ..unit = unit
            ..unitOptions = unitOptions
            ..isOption = unitOptions.length > 1
            ..rtTa = it['rtta']?.toString()
            ..recommendation = it['tasklist']?.toString()
            ..gruptasklistId = _int(it['gruptasklist_id']));
        }
      } else {
        items.add(ItemParamRow());
      }
    }

    recalcGrades();
  }

  int? _defaultClassification() {
    final current = _int(form['currentClassification']);
    if (current != null) return current;
    final label = maintenancePlan != null ? 'Temuan PPM' : 'Temuan Korektif';
    return _int(classificationOptions.where((o) => o.label == label).firstOrNull?.value);
  }

  /// web onParameterSelected (:1114-1142).
  void onParameterSelected(ItemParamRow row, String value) {
    row.parameter = value;
    final found = itemParameterType.where((p) => p['value'] == value).firstOrNull;
    if (found != null && found['item'] is Map) {
      final it = Map<String, dynamic>.from(found['item'] as Map);
      row
        ..unit = it['unit']?.toString()
        ..rtTa = it['rtta']?.toString()
        ..method = it['pgpr']?.toString()
        ..recommendation = it['tasklist']?.toString();
    }
    final tasklist = tasklistOptions.where((t) => t['parameter'] == value).firstOrNull;
    final unitOptions = (tasklist != null && _bool(tasklist['is_option']))
        ? (tasklist['unit']?.toString() ?? '').split('/')
        : <String>[];
    final isOption =
        (tasklist != null ? _bool(tasklist['is_option']) : row.isOption) && unitOptions.length > 1;
    row
      ..isOption = isOption
      ..unitOptions = unitOptions
      ..gruptasklistId = _int(tasklist?['id'])
      ..unitSelected = isOption ? null : row.unit;
  }

  /// Grade otomatis (web deep watcher :994-1011): faktor × effect_value equipment.
  void recalcGrades() {
    const factor = {'CONSIDERABLE': 2, 'WARNING': 3, 'BAD': 4, 'BREAKDOWN': 5};
    for (final r in items) {
      r.grade = (factor[r.evaluation] ?? 0) * effectValue;
    }
  }

  /// web hasRequiredPhoto (:1290-1306).
  bool hasRequiredPhoto(String mode, List<String> newFileNames) {
    if (parkedEposhPhotos.isNotEmpty) return true;
    bool isPhoto(String name) => photoExtensions.contains(name.split('.').last.toLowerCase());
    final newPhotos = newFileNames.where(isPhoto).length;
    if (mode == 'replace' || afterRepairPhotoRequired) return newPhotos > 0;
    final oldPhotos = attachments
        .where((a) => isPhoto((a['file_name_original'] ?? a['file_name'] ?? '').toString()))
        .length;
    return oldPhotos + newPhotos > 0;
  }

  /// Payload sama dengan web submit() (:1328-1414). `final` = true untuk Save, false Temp Save.
  Map<String, dynamic> toPayload({required bool isFinal, required String attachmentMode}) {
    if (isFinal) {
      // syncUnitSelectedToUnit — hanya saat Save (bukan Temp Save), sama dgn web.
      for (final r in items) {
        if (r.isOption) r.unit = r.unitSelected;
      }
    }
    final wo = workorder;
    return {
      'date': date == null ? null : formatDateTime(date!),
      'equipment_id': equipment['id'],
      'executor_id': executorId,
      'classification_id': classificationId,
      'work_order': workOrder,
      'notification': wo['Notification'],
      'no_workorder': wo['WorkOrder'],
      'equipment': wo['Equipment'],
      'oprshorttext': wo['Oprshorttext'],
      'oprworkcenter': wo['OprWorkcenter'],
      'description': wo['Description'],
      'executed': executed,
      'reason_not_executed': reasonNotExecuted,
      if (dataParameter?['pic_id'] != null) 'pic_id': dataParameter!['pic_id'],
      'is_unsafe_condition': dataParameter?['is_unsafe_condition'] == true,
      'final': isFinal,
      'attachment_mode': attachmentMode,
      'item_parameter': [
        for (final r in items)
          {
            'id': r.id,
            'parameter': r.parameter,
            'gruptasklist_id': r.gruptasklistId,
            'method': r.method,
            'value': r.value, // web tetap mengirim value walau field disembunyikan (is_option)
            'unit': r.unit,
            'rt_ta': r.rtTa,
            'analysis': r.analysis,
            'recommendation': r.recommendation,
            'evaluation': r.evaluation,
            'grade': r.grade,
          },
      ],
      if (executed)
        'personel_workorder': [
          for (final p in personel)
            {
              'id': p.id,
              'personel': p.personel,
              'shift': p.shift,
              'start_date': p.startDate == null ? null : formatDateTime(p.startDate!),
              'finish_date': p.finishDate == null ? null : formatDateTime(p.finishDate!),
              'note': p.note,
            },
        ],
    };
  }

  static Map<String, String> _descriptions(Object? raw) => raw is Map
      ? raw.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''))
      : {};

  static Map<String, String> descriptionsFrom(Object? raw) => _descriptions(raw);
}

int? _int(Object? v) => v == null || v == '' ? null : int.tryParse(v.toString());

bool _bool(Object? v) => v == true || v == 1 || v == '1' || v == 'true';
