import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../../repositories/inventory_repository.dart';
import '../../database_helper.dart';
import '../api_context.dart';
import '../pagination.dart';

/// `/inventory/*` — ombor. Faqat admin/kassir uchun.
///
/// Ombor moduli desktopda bor edi, lekin tarmoqqa umuman chiqmagan. Admin
/// mobil ilovasi uchun eng kerakli uchta ko'rinish shu yerda: qoldiq,
/// kam qolganlar va harakatlar tarixi.
///
/// **Faqat o'qish.** Kirim/chiqim yozish ataylab qo'shilmadi: u tannarx
/// hisobini va tranzaksiya chegaralarini o'zgartiradi
/// ([InventoryRepository.applyStockBatch]), telefonda esa xato bosish oson.
/// Kerak bo'lsa alohida, o'ylangan holda qo'shiladi.
class InventoryRoutes {
  const InventoryRoutes._();

  static void register(Router router) {
    // ── Qoldiq ──────────────────────────────────────────────────────────
    //
    // `?kind=ingredient|product` — faqat bitta turini olish.
    // `?low_only=true`           — faqat eng kam chegaradan tushganlar.
    router.get('/inventory/stock', (Request request) async {
      try {
        final q = request.url.queryParameters;
        final kind = q['kind'];
        final lowOnly = q['low_only'] == 'true';
        final repo = InventoryRepository();

        final items = <Map<String, dynamic>>[];

        if (kind == null || kind == 'ingredient') {
          for (final row in await repo.getIngredientsWithStock()) {
            final onHand = (row['on_hand'] as num?)?.toDouble() ?? 0.0;
            final minStock = (row['min_stock'] as num?)?.toDouble() ?? 0.0;
            final isLow = minStock > 0 && onHand <= minStock;
            if (lowOnly && !isLow) continue;
            items.add({
              'kind': 'ingredient',
              'id': row['id'],
              'name': row['name'],
              'unit': row['base_unit'],
              'on_hand': onHand,
              'min_stock': minStock,
              'is_low': isLow,
              'avg_cost': (row['avg_cost'] as num?)?.toDouble() ?? 0.0,
            });
          }
        }

        if (kind == null || kind == 'product') {
          // Mahsulot qoldig'i `products.quantity` da; `track_type = 0`
          // (kuzatilmaydigan) mahsulotlar qoldiqqa kirmaydi.
          final db = await DatabaseHelper.instance.database;
          final rows = await db.rawQuery('''
            SELECT id, name, unit, quantity, product_type, avg_cost
            FROM products
            WHERE is_active = 1 AND track_type != 0
            ORDER BY name ASC
          ''');
          for (final row in rows) {
            final onHand = (row['quantity'] as num?)?.toDouble() ?? 0.0;
            // Mahsulot uchun eng kam chegara sozlamasi yo'q — "kam" deb
            // faqat nol yoki manfiy qoldiq hisoblanadi.
            final isLow = onHand <= 0;
            if (lowOnly && !isLow) continue;
            items.add({
              'kind': 'product',
              'id': row['id'],
              'name': row['name'],
              'unit': row['unit'] ?? 'dona',
              'on_hand': onHand,
              'min_stock': 0.0,
              'is_low': isLow,
              'product_type': row['product_type'],
              'avg_cost': (row['avg_cost'] as num?)?.toDouble() ?? 0.0,
            });
          }
        }

        return Response.ok(
          jsonEncode({
            'enabled': await ApiContext.inventoryEnabled(),
            'items': items,
            'low_count': items.where((i) => i['is_low'] == true).length,
          }),
          headers: ApiContext.jsonHeaders,
        );
      } catch (e) {
        return Response.internalServerError(
          body: jsonEncode({'error': '$e'}),
          headers: ApiContext.jsonHeaders,
        );
      }
    });

    // ── Harakatlar tarixi ───────────────────────────────────────────────
    //
    // Filtrlar: `?start`, `?end`, `?types=IN,OUT`, `?source=ingredient|product`,
    // `?item_id`, `?search` + sahifalash (`?limit`, `?offset`).
    router.get('/inventory/movements', (Request request) async {
      try {
        final q = request.url.queryParameters;
        final page = Pagination.of(request);
        final repo = InventoryRepository();

        final from = q['start'] != null ? DateTime.tryParse(q['start']!) : null;
        final to = q['end'] != null ? DateTime.tryParse(q['end']!) : null;
        final types = q['types']
            ?.split(',')
            .map((t) => t.trim())
            .where((t) => t.isNotEmpty)
            .toList();

        final rows = await repo.getHistory(
          from: from,
          to: to,
          types: types == null || types.isEmpty ? null : types,
          itemId: int.tryParse(q['item_id'] ?? ''),
          source: q['source'],
          search: q['search'],
          // Sahifalash so'ralmasa ham cheklov qo'yamiz: harakatlar jurnali
          // yillar davomida o'sadi, butunini tarmoqqa chiqarish mumkin emas.
          limit: page.enabled ? page.limit : Pagination.maxLimit,
          offset: page.enabled ? page.offset : 0,
        );

        int? total;
        if (page.enabled) {
          total = await repo.getHistoryCount(
            from: from,
            to: to,
            types: types == null || types.isEmpty ? null : types,
            itemId: int.tryParse(q['item_id'] ?? ''),
            source: q['source'],
            search: q['search'],
          );
        }

        return page.respond(rows, total: total);
      } catch (e) {
        return Response.internalServerError(
          body: jsonEncode({'error': '$e'}),
          headers: ApiContext.jsonHeaders,
        );
      }
    });
  }
}
