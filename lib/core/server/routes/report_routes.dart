import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../database_helper.dart';
import '../pagination.dart';
import '../views/mobile_report_html.dart';

/// `/reports/*` — hisobotlar (faqat admin/kassir; `/reports/view` HTML
/// qobig'i tokensiz ochiladi va o'zi login so'raydi).
class ReportRoutes {
  const ReportRoutes._();

  static void register(Router router) {
    // 5. Reports View (for Telegram WebApp)
    router.get('/reports/view', (Request request) async {
      return Response.ok(
        mobileReportHtml(),
        headers: {'Content-Type': 'text/html; charset=utf-8'},
      );
    });

    // ── Report API endpoints (client devices fetch from server) ─────────────

    // Telegram Mini App uchun server tomonida hisoblangan kun chegaralari
    router.get('/reports/periods', (Request request) async {
      try {
        final dayStart = await DatabaseHelper.instance.getDayStartTime();
        final todayEnd   = dayStart.add(const Duration(days: 1));
        final yesterdayS = dayStart.subtract(const Duration(days: 1));
        final weekStart  = dayStart.subtract(const Duration(days: 6));
        final monthStart = DateTime(dayStart.year, dayStart.month, 1,
            dayStart.hour, dayStart.minute);
        final prevMonthS = DateTime(dayStart.year, dayStart.month - 1, 1,
            dayStart.hour, dayStart.minute);
        final prevMonthE = DateTime(dayStart.year, dayStart.month, 1,
            dayStart.hour, dayStart.minute);

        return Response.ok(
          jsonEncode({
            'today':     [dayStart.toIso8601String(),  todayEnd.toIso8601String()],
            'yesterday': [yesterdayS.toIso8601String(), dayStart.toIso8601String()],
            'week':      [weekStart.toIso8601String(),  todayEnd.toIso8601String()],
            'month':     [monthStart.toIso8601String(), todayEnd.toIso8601String()],
            'prevmonth': [prevMonthS.toIso8601String(), prevMonthE.toIso8601String()],
          }),
          headers: {'Content-Type': 'application/json'},
        );
      } catch (e) {
        return Response.internalServerError(body: jsonEncode({'error': '$e'}));
      }
    });

    // Smena ro'yxati — Telegram Mini App shift selektor uchun
    router.get('/reports/shifts', (Request request) async {
      try {
        final q = request.url.queryParameters;
        final limit = int.tryParse(q['limit'] ?? '') ?? 20;
        final db = await DatabaseHelper.instance.database;
        final rows = await db.rawQuery('''
          SELECT s.id, s.opened_at, s.closed_at, s.status,
                 s.opening_cash, s.counted_cash,
                 u1.name as opened_by_name,
                 u2.name as closed_by_name,
                 COUNT(o.id) as order_count,
                 COALESCE(SUM(o.grand_total), 0) as total_sales
          FROM shifts s
          LEFT JOIN users u1 ON s.opened_by = u1.id
          LEFT JOIN users u2 ON s.closed_by = u2.id
          LEFT JOIN orders o ON o.shift_id = s.id AND o.status = 1
          GROUP BY s.id
          ORDER BY s.opened_at DESC
          LIMIT ?
        ''', [limit]);
        return Response.ok(jsonEncode(rows),
            headers: {'Content-Type': 'application/json'});
      } catch (e) {
        return Response.internalServerError(body: jsonEncode({'error': e.toString()}));
      }
    });

    router.get('/reports/hourly', (Request request) async {
      try {
        final q = request.url.queryParameters;
        final start = q['start'] ?? DateTime.now().toIso8601String();
        final end = q['end'] ?? DateTime(DateTime.now().year, DateTime.now().month,
            DateTime.now().day + 1).toIso8601String();
        final shiftId = q['shift_id'] != null ? int.tryParse(q['shift_id']!) : null;
        final db = await DatabaseHelper.instance.database;
        final String hWhere;
        final List<dynamic> hArgs;
        if (shiftId != null) {
          hWhere = 'status = 1 AND shift_id = ?';
          hArgs  = [shiftId];
        } else {
          hWhere = 'status = 1 AND created_at >= ? AND created_at < ?';
          hArgs  = [start, end];
        }
        final rows = await db.rawQuery('''
          SELECT CAST(strftime('%H', created_at) AS INTEGER) as hour,
                 COUNT(*) as orders_count, SUM(grand_total) as revenue
          FROM orders WHERE $hWhere
          GROUP BY hour ORDER BY hour ASC
        ''', hArgs);
        final hourMap = <int, Map<String, Object?>>{};
        for (final r in rows) { hourMap[r['hour'] as int] = r; }
        final result = List.generate(24, (h) => {
          'hour': h,
          'orders_count': (hourMap[h]?['orders_count'] as int?) ?? 0,
          'revenue': (hourMap[h]?['revenue'] as num?)?.toDouble() ?? 0.0,
        });
        return Response.ok(jsonEncode(result), headers: {'Content-Type': 'application/json'});
      } catch (e) {
        return Response.internalServerError(body: jsonEncode({'error': e.toString()}));
      }
    });

    router.get('/reports/stats', (Request request) async {
      try {
        final q = request.url.queryParameters;
        final start = q['start'] ?? DateTime.now().toIso8601String();
        final end = q['end'] ??
            DateTime(DateTime.now().year, DateTime.now().month,
                    DateTime.now().day, 23, 59, 59)
                .toIso8601String();
        final orderType = q['order_type'] != null ? int.tryParse(q['order_type']!) : null;
        final locationId = q['location_id'] != null ? int.tryParse(q['location_id']!) : null;
        final waiterId = q['waiter_id'] != null ? int.tryParse(q['waiter_id']!) : null;
        final shiftId = q['shift_id'] != null ? int.tryParse(q['shift_id']!) : null;

        final db = await DatabaseHelper.instance.database;
        final args = <dynamic>[];
        var extra = '';
        if (orderType != null) { extra += ' AND o.order_type = ?'; args.add(orderType); }
        if (locationId != null) { extra += ' AND o.location_id = ?'; args.add(locationId); }
        if (waiterId != null) { extra += ' AND o.waiter_id = ?'; args.add(waiterId); }

        final String baseWhere;
        if (shiftId != null) {
          baseWhere = 'o.status = 1 AND o.shift_id = ?$extra';
          args.insert(0, shiftId);
        } else {
          baseWhere = 'o.status = 1 AND o.created_at >= ? AND o.created_at <= ?$extra';
          args.insertAll(0, [start, end]);
        }

        final ordersRaw = await db.rawQuery('''
          SELECT COUNT(*) as count,
            SUM(grand_total) as total, AVG(grand_total) as avg_check,
            SUM(CASE WHEN order_type=0 THEN grand_total ELSE 0 END) as dine_in_total,
            SUM(CASE WHEN order_type=1 THEN grand_total ELSE 0 END) as takeaway_total
          FROM orders o WHERE $baseWhere
        ''', List.from(args));

        // Payment breakdown from order_payments (handles split payments correctly)
        final payRows = await db.rawQuery('''
          SELECT op.payment_type, SUM(op.amount) as pay_total
          FROM order_payments op JOIN orders o ON op.order_id = o.id
          WHERE $baseWhere
          GROUP BY op.payment_type
        ''', List.from(args));
        final payMap = {
          for (final r in payRows)
            r['payment_type'] as String: (r['pay_total'] as num?)?.toDouble() ?? 0.0
        };
        final metricsRow = Map<String, dynamic>.from(ordersRaw.first);
        metricsRow['cash_total']     = payMap['cash'] ?? 0.0;
        metricsRow['card_total']     = payMap['card'] ?? 0.0;
        metricsRow['terminal_total'] = payMap['terminal'] ?? 0.0;
        metricsRow['bonus_total']    = payMap['bonus'] ?? 0.0;
        metricsRow['debt_total']     = payMap['debt'] ?? 0.0;
        metricsRow['transfer_total'] = payMap['transfer'] ?? 0.0;
        final orders = [metricsRow];

        final topQty = await db.rawQuery('''
          SELECT p.name, SUM(oi.qty) as qty FROM order_items oi
          JOIN products p ON oi.product_id=p.id JOIN orders o ON oi.order_id=o.id
          WHERE $baseWhere GROUP BY p.id ORDER BY qty DESC LIMIT 5
        ''', List.from(args));

        final topRevenue = await db.rawQuery('''
          SELECT p.name, SUM(oi.qty*oi.price) as revenue FROM order_items oi
          JOIN products p ON oi.product_id=p.id JOIN orders o ON oi.order_id=o.id
          WHERE $baseWhere GROUP BY p.id ORDER BY revenue DESC LIMIT 5
        ''', List.from(args));

        return Response.ok(
          jsonEncode({'metrics': orders.first, 'topQty': topQty, 'topRevenue': topRevenue}),
          headers: {'Content-Type': 'application/json'},
        );
      } catch (e) {
        return Response.internalServerError(body: jsonEncode({'error': e.toString()}));
      }
    });

    router.get('/reports/orders', (Request request) async {
      try {
        final q = request.url.queryParameters;
        final start = q['start'] ?? DateTime.now().toIso8601String();
        final end = q['end'] ??
            DateTime(DateTime.now().year, DateTime.now().month,
                    DateTime.now().day, 23, 59, 59)
                .toIso8601String();
        final orderType = q['order_type'] != null ? int.tryParse(q['order_type']!) : null;
        final locationId = q['location_id'] != null ? int.tryParse(q['location_id']!) : null;
        final waiterId = q['waiter_id'] != null ? int.tryParse(q['waiter_id']!) : null;
        final shiftId = q['shift_id'] != null ? int.tryParse(q['shift_id']!) : null;

        final db = await DatabaseHelper.instance.database;
        final args = <dynamic>[];
        var extra = '';
        if (orderType != null) { extra += ' AND o.order_type = ?'; args.add(orderType); }
        if (locationId != null) { extra += ' AND o.location_id = ?'; args.add(locationId); }
        if (waiterId != null) { extra += ' AND o.waiter_id = ?'; args.add(waiterId); }

        final String ordWhere;
        if (shiftId != null) {
          ordWhere = 'o.status = 1 AND o.shift_id = ?$extra';
          args.insert(0, shiftId);
        } else {
          ordWhere = 'o.status = 1 AND o.created_at >= ? AND o.created_at <= ?$extra';
          args.insertAll(0, [start, end]);
        }

        final page = Pagination.of(request);
        final rows = await db.rawQuery('''
          SELECT o.*, l.name as location_name, t.name as table_name, w.name as waiter_name
          FROM orders o
          LEFT JOIN locations l ON o.location_id=l.id
          LEFT JOIN tables t ON o.table_id=t.id
          LEFT JOIN waiters w ON o.waiter_id=w.id
          WHERE $ordWhere
          ORDER BY o.created_at DESC${page.sqlSuffix}
        ''', args);

        int? total;
        if (page.enabled) {
          final countRows = await db.rawQuery(
            'SELECT COUNT(*) AS c FROM orders o WHERE $ordWhere',
            args,
          );
          total = (countRows.first['c'] as num?)?.toInt() ?? 0;
        }

        return page.respond(rows, total: total);
      } catch (e) {
        return Response.internalServerError(body: jsonEncode({'error': e.toString()}));
      }
    });

    router.get('/reports/products', (Request request) async {
      try {
        final q = request.url.queryParameters;
        final start = q['start'] ?? DateTime.now().toIso8601String();
        final end = q['end'] ??
            DateTime(DateTime.now().year, DateTime.now().month,
                    DateTime.now().day, 23, 59, 59)
                .toIso8601String();
        final orderType = q['order_type'] != null ? int.tryParse(q['order_type']!) : null;
        final locationId = q['location_id'] != null ? int.tryParse(q['location_id']!) : null;
        final waiterId = q['waiter_id'] != null ? int.tryParse(q['waiter_id']!) : null;
        final shiftId = q['shift_id'] != null ? int.tryParse(q['shift_id']!) : null;

        final db = await DatabaseHelper.instance.database;
        final args = <dynamic>[];
        var extra = '';
        if (orderType != null) { extra += ' AND o.order_type = ?'; args.add(orderType); }
        if (locationId != null) { extra += ' AND o.location_id = ?'; args.add(locationId); }
        if (waiterId != null) { extra += ' AND o.waiter_id = ?'; args.add(waiterId); }

        final String pWhere;
        if (shiftId != null) {
          pWhere = 'o.status=1 AND o.shift_id=?$extra';
          args.insert(0, shiftId);
        } else {
          pWhere = 'o.status=1 AND o.created_at>=? AND o.created_at<=?$extra';
          args.insertAll(0, [start, end]);
        }

        final rows = await db.rawQuery('''
          SELECT p.name, p.category, SUM(oi.qty) as total_qty,
            SUM(oi.qty*oi.price) as total_revenue, p.quantity as current_stock
          FROM order_items oi
          JOIN products p ON oi.product_id=p.id JOIN orders o ON oi.order_id=o.id
          WHERE $pWhere
          GROUP BY p.id, p.name, p.quantity ORDER BY total_revenue DESC
        ''', args);

        return Response.ok(jsonEncode(rows),
            headers: {'Content-Type': 'application/json'});
      } catch (e) {
        return Response.internalServerError(body: jsonEncode({'error': e.toString()}));
      }
    });

    router.get('/reports/waiters', (Request request) async {
      try {
        final q = request.url.queryParameters;
        final start = q['start'] ?? DateTime.now().toIso8601String();
        final end = q['end'] ??
            DateTime(DateTime.now().year, DateTime.now().month,
                    DateTime.now().day, 23, 59, 59)
                .toIso8601String();
        final orderType = q['order_type'] != null ? int.tryParse(q['order_type']!) : null;
        final locationId = q['location_id'] != null ? int.tryParse(q['location_id']!) : null;
        final shiftId = q['shift_id'] != null ? int.tryParse(q['shift_id']!) : null;

        final db = await DatabaseHelper.instance.database;
        final args = <dynamic>[];
        var extra = '';
        if (orderType != null) { extra += ' AND o.order_type = ?'; args.add(orderType); }
        if (locationId != null) { extra += ' AND o.location_id = ?'; args.add(locationId); }

        final String wJoinCond;
        if (shiftId != null) {
          wJoinCond = 'o.status=1 AND o.shift_id=?$extra';
          args.insert(0, shiftId);
        } else {
          wJoinCond = 'o.status=1 AND o.created_at>=? AND o.created_at<=?$extra';
          args.insertAll(0, [start, end]);
        }

        final rows = await db.rawQuery('''
          SELECT w.name, w.type as waiter_type, w.value as waiter_value,
            COUNT(o.id) as order_count, SUM(COALESCE(o.grand_total,0)) as total_sales
          FROM waiters w
          LEFT JOIN orders o ON w.id=o.waiter_id AND $wJoinCond
          GROUP BY w.id, w.name, w.type, w.value
          HAVING order_count > 0
        ''', args);

        return Response.ok(jsonEncode(rows),
            headers: {'Content-Type': 'application/json'});
      } catch (e) {
        return Response.internalServerError(body: jsonEncode({'error': e.toString()}));
      }
    });

    router.get('/reports/locations', (Request request) async {
      try {
        final q = request.url.queryParameters;
        final start = q['start'] ?? DateTime.now().toIso8601String();
        final end = q['end'] ??
            DateTime(DateTime.now().year, DateTime.now().month,
                    DateTime.now().day, 23, 59, 59)
                .toIso8601String();

        final db = await DatabaseHelper.instance.database;
        final rows = await db.rawQuery('''
          SELECT l.name, COUNT(o.id) as order_count, SUM(o.grand_total) as total_revenue
          FROM locations l JOIN orders o ON l.id=o.location_id
          WHERE o.status=1 AND o.created_at>=? AND o.created_at<=?
          GROUP BY l.id ORDER BY total_revenue DESC
        ''', [start, end]);

        return Response.ok(jsonEncode(rows),
            headers: {'Content-Type': 'application/json'});
      } catch (e) {
        return Response.internalServerError(body: jsonEncode({'error': e.toString()}));
      }
    });

    router.get('/reports/tables', (Request request) async {
      try {
        final q = request.url.queryParameters;
        final start = q['start'] ?? DateTime.now().toIso8601String();
        final end = q['end'] ??
            DateTime(DateTime.now().year, DateTime.now().month,
                    DateTime.now().day, 23, 59, 59)
                .toIso8601String();

        final db = await DatabaseHelper.instance.database;
        final rows = await db.rawQuery('''
          SELECT t.name as table_name, l.name as location_name,
            COUNT(o.id) as order_count, SUM(o.grand_total) as total_revenue
          FROM tables t JOIN locations l ON t.location_id=l.id
          JOIN orders o ON t.id=o.table_id
          WHERE o.status=1 AND o.created_at>=? AND o.created_at<=?
          GROUP BY t.id ORDER BY total_revenue DESC
        ''', [start, end]);

        return Response.ok(jsonEncode(rows),
            headers: {'Content-Type': 'application/json'});
      } catch (e) {
        return Response.internalServerError(body: jsonEncode({'error': e.toString()}));
      }
    });

    router.get('/reports/zreport', (Request request) async {
      try {
        final q = request.url.queryParameters;
        final start = q['start'] ?? DateTime.now().toIso8601String();
        final end = q['end'] ??
            DateTime(DateTime.now().year, DateTime.now().month,
                    DateTime.now().day, 23, 59, 59)
                .toIso8601String();
        final shiftId = q['shift_id'] != null ? int.tryParse(q['shift_id']!) : null;

        final db = await DatabaseHelper.instance.database;

        final String zWhere;
        final List<dynamic> zArgs;
        if (shiftId != null) {
          zWhere = 'o.status=1 AND o.shift_id=?';
          zArgs  = [shiftId];
        } else {
          zWhere = 'o.status=1 AND o.created_at>=? AND o.created_at<=?';
          zArgs  = [start, end];
        }
        final String oWhere = zWhere.replaceAll('o.', '');

        final summaryRaw = await db.rawQuery('''
          SELECT COUNT(*) as count, SUM(grand_total) as total,
            MIN(created_at) as first_order, MAX(created_at) as last_order
          FROM orders WHERE $oWhere
        ''', List.from(zArgs));

        final zPayRows = await db.rawQuery('''
          SELECT op.payment_type, SUM(op.amount) as pay_total
          FROM order_payments op JOIN orders o ON op.order_id = o.id
          WHERE $zWhere
          GROUP BY op.payment_type
        ''', List.from(zArgs));
        final zPayMap = <String, double>{};
        for (final r in zPayRows) {
          final pt = (r['payment_type'] as String? ?? '').toLowerCase();
          final amt = (r['pay_total'] as num?)?.toDouble() ?? 0.0;
          final key = (pt == 'naqd') ? 'cash' : (pt == 'karta') ? 'card' :
                      (pt == 'nasiya') ? 'debt' : pt;
          zPayMap[key] = (zPayMap[key] ?? 0.0) + amt;
        }
        final summaryRow = Map<String, dynamic>.from(summaryRaw.first);
        summaryRow['cash_total']     = zPayMap['cash'] ?? 0.0;
        summaryRow['card_total']     = zPayMap['card'] ?? 0.0;
        summaryRow['terminal_total'] = zPayMap['terminal'] ?? 0.0;
        summaryRow['bonus_total']    = zPayMap['bonus'] ?? 0.0;
        summaryRow['debt_total']     = zPayMap['debt'] ?? 0.0;
        summaryRow['transfer_total'] = zPayMap['transfer'] ?? 0.0;
        // Smena qo'shimcha ma'lumotlari
        if (shiftId != null) {
          final shiftRow = await db.query('shifts', where: 'id=?', whereArgs: [shiftId], limit: 1);
          if (shiftRow.isNotEmpty) {
            summaryRow['shift_opened_at'] = shiftRow.first['opened_at'];
            summaryRow['shift_closed_at'] = shiftRow.first['closed_at'];
            summaryRow['shift_status']    = shiftRow.first['status'];
            summaryRow['opening_cash']    = shiftRow.first['opening_cash'];
            summaryRow['counted_cash']    = shiftRow.first['counted_cash'];
          }
          // Xarajatlar
          final expRow = await db.rawQuery(
            'SELECT COALESCE(SUM(amount),0) as total FROM expenses WHERE shift_id=?', [shiftId]);
          summaryRow['total_expenses'] = (expRow.first['total'] as num?)?.toDouble() ?? 0.0;
        }

        final waiterSales = await db.rawQuery('''
          SELECT COALESCE(w.name,'Admin/Saboy') as name, SUM(o.grand_total) as sales
          FROM orders o LEFT JOIN waiters w ON o.waiter_id=w.id
          WHERE $zWhere
          GROUP BY o.waiter_id
        ''', List.from(zArgs));

        final categorySales = await db.rawQuery('''
          SELECT p.category, SUM(oi.qty) as qty, SUM(oi.qty*oi.price) as total
          FROM order_items oi JOIN products p ON oi.product_id=p.id
          JOIN orders o ON oi.order_id=o.id
          WHERE $zWhere
          GROUP BY p.category ORDER BY total DESC
        ''', List.from(zArgs));

        final topProducts = await db.rawQuery('''
          SELECT p.name, SUM(oi.qty) as qty, SUM(oi.qty*oi.price) as revenue
          FROM order_items oi JOIN products p ON oi.product_id=p.id
          JOIN orders o ON oi.order_id=o.id
          WHERE $zWhere
          GROUP BY p.id ORDER BY revenue DESC LIMIT 10
        ''', List.from(zArgs));

        return Response.ok(
          jsonEncode({
            'summary': summaryRow,
            'waiterSales': waiterSales,
            'categorySales': categorySales,
            'topProducts': topProducts,
          }),
          headers: {'Content-Type': 'application/json'},
        );
      } catch (e) {
        return Response.internalServerError(body: jsonEncode({'error': e.toString()}));
      }
    });

  }
}
