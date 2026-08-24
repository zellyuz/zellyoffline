import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../repositories/shift_repository.dart';
import '../../database_helper.dart';
import '../api_context.dart';
import '../pagination.dart';

/// Admin (mobil) ilovasi uchun endpoint'lar.
///
/// Mavjud `/reports/*` bo'limi hisobot ekranlariga mo'ljallangan — har biri
/// bitta jadval yoki grafik uchun. Mobil ilovaning **bosh ekrani** esa bitta
/// so'rovda hamma narsani olishi kerak, aks holda telefon 5-6 marta tarmoqqa
/// chiqadi. `/admin/dashboard` shu ehtiyoj uchun.
class AdminRoutes {
  const AdminRoutes._();

  static void register(Router router) {
    // ── Buyurtmalar ro'yxati (filtrli) ──────────────────────────────────
    //
    // `/reports/orders` faqat **to'langan** buyurtmalarni beradi (status = 1).
    // Adminga esa hozir **ochiq** buyurtmalar ham kerak: zalda nima bo'layotgani.
    //
    // Ofitsiantga ham ochiq, lekin u faqat o'z buyurtmalarini ko'radi —
    // `waiter_id` tokendan majburan qo'yiladi.
    router.get('/orders', (Request request) async {
      try {
        final session = ApiContext.sessionOf(request);
        if (session == null) return ApiContext.unauthorized('Token topilmadi');

        final q = request.url.queryParameters;
        final page = Pagination.of(request);

        final where = <String>[];
        final args = <Object?>[];

        // status: 0 — ochiq, 1 — to'langan, 2 — bekor qilingan.
        // Berilmasa — hammasi (bekor qilinganlardan tashqari).
        final status = int.tryParse(q['status'] ?? '');
        if (status != null) {
          where.add('o.status = ?');
          args.add(status);
        } else {
          where.add('o.status != 2');
        }

        if (session.isWaiter) {
          // Ofitsiant boshqaning buyurtmasini ko'ra olmaydi — `?waiter_id`
          // yuborsa ham e'tiborga olinmaydi.
          where.add('o.waiter_id = ?');
          args.add(session.userId);
        } else {
          final waiterId = int.tryParse(q['waiter_id'] ?? '');
          if (waiterId != null) {
            where.add('o.waiter_id = ?');
            args.add(waiterId);
          }
        }

        final tableId = int.tryParse(q['table_id'] ?? '');
        if (tableId != null) {
          where.add('o.table_id = ?');
          args.add(tableId);
        }
        final locationId = int.tryParse(q['location_id'] ?? '');
        if (locationId != null) {
          where.add('o.location_id = ?');
          args.add(locationId);
        }
        final orderType = int.tryParse(q['order_type'] ?? '');
        if (orderType != null) {
          where.add('o.order_type = ?');
          args.add(orderType);
        }
        if (q['start'] != null) {
          where.add('o.created_at >= ?');
          args.add(q['start']);
        }
        if (q['end'] != null) {
          where.add('o.created_at <= ?');
          args.add(q['end']);
        }

        final whereSql = where.join(' AND ');
        final db = await DatabaseHelper.instance.database;

        final rows = await db.rawQuery('''
          SELECT o.*, l.name AS location_name, t.name AS table_name,
                 w.name AS waiter_name,
                 (SELECT COUNT(*) FROM order_items oi WHERE oi.order_id = o.id)
                   AS item_count
          FROM orders o
          LEFT JOIN locations l ON o.location_id = l.id
          LEFT JOIN tables    t ON o.table_id    = t.id
          LEFT JOIN waiters   w ON o.waiter_id   = w.id
          WHERE $whereSql
          ORDER BY o.created_at DESC${page.sqlSuffix}
        ''', args);

        int? total;
        if (page.enabled) {
          final countRows = await db.rawQuery(
            'SELECT COUNT(*) AS c FROM orders o WHERE $whereSql',
            args,
          );
          total = (countRows.first['c'] as num?)?.toInt() ?? 0;
        }

        return page.respond(rows, total: total);
      } catch (e) {
        return Response.internalServerError(
          body: jsonEncode({'error': '$e'}),
          headers: ApiContext.jsonHeaders,
        );
      }
    });

    // ── Bosh ekran: bitta so'rovda hamma narsa ──────────────────────────
    router.get('/admin/dashboard', (Request request) async {
      try {
        final db = await DatabaseHelper.instance.database;

        // Kun chegarasi sozlamadan olinadi (`day_reset_time`) — kafening
        // "kuni" yarim tunda tugamasligi mumkin.
        final dayStart = await DatabaseHelper.instance.getDayStartTime();
        final dayEnd = dayStart.add(const Duration(days: 1));
        final prevStart = dayStart.subtract(const Duration(days: 1));

        final today = await _periodMetrics(db, dayStart, dayEnd);
        final yesterday = await _periodMetrics(db, prevStart, dayStart);

        // Zal holati
        final tableRows = await db.rawQuery('''
          SELECT COUNT(*) AS total,
                 SUM(CASE WHEN status = 1 THEN 1 ELSE 0 END) AS busy
          FROM tables
        ''');
        final billRows = await db.rawQuery(
          'SELECT COUNT(*) AS c FROM orders WHERE status = 0 AND bill_requested = 1',
        );

        // Ochiq buyurtmalar (hali to'lanmagan pul)
        final openRows = await db.rawQuery('''
          SELECT COUNT(*) AS count, COALESCE(SUM(grand_total), 0) AS total
          FROM orders WHERE status = 0
        ''');

        // Top 5 mahsulot — bugun
        final topProducts = await db.rawQuery('''
          SELECT oi.product_name AS name,
                 SUM(oi.qty) AS qty,
                 SUM(oi.qty * oi.price) AS revenue
          FROM order_items oi
          JOIN orders o ON oi.order_id = o.id
          WHERE o.status = 1 AND o.created_at >= ? AND o.created_at < ?
          GROUP BY oi.product_name
          ORDER BY qty DESC
          LIMIT 5
        ''', [dayStart.toIso8601String(), dayEnd.toIso8601String()]);

        // Faol smena
        final shift = await ShiftRepository().getOpenShift();
        Map<String, dynamic>? shiftJson;
        if (shift != null) {
          final summary = await ShiftRepository().getShiftSalesSummary(shift.id!);
          shiftJson = {
            'id': shift.id,
            'opened_at': shift.openedAt.toIso8601String(),
            'opening_cash': shift.openingCash,
            'expected_cash': summary.expectedCashBalance,
            'total_sales': summary.totalSales,
            'total_expenses': summary.totalExpenses,
          };
        }

        // Kam qolgan xomashyo (ombor yoqilgan bo'lsa)
        final inventoryOn = await ApiContext.inventoryEnabled();
        int lowStock = 0;
        if (inventoryOn) {
          final lowRows = await db.rawQuery('''
            SELECT COUNT(*) AS c
            FROM ingredients i
            LEFT JOIN ingredient_stock s ON s.ingredient_id = i.id
            WHERE i.is_active = 1
              AND i.min_stock > 0
              AND COALESCE(s.on_hand, 0) <= i.min_stock
          ''');
          lowStock = (lowRows.first['c'] as num?)?.toInt() ?? 0;
        }

        return Response.ok(
          jsonEncode({
            'period': {
              'start': dayStart.toIso8601String(),
              'end': dayEnd.toIso8601String(),
            },
            'today': today,
            'yesterday': yesterday,
            'tables': {
              'total': (tableRows.first['total'] as num?)?.toInt() ?? 0,
              'busy': (tableRows.first['busy'] as num?)?.toInt() ?? 0,
              'bill_requested': (billRows.first['c'] as num?)?.toInt() ?? 0,
            },
            'open_orders': {
              'count': (openRows.first['count'] as num?)?.toInt() ?? 0,
              'total': (openRows.first['total'] as num?)?.toDouble() ?? 0.0,
            },
            'top_products': topProducts,
            'shift': shiftJson,
            'inventory': {'enabled': inventoryOn, 'low_stock': lowStock},
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

    // ── Joriy smena (kassa holati) ──────────────────────────────────────
    router.get('/admin/shift/current', (Request request) async {
      try {
        final repo = ShiftRepository();
        final shift = await repo.getOpenShift();
        if (shift == null) {
          return Response.ok(
            jsonEncode({'open': false}),
            headers: ApiContext.jsonHeaders,
          );
        }
        final summary = await repo.getShiftSalesSummary(shift.id!);
        final orderCount = await repo.getShiftOrderCount(shift.id!);
        final names = await repo.getShiftUserNames(shift.openedBy, shift.closedBy);

        return Response.ok(
          jsonEncode({
            'open': true,
            'shift': {
              'id': shift.id,
              'opened_at': shift.openedAt.toIso8601String(),
              'opened_by': shift.openedBy,
              'opened_by_name': names['opened_by'],
              'opening_cash': shift.openingCash,
              'order_count': orderCount,
            },
            'summary': {
              'cash': summary.totalCashSales,
              'card': summary.totalCardSales,
              'terminal': summary.totalTerminalSales,
              'debt': summary.totalDebtSales,
              'bonus': summary.totalBonusSales,
              'transfer': summary.totalTransferSales,
              'total_sales': summary.totalSales,
              'in_movements': summary.totalInMovements,
              'out_movements': summary.totalOutMovements,
              'expected_cash': summary.expectedCashBalance,
              'discount': summary.totalDiscount,
              'expenses': summary.totalExpenses,
              'net_profit': summary.netProfit,
            },
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
  }

  /// Bir davr uchun asosiy ko'rsatkichlar (tushum, chek soni, to'lov turlari).
  ///
  /// To'lov turlari `order_payments` dan olinadi — bo'lingan to'lov
  /// (yarmi naqd, yarmi karta) shundagina to'g'ri hisoblanadi.
  static Future<Map<String, dynamic>> _periodMetrics(
    Database db,
    DateTime start,
    DateTime end,
  ) async {
    final args = [start.toIso8601String(), end.toIso8601String()];

    final rows = await db.rawQuery('''
      SELECT COUNT(*) AS orders,
             COALESCE(SUM(grand_total), 0) AS revenue,
             COALESCE(AVG(grand_total), 0)  AS avg_check
      FROM orders
      WHERE status = 1 AND created_at >= ? AND created_at < ?
    ''', args);

    final payRows = await db.rawQuery('''
      SELECT op.payment_type AS type, SUM(op.amount) AS amount
      FROM order_payments op
      JOIN orders o ON op.order_id = o.id
      WHERE o.status = 1 AND o.created_at >= ? AND o.created_at < ?
      GROUP BY op.payment_type
    ''', args);

    // To'lov turi tarixan ikki xil yozilgan ('cash' va 'Naqd') — ikkisini ham
    // tushunamiz, aks holda mobil ilovada naqd summasi nolga chiqadi.
    final payments = <String, double>{
      'cash': 0,
      'card': 0,
      'terminal': 0,
      'debt': 0,
      'bonus': 0,
      'transfer': 0,
    };
    for (final row in payRows) {
      final raw = (row['type'] ?? '').toString().toLowerCase();
      final amount = (row['amount'] as num?)?.toDouble() ?? 0.0;
      final key = switch (raw) {
        'cash' || 'naqd' => 'cash',
        'card' || 'karta' => 'card',
        'terminal' => 'terminal',
        'debt' || 'nasiya' || 'qarz' => 'debt',
        'bonus' => 'bonus',
        'transfer' || "o'tkazma" => 'transfer',
        _ => null,
      };
      if (key != null) payments[key] = payments[key]! + amount;
    }

    final first = rows.first;
    return {
      'orders': (first['orders'] as num?)?.toInt() ?? 0,
      'revenue': (first['revenue'] as num?)?.toDouble() ?? 0.0,
      'avg_check': (first['avg_check'] as num?)?.toDouble() ?? 0.0,
      'payments': payments,
    };
  }
}
