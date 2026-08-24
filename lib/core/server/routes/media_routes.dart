import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../api_context.dart';

/// `/upload/image`, `/uploads/<name>` — mahsulot rasmlari.
class MediaRoutes {
  const MediaRoutes._();

  static void register(Router router) {
    // 6. Image Sync
    router.post('/upload/image', (Request request) async {
      final List<int> bytes = await request
          .read()
          .expand((chunk) => chunk)
          .toList();
      final imagesDir = await ApiContext.getImagesDir();

      // Simple file name with timestamp
      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}.jpg'; // Assuming jpg or handle mime
      final file = File(p.join(imagesDir.path, fileName));
      await file.writeAsBytes(bytes);

      return Response.ok(jsonEncode({'fileName': fileName}));
    });

    router.get('/uploads/<name>', (Request request, String name) async {
      final imagesDir = await ApiContext.getImagesDir();
      final file = File(p.join(imagesDir.path, name));

      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        String contentType = 'image/jpeg';
        if (name.endsWith('.png')) contentType = 'image/png';
        if (name.endsWith('.webp')) contentType = 'image/webp';

        return Response.ok(bytes, headers: {'Content-Type': contentType});
      }
      return Response.notFound('Image not found');
    });

  }
}
