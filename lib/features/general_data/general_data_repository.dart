import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/form_submit.dart';
import 'general_data_form.dart';

/// Hasil pencarian equipment (web: general-logbook.searchEquipment).
class EquipmentHit {
  EquipmentHit(this.id, String label)
      : name = label.split('  ---  ').first.trim(),
        description = label.contains('  ---  ') ? label.split('  ---  ').last.trim() : '';

  final int id;
  final String name;
  final String description;
}

/// Detail equipment + 5 temuan terbuka terakhir (web: halaman Create Notif).
class EquipmentSummary {
  EquipmentSummary(this.raw);

  final Map<String, dynamic> raw;

  int get id => raw['id'] as int;
  String get name => raw['name']?.toString() ?? '-';
  String? get description => raw['description']?.toString();
  String get location => [raw['factory'], raw['plant']].whereType<Object>().join(' - ');
  String? get abcIndicator => raw['abc_indicator']?.toString();
  List<Map<String, dynamic>> get history => (raw['history'] as List? ?? const [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
}

class SavedLogbook {
  SavedLogbook(this.id, this.no, this.next);

  final int id;
  final String no;

  /// index | bypass | moc — bypass/moc dilanjutkan di APM web.
  final String next;
}

class GeneralDataRepository {
  GeneralDataRepository(this._ref);

  final Ref _ref;

  Dio get _dio => _ref.read(dioProvider);

  Future<List<EquipmentHit>> searchEquipment(String q, {CancelToken? cancelToken}) async {
    final res = await _dio.get('/general-data/equipment',
        queryParameters: {'q': q}, cancelToken: cancelToken);
    return (res.data['data'] as List)
        .map((e) => EquipmentHit((e as Map)['value'] as int, e['label'].toString()))
        .toList();
  }

  Future<EquipmentSummary> equipment(int id) async {
    final res = await _dio.get('/general-data/equipment/$id');
    return EquipmentSummary(Map<String, dynamic>.from(res.data['data'] as Map));
  }

  Future<GeneralDataForm> loadForm(int equipmentId) async {
    final res = await _dio.get('/general-data/form', queryParameters: {'equipment_id': equipmentId});
    return GeneralDataForm.fromResponse(Map<String, dynamic>.from(res.data['data'] as Map));
  }

  Future<Map<String, String>> evaluationDescriptions(int classificationId) async {
    final res = await _dio.get('/evaluation-descriptions/$classificationId');
    final raw = res.data['data'];
    return raw is Map ? raw.map((k, v) => MapEntry(k.toString(), v?.toString() ?? '')) : {};
  }

  Future<EposhMaster> eposhMaster() async {
    final res = await _dio.get('/general-data/eposh/master');
    return EposhMaster(Map<String, dynamic>.from(res.data['data'] as Map));
  }

  Future<List<EposhOption>> bagian(int departmentId) async {
    final res = await _dio.get('/general-data/eposh/bagian', queryParameters: {'department_id': departmentId});
    return EposhOption.listFrom(res.data['data']);
  }

  Future<Map<String, dynamic>?> riskCategory(String likelihood, String consequence, String? affectedObject) async {
    final res = await _dio.get('/general-data/eposh/risk-category', queryParameters: {
      'likelihood': likelihood,
      'consequence': consequence,
      'affected_object': ?affectedObject,
    });
    final d = res.data['data'];
    return d is Map ? Map<String, dynamic>.from(d) : null;
  }

  Future<SavedLogbook> submit(Map<String, dynamic> payload, List<AttachmentFile> files) async {
    final res = await postMultipart(_dio, '/general-data', payload, files);
    final d = res.data['data'] as Map;
    return SavedLogbook(d['id'] as int, d['no'].toString(), d['next']?.toString() ?? 'index');
  }
}

final generalDataRepositoryProvider = Provider(GeneralDataRepository.new);
