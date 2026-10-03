import 'dart:io';

import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

class ImageService {
  Future<String> saveImage(String pickedPath, String localId) async {
    final docsDir = await getApplicationDocumentsDirectory();
    final imagesDir = Directory(join(docsDir.path, 'images'));

    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }

    final fileName = '${localId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final newPath = join(imagesDir.path, fileName);

    final savedFile = await File(pickedPath).copy(newPath);
    return savedFile.path;
  }

  Future<void> deleteImage(String? path) async {
    if (path == null) return;
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }
}
