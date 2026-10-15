import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_client.dart';
import '../../../core/form_submit.dart';
import 'confirmation_form.dart';

export '../../../core/form_submit.dart' show AttachmentFile;

/// Error validasi 422 — lihat [ValidationError].
typedef ConfirmationValidationError = ValidationError;

class ConfirmationRepository {
  ConfirmationRepository(this._ref);

  final Ref _ref;

  String _path(String workOrder, String operationId) =>
      '/workorders/$workOrder/operations/$operationId/confirmation';

  Future<ConfirmationForm> load(String workOrder, String operationId) async {
    final res = await _ref.read(dioProvider).get(_path(workOrder, operationId));
    return ConfirmationForm.fromResponse(Map<String, dynamic>.from(res.data['data'] as Map));
  }

  Future<Map<String, String>> evaluationDescriptions(int classificationId) async {
    final res = await _ref.read(dioProvider).get('/evaluation-descriptions/$classificationId');
    return ConfirmationForm.descriptionsFrom(res.data['data']);
  }

  /// Kirim multipart (sama dengan Inertia web saat ada file).
  Future<String> submit(
    String workOrder,
    String operationId,
    Map<String, dynamic> payload,
    List<AttachmentFile> files,
  ) async {
    final res =
        await postMultipart(_ref.read(dioProvider), _path(workOrder, operationId), payload, files);
    return res.data['message']?.toString() ?? 'Berhasil disimpan.';
  }
}

final confirmationRepositoryProvider = Provider(ConfirmationRepository.new);
