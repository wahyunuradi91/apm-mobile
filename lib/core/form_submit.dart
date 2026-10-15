import 'package:dio/dio.dart';

/// File lampiran yang dipilih user (kamera/galeri/PDF).
class AttachmentFile {
  AttachmentFile(this.path, this.name);

  final String path;
  final String name;
}

/// Error validasi 422 dari Laravel: `errors` per field (mis. item_parameter.0.analysis).
class ValidationError implements Exception {
  ValidationError(this.message, this.errors);

  final String message;
  final Map<String, List<String>> errors;

  @override
  String toString() => message;
}

/// POST multipart dengan kunci bersarang notasi PHP (item_parameter[0][parameter], file[]),
/// sama dengan FormData halaman web. bool → '1'/'0', null → '' (ConvertEmptyStringsToNull).
/// Melempar [ValidationError] untuk respons 422.
Future<Response> postMultipart(
  Dio dio,
  String path,
  Map<String, dynamic> payload,
  List<AttachmentFile> files,
) async {
  final form = FormData();
  void add(String key, Object? v) {
    if (v is Map) {
      v.forEach((k, val) => add('$key[$k]', val));
    } else if (v is List) {
      for (var i = 0; i < v.length; i++) {
        add('$key[$i]', v[i]);
      }
    } else if (v is bool) {
      form.fields.add(MapEntry(key, v ? '1' : '0'));
    } else {
      form.fields.add(MapEntry(key, v?.toString() ?? ''));
    }
  }

  payload.forEach(add);
  for (final f in files) {
    form.files.add(MapEntry('file[]', await MultipartFile.fromFile(f.path, filename: f.name)));
  }

  try {
    return await dio.post(
      path,
      data: form,
      options: Options(sendTimeout: const Duration(minutes: 2)),
    );
  } on DioException catch (e) {
    final body = e.response?.data;
    if (e.response?.statusCode == 422 && body is Map) {
      final errors = <String, List<String>>{};
      (body['errors'] as Map? ?? const {}).forEach((k, v) {
        errors[k.toString()] = (v as List).map((e) => e.toString()).toList();
      });
      throw ValidationError(body['message']?.toString() ?? 'Data belum valid.', errors);
    }
    rethrow;
  }
}
