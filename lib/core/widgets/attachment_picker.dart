import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../form_submit.dart';
import '../theme.dart';

/// Field lampiran (foto kamera/galeri, PDF) — pengganti input file web
/// (accept="image/*, application/pdf" multiple). [files] diubah langsung.
class AttachmentPicker extends StatelessWidget {
  const AttachmentPicker({
    super.key,
    required this.files,
    required this.onChanged,
    this.label = 'Lampiran (foto/PDF)',
    this.required = false,
    this.enabled = true,
    this.errorText,
    this.helper,
  });

  final List<AttachmentFile> files;
  final VoidCallback onChanged;
  final String label;
  final bool required;
  final bool enabled;
  final String? errorText;

  /// Baris info tambahan di atas daftar file (mis. "2 lampiran tersimpan").
  final Widget? helper;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: required ? '$label *' : label,
        errorText: errorText,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ?helper,
          for (final (i, file) in files.indexed)
            Row(children: [
              const Icon(Icons.attach_file, size: 16),
              const SizedBox(width: 4),
              Expanded(child: Text(file.name, overflow: TextOverflow.ellipsis)),
              if (enabled)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () {
                    files.removeAt(i);
                    onChanged();
                  },
                ),
            ]),
          if (files.isEmpty && helper == null && !enabled)
            const Text('-', style: TextStyle(color: ApmColors.muted)),
          if (enabled)
            Wrap(spacing: 8, children: [
              ActionChip(
                avatar: const Icon(Icons.photo_camera_outlined, size: 18),
                label: const Text('Kamera'),
                onPressed: () => _pickImage(ImageSource.camera),
              ),
              ActionChip(
                avatar: const Icon(Icons.photo_library_outlined, size: 18),
                label: const Text('Galeri'),
                onPressed: () => _pickImage(ImageSource.gallery),
              ),
              ActionChip(
                avatar: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: const Text('PDF'),
                onPressed: _pickPdf,
              ),
            ]),
        ],
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final picker = ImagePicker();
    if (source == ImageSource.gallery) {
      final imgs = await picker.pickMultiImage(imageQuality: 80, maxWidth: 2048);
      files.addAll(imgs.map((x) => AttachmentFile(x.path, x.name)));
    } else {
      final x = await picker.pickImage(source: source, imageQuality: 80, maxWidth: 2048);
      if (x != null) files.add(AttachmentFile(x.path, x.name));
    }
    onChanged();
  }

  Future<void> _pickPdf() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
    files.addAll(picked.where((p) => p.path != null).map((p) => AttachmentFile(p.path!, p.name)));
    onChanged();
  }
}

/// True bila nama file berekstensi foto yang diterima e-Posh.
bool isPhotoFile(String name, List<String> extensions) =>
    extensions.contains(name.split('.').last.toLowerCase());
