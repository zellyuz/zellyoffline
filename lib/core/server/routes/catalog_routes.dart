import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../database_helper.dart';

/// `/products`, `/categories`, `/printers`, `/settings` — menyu va
/// mijoz ilovasiga ochiq sozlamalar.
class CatalogRoutes {
  const CatalogRoutes._();

  static void register(Router router) {
    // 3. Products
    router.get('/products', (Request request) async {
      final data = await DatabaseHelper.instance.queryAll('products');
      // Strip full paths from image_path for remote clients
      final processedData = data.map((item) {
        final newItem = Map<String, dynamic>.from(item);
        if (newItem['image_path'] != null) {
          newItem['image_path'] = p.basename(newItem['image_path'] as String);
        }
        return newItem;
      }).toList();
      return Response.ok(jsonEncode(processedData));
    });

    router.get('/categories', (Request request) async {
      final data = await DatabaseHelper.instance.queryAll('categories');
      return Response.ok(jsonEncode(data));
    });

    // Printers — mobil ilova uchun
    router.get('/printers', (Request request) async {
      try {
        final db = await DatabaseHelper.instance.database;
        final printers = await db.query('printers');
        final result = printers.map((p) {
          final row = Map<String, dynamic>.from(p);
          // category_ids: JSON array → List<int>
          final catRaw = row['category_ids']?.toString() ?? '';
          List<int> catIds = [];
          if (catRaw.isNotEmpty) {
            try {
              catIds = List<int>.from(jsonDecode(catRaw));
            } catch (_) {
              catIds = catRaw
                  .split(',')
                  .map((e) => int.tryParse(e.trim()) ?? 0)
                  .where((e) => e != 0)
                  .toList();
            }
          }
          row['category_ids'] = catIds;
          // is_main: int → bool
          row['is_main'] = (row['is_main'] as int? ?? 0) == 1;
          return row;
        }).toList();
        return Response.ok(
          jsonEncode(result),
          headers: {'Content-Type': 'application/json'},
        );
      } catch (e) {
        return Response.internalServerError(body: jsonEncode({'error': '$e'}));
      }
    });

    // Settings — mobil ilova uchun kerakli sozlamalar
    router.get('/settings', (Request request) async {
      try {
        final db = await DatabaseHelper.instance.database;
        final rows = await db.query('settings');

        // Faqat mobil ilovaga kerakli kalitlar
        const allowedKeys = {
          'restaurant_name',
          'receipt_restaurant_name',
          'receipt_branch_name',
          'receipt_phone',
          'receipt_address',
          'receipt_footer_message',
          'receipt_show_room_charges',
          'receipt_layout_type',
          'receipt_cut_paper',
          'receipt_feed_lines',
          'receipt_horizontal_margin',
          'kitchen_header_text',
          'kitchen_font_large',
          'kitchen_group_by_category',
          'kitchen_show_order_number',
          'kitchen_show_table',
          'kitchen_show_waiter',
          'kitchen_cut_paper',
          'kitchen_feed_lines',
          'auto_confirm_order',
          'enable_inventory',
        };

        final Map<String, dynamic> result = {};
        for (final row in rows) {
          final key = row['key'] as String;
          if (allowedKeys.contains(key)) {
            result[key] = row['value'];
          }
        }
        return Response.ok(
          jsonEncode(result),
          headers: {'Content-Type': 'application/json'},
        );
      } catch (e) {
        return Response.internalServerError(body: jsonEncode({'error': '$e'}));
      }
    });

  }
}
