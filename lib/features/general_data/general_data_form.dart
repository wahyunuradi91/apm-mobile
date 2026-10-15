import 'package:intl/intl.dart';

import '../workorder/confirmation/confirmation_form.dart' show Json, Option;

/// Model form Create General Data — meniru
/// apm/resources/js/Pages/Transaction/General-Logbook/Create.vue.
/// Sumber: GET /general-data/form → `form` (= props halaman web) + data pendukung.

/// Opsi e-Posh: bisa {value,label,meta,description} (API) atau string polos (cadangan config).
class EposhOption {
  EposhOption(this.value, this.label, {this.meta, this.description});

  final Object value;
  final String label;
  final String? meta;
  final String? description;

  static List<EposhOption> listFrom(Object? raw) => (raw as List? ?? const []).map((e) {
        if (e is Map) {
          return EposhOption(e['value'] as Object, e['label']?.toString() ?? '${e['value']}',
              meta: e['meta']?.toString(), description: e['description']?.toString());
        }
        return EposhOption(e.toString(), e.toString());
      }).toList();
}

/// Master dropdown Unsafe Condition (GET /general-data/eposh/master).
class EposhMaster {
  EposhMaster(Json raw)
      : affectedObject = EposhOption.listFrom(raw['affected_object']),
        likelihood = EposhOption.listFrom(raw['likelihood']),
        sumberTemuan = EposhOption.listFrom(raw['sumber_temuan']),
        departments = EposhOption.listFrom(raw['departments']),
        consequenceByObject = (raw['consequence_by_object'] as Map? ?? const {})
            .map((k, v) => MapEntry(k.toString(), EposhOption.listFrom(v))),
        degraded = raw['degraded'] == true;

  EposhMaster.empty()
      : affectedObject = const [],
        likelihood = const [],
        sumberTemuan = const [],
        departments = const [],
        consequenceByObject = const {},
        degraded = false;

  final List<EposhOption> affectedObject;
  final List<EposhOption> likelihood;
  final List<EposhOption> sumberTemuan;
  final List<EposhOption> departments;
  final Map<String, List<EposhOption>> consequenceByObject;
  final bool degraded;
}

/// Satu baris item parameter (`item_parameter[i]`).
class GdItemRow {
  GdItemRow({this.departmentId, this.partId});

  String? parameter;
  String? method;
  String? value;
  String? unit;
  String? rtTa;
  String? analysis;
  String? recommendation;
  String? evaluation;
  num grade = 0;

  // Unsafe Condition (eposh.unsafe_condition_details).
  String? affectedObject;
  String? likelihood;
  String? source;
  String? consequence;
  int? departmentId;
  int? partId;
  DateTime? dueDate;

  // Hanya UI.
  /// Pilihan satuan dari tasklist PPM (mis. Comply/Not Comply) — chip pengisi UoM.
  List<String> unitChoices = [];
  Json? riskCategory;
  bool riskLoading = false;
  int riskToken = 0;
}

class GeneralDataForm {
  GeneralDataForm._(this.data, this.form);

  final Json data;
  final Json form;

  Json get equipment => Map<String, dynamic>.from(form['equipment'] as Map);
  String get equipmentName => equipment['name']?.toString() ?? '-';
  String get session => form['session']?.toString() ?? '';
  bool get isAJG => form['isAJG'] == true;
  num get effectValue => num.tryParse('${equipment['effect_value'] ?? 0}') ?? 0;
  bool get hasCostCenter => equipment['cost_center_id'] != null;
  bool get isSce => equipment['abc_indicator'] == 'SCE';

  bool get unsafeEnabled => data['unsafe_condition_enabled'] == true;
  List<String> get photoExtensions =>
      (data['photo_extensions'] as List? ?? const []).map((e) => e.toString().toLowerCase()).toList();
  List<Json> get maintenanceActivities => (data['maintenance_activities'] as List? ?? const [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();

  List<Option> get executorOptions => Option.listFrom(form['executors']);
  List<Option> get classificationOptions => Option.listFrom(form['classification']);
  List<Option> get typeRtOptions => Option.listFrom(form['typeRT']);
  List<Option> get evaluationOptions => Option.listFrom(form['evaluationType']);
  List<String> get likelihoodFallback =>
      (form['likelihoodOptions'] as List? ?? const []).map((e) => e.toString()).toList();
  List<String> get consequenceFallback =>
      (form['consequenceOptions'] as List? ?? const []).map((e) => e.toString()).toList();
  int? get eposhDepartmentPrefill => _int(form['eposhDepartmentPrefill']);
  int? get eposhPartPrefill => _int(form['eposhPartPrefill']);

  /// itemParameterType = PPMService::findPrameter (value, label, item{unit, pgpr, tasklist, is_option}).
  List<Json> get itemParameterType => (form['itemParameterType'] as List? ?? const [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();

  // ---------------- state yang diedit ----------------
  DateTime date = DateTime.now();
  String workOrder = '';
  String? notification;
  int? executorId;
  int? classificationId;
  int? maintenanceActivityId;
  bool unsafe = false;
  final List<GdItemRow> items = [];
  Map<String, String> evaluationDescriptions = {};

  factory GeneralDataForm.fromResponse(Json data) {
    final f = GeneralDataForm._(data, Map<String, dynamic>.from(data['form'] as Map));
    f._init();
    return f;
  }

  void _init() {
    // data() web :825-835
    workOrder = form['no_work_order']?.toString() ?? '';
    notification = form['notif']?.toString();
    executorId = _int((equipment['executor'] as Map?)?['id']) ?? _int(form['currentExecutor']);
    classificationId = _int(form['currentClassification']);
    evaluationDescriptions = _descriptions(form['evaluationDescriptions']);
    // mounted: openPopUpLogbook() — satu baris awal.
    addItem();
  }

  /// web openPopUpLogbook: Unsafe Condition = satu temuan, tidak boleh menambah baris.
  GdItemRow? addItem() {
    if (unsafe && items.isNotEmpty) return null;
    final row = GdItemRow(departmentId: eposhDepartmentPrefill, partId: eposhPartPrefill);
    items.add(row);
    return row;
  }

  /// web onParameterChange: unit, method, rekomendasi dari tasklist (rt_ta tidak diisi).
  void onParameterSelected(GdItemRow row, String value) {
    row.parameter = value;
    final found = itemParameterType.where((p) => p['value'] == value).firstOrNull;
    final it = found?['item'] is Map ? Map<String, dynamic>.from(found!['item'] as Map) : null;
    if (it == null) {
      row.unitChoices = [];
      return;
    }
    row
      ..unit = it['unit']?.toString()
      ..method = it['pgpr']?.toString()
      ..recommendation = it['tasklist']?.toString();
    final unit = it['unit']?.toString() ?? '';
    final choices = unit.split('/').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    row.unitChoices = _bool(it['is_option']) && choices.length > 1 ? choices : [];
  }

  /// web clearParameter.
  void clearParameter(GdItemRow row) {
    row
      ..parameter = null
      ..unit = null
      ..rtTa = null
      ..method = null
      ..recommendation = null
      ..unitChoices = [];
  }

  /// web calculateGrade: GOOD 1 … BREAKDOWN 5 × effect_value equipment.
  num gradeFor(String? evaluation) {
    const factor = {'GOOD': 1, 'CONSIDERABLE': 2, 'WARNING': 3, 'BAD': 4, 'BREAKDOWN': 5};
    return (factor[evaluation] ?? 0) * effectValue;
  }

  /// web onMaintenanceActivitySelected.
  void applyMaintenanceActivity(Json a) {
    maintenanceActivityId = _int(a['value']);
    if (a['no_wo'] != null && '${a['no_wo']}'.isNotEmpty) workOrder = a['no_wo'].toString();
    if (a['notif'] != null && '${a['notif']}'.isNotEmpty) notification = a['notif'].toString();
    if (a['executor_id'] != null) executorId = _int(a['executor_id']);
    if (items.isEmpty) addItem();
    final row = items.first
      ..parameter = a['item']?.toString()
      ..analysis = a['description']?.toString();
    if (a['evaluation'] != null) {
      row
        ..evaluation = a['evaluation'].toString()
        ..grade = gradeFor(row.evaluation);
    }
  }

  /// web computed disabled: kolom wajib per baris.
  List<String> missingFor(GdItemRow r) => [
        if (_blank(r.parameter)) 'Parameter',
        if (_blank(r.rtTa)) 'RT/TA',
        if (_blank(r.analysis)) 'Analysis',
        if (_blank(r.evaluation)) 'Evaluation',
        if (unsafe && _blank(r.affectedObject)) 'Objek Terdampak',
        if (unsafe && _blank(r.likelihood)) 'Likelihood',
        if (unsafe && _blank(r.consequence)) 'Consequence',
        if (unsafe && r.departmentId == null) 'Department',
      ];

  bool get costCenterBlocked => (classificationId == 13 || classificationId == 1) && !hasCostCenter;

  String? get classificationLabel =>
      classificationOptions.where((o) => o.value == classificationId).firstOrNull?.label;

  /// Payload = FormData web submit() (:1504-1606).
  Map<String, dynamic> toPayload() => {
        'date': DateFormat('yyyy-MM-dd HH:mm:ss').format(date),
        'equipment_id': equipment['id'],
        'executor_id': executorId,
        'classification_id': classificationId,
        'work_order': workOrder,
        'notification': notification,
        'is_unsafe_condition': unsafe,
        if (maintenanceActivityId != null) 'maintenance_activity_id': maintenanceActivityId,
        'item_parameter': [
          for (final r in items)
            {
              'parameter': r.parameter,
              'method': r.method,
              'value': r.value,
              'unit': r.unit,
              'rt_ta': r.rtTa,
              'analysis': r.analysis,
              'recommendation': r.recommendation,
              'evaluation': r.evaluation,
              'grade': r.grade,
              'affected_object': r.affectedObject,
              'likelihood': r.likelihood,
              'source': r.source,
              'consequence': r.consequence,
              // Hanya untuk Unsafe Condition — baris non-unsafe ikut terprefill dari peta
              // plant, dan server membuat detail unsafe begitu ada satu nilai saja.
              // (Web hanya menjaga department_id; part_id ikut dijaga di sini.)
              'department_id': unsafe ? r.departmentId : null,
              'part_id': unsafe ? r.partId : null,
              'due_date': r.dueDate == null ? null : DateFormat('yyyy-MM-dd').format(r.dueDate!),
            },
        ],
      };

  static Map<String, String> _descriptions(Object? raw) =>
      raw is Map ? raw.map((k, v) => MapEntry(k.toString(), v?.toString() ?? '')) : {};
}

int? _int(Object? v) => v == null || v == '' ? null : int.tryParse(v.toString());

bool _bool(Object? v) => v == true || v == 1 || v == '1' || v == 'true';

bool _blank(String? s) => s == null || s.trim().isEmpty;
