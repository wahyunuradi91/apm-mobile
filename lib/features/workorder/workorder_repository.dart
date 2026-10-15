import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';

/// Bentuk mengikuti `App\Http\Resources\Mobile\WorkorderResource` /
/// `WorkorderDetailResource` di backend — kolom tabel web Workorder/Index.vue.
class Workorder {
  Workorder(this.raw);

  final Map<String, dynamic> raw;

  String get number => raw['work_order']?.toString() ?? '-';
  String get description => raw['description']?.toString() ?? '-';
  String? get notification => raw['notification']?.toString();
  List<String> get ucReportNumbers =>
      (raw['uc_report_numbers'] as List? ?? const []).map((e) => e.toString()).toList();
  String? get rtta => raw['rtta']?.toString();
  String? get maintenancePlan => _blank(raw['maintenance_plan']);
  String? get plantSection => _blank(raw['plant_section']);
  String? get sapStatus => raw['sap_status']?.toString();
  String? get basicStart => raw['basic_start']?.toString();
  String? get basicFinish => raw['basic_finish']?.toString();
  String? get duration => raw['duration']?.toString();
  String get equipmentTag => (raw['equipment'] as Map?)?['tag']?.toString() ?? '-';
  String? get equipmentName => (raw['equipment'] as Map?)?['description']?.toString();
  String? get plant => raw['plant']?.toString();
  String? get section => raw['section']?.toString();
  String? get workcenterDescription => (raw['workcenter'] as Map?)?['description']?.toString();
  String? get workcenter {
    final wc = raw['workcenter'] as Map?;
    if (wc == null) return null;
    return [wc['code'], wc['description']].whereType<Object>().join(' · ');
  }

  // ---- badge (sama dengan kolom pertama tabel web) ----
  bool get isPpm => raw['is_ppm'] == true;
  bool get isReported => raw['is_reported'] == true;

  /// CNF / PCNF / null.
  String? get confirmationStatus => raw['confirmation_status']?.toString();
  int get konfirmasiCount => raw['konfirmasi_count'] as int? ?? 0;
  bool get allNotExecuted => raw['all_not_executed'] == true;
  String? get readinessStatus => (raw['readiness'] as Map?)?['status']?.toString();
  String? get readinessEstimate => (raw['readiness'] as Map?)?['execution_estimate']?.toString();

  /// Web: "Backlog" bila belum ada konfirmasi, finish < hari ini, status REL/CRTD.
  bool get isBacklog {
    if (konfirmasiCount > 0) return false;
    final finish = DateTime.tryParse(basicFinish ?? '');
    final s = sapStatus ?? '';
    return finish != null &&
        _dateOnly(finish).isBefore(_dateOnly(DateTime.now())) &&
        (s.contains('REL') || s.contains('CRTD'));
  }

  /// Web: "Today" bila belum ada konfirmasi & basic start = hari ini (dan bukan backlog).
  bool get isToday {
    if (konfirmasiCount > 0 || isBacklog) return false;
    final start = DateTime.tryParse(basicStart ?? '');
    return start != null && _dateOnly(start) == _dateOnly(DateTime.now());
  }

  /// Web: tombol "Lihat Report" bila sudah reported atau status SAP mengandung CNF.
  bool get hasReport => isReported || (sapStatus?.contains('CNF') ?? false);

  List<WorkorderOperation> get operations => (raw['operations'] as List? ?? const [])
      .map((e) => WorkorderOperation(Map<String, dynamic>.from(e as Map)))
      .toList();

  List<Map<String, dynamic>> get reports => (raw['reports'] as List? ?? const [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();

  int get reportCount => reports.length;

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
  static String? _blank(Object? v) {
    final s = v?.toString();
    return (s == null || s.trim().isEmpty) ? null : s;
  }
}

class WorkorderOperation {
  WorkorderOperation(this.raw);

  final Map<String, dynamic> raw;

  /// PK workorders bertipe string di backend (mis. "4000008382330001").
  String get id => raw['id'].toString();
  String? get pic => raw['pic']?.toString();
  String get activity => raw['activity']?.toString() ?? '-';
  String get shortText => raw['short_text']?.toString() ?? '-';
  String? get duration {
    final d = raw['normal_duration'];
    return d == null ? null : '$d ${raw['duration_unit'] ?? ''}'.trim();
  }

  bool get confirmed => raw['confirmed'] == true;
  bool get notExecuted => raw['executed'] == false;
}

/// Definisi satu filter panel web (Filter::jsonSerialize di backend).
class WoFilterDef {
  WoFilterDef(Map raw)
      : paramName = raw['paramName'].toString(),
        label = raw['label']?.toString() ?? raw['name'].toString(),
        component = raw['componentName']?.toString() ?? 'dropdown-filter',
        options = (raw['options'] as List? ?? const [])
            .map((o) => MapEntry((o as Map)['name'].toString(), o['value']?.toString() ?? ''))
            .toList();

  final String paramName;
  final String label;

  /// dropdown-filter | dropdown-filter-multiple | date-range-filter
  final String component;

  /// key = nilai yang dikirim, value = label.
  final List<MapEntry<String, String>> options;

  bool get isMultiple => component == 'dropdown-filter-multiple';
  bool get isDateRange => component == 'date-range-filter';
}

class WorkorderPage {
  WorkorderPage(this.items, this.currentPage, this.hasMore);

  final List<Workorder> items;
  final int currentPage;

  /// Backend memakai simplePaginate (tanpa count total) — cukup tahu ada halaman berikut.
  final bool hasMore;
}

class WorkorderRepository {
  WorkorderRepository(this._ref);

  final Ref _ref;

  /// [filters] = parameter filter-* persis seperti query string halaman web.
  Future<WorkorderPage> fetch({
    int page = 1,
    String? search,
    Map<String, String> filters = const {},
    CancelToken? cancelToken,
  }) async {
    final res = await _ref.read(dioProvider).get('/workorders', cancelToken: cancelToken, queryParameters: {
      'page': page,
      'per_page': 20,
      if (search != null && search.isNotEmpty) 'search': search,
      ...filters,
    });
    final meta = res.data['meta'] as Map;
    return WorkorderPage(
      (res.data['data'] as List)
          .map((e) => Workorder(Map<String, dynamic>.from(e as Map)))
          .toList(),
      meta['current_page'] as int,
      meta['has_more'] == true,
    );
  }

  Future<List<WoFilterDef>> filterDefinitions() async {
    final res = await _ref.read(dioProvider).get('/workorders/filters');
    return (res.data['data'] as List).map((e) => WoFilterDef(e as Map)).toList();
  }

  Future<Workorder> show(String workOrder) async {
    final res = await _ref.read(dioProvider).get('/workorders/$workOrder');
    return Workorder(Map<String, dynamic>.from(res.data['data'] as Map));
  }
}

final workorderRepositoryProvider = Provider(WorkorderRepository.new);

final workorderFilterDefsProvider = FutureProvider<List<WoFilterDef>>(
  (ref) => ref.read(workorderRepositoryProvider).filterDefinitions(),
);

final workorderDetailProvider = FutureProvider.autoDispose.family<Workorder, String>(
  (ref, id) => ref.read(workorderRepositoryProvider).show(id),
);
