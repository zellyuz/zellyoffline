import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../app_logger.dart';
import '../../database_helper.dart';

/// `/locations`, `/tables` — zallar va stollar.
class TableRoutes {
  const TableRoutes._();

  static void register(Router router) {
    // 2. Locations & Tables
    router.get('/locations', (Request request) async {
      final data = await DatabaseHelper.instance.queryAll('locations');
      return Response.ok(jsonEncode(data));
    });

    router.get('/tables', (Request request) async {
      final locId = request.url.queryParameters['location_id'];
      final db = await DatabaseHelper.instance.database;

      final List<Map<String, dynamic>> tables;
      if (locId != null) {
        tables = await db.query(
          'tables',
          where: 'location_id = ?',
          whereArgs: [locId],
        );
      } else {
        tables = await db.query('tables');
      }
      return Response.ok(jsonEncode(tables));
    });

    router.post('/tables', (Request request) async {
      final payload = jsonDecode(await request.readAsString());
      final db = await DatabaseHelper.instance.database;
      if (payload['id'] != null) {
        await db.update(
          'tables',
          payload,
          where: 'id = ?',
          whereArgs: [payload['id']],
        );
      } else {
        await db.insert('tables', payload);
      }
      return Response.ok(jsonEncode({'status': 'success'}));
    });

    router.delete('/tables/<id>', (Request request, String id) async {
      final db = await DatabaseHelper.instance.database;
      await db.delete('tables', where: 'id = ?', whereArgs: [id]);
      return Response.ok(jsonEncode({'status': 'success'}));
    });

    router.post('/locations', (Request request) async {
      final payload = jsonDecode(await request.readAsString());
      final db = await DatabaseHelper.instance.database;
      if (payload['id'] != null) {
        await db.update(
          'locations',
          payload,
          where: 'id = ?',
          whereArgs: [payload['id']],
        );
      } else {
        await db.insert('locations', payload);
      }
      return Response.ok(jsonEncode({'status': 'success'}));
    });

    router.delete('/locations/<id>', (Request request, String id) async {
      final db = await DatabaseHelper.instance.database;
      await db.delete('locations', where: 'id = ?', whereArgs: [id]);
      return Response.ok(jsonEncode({'status': 'success'}));
    });

    router.get('/tables/summary', (Request request) async {
      final db = await DatabaseHelper.instance.database;
      // Get tables with their active orders if any
      final summary = await db.rawQuery('''
        SELECT
          t.id, t.location_id, t.name, t.status, t.pricing_type, 
          t.hourly_rate, t.fixed_amount, t.active_order_id,
          t.x, t.y, t.width, t.height, t.shape, t.service_percentage,
          l.name as location_name,
          o.id as order_id,
          o.total as order_total,
          o.waiter_id,
          o.bill_requested,
          w.name as waiter_name,
          o.opened_at
        FROM tables t
        LEFT JOIN locations l ON t.location_id = l.id
        LEFT JOIN orders o ON t.active_order_id = o.id AND o.status = 0
        LEFT JOIN waiters w ON o.waiter_id = w.id
      ''');
      
      AppLogger.d('ApiServer', 'API [GET] /tables/summary: Loaded ${summary.length} tables');
      if (summary.isNotEmpty) {
        AppLogger.d('ApiServer', 'First table summary example: ID=${summary.first['id']}, '
              'Status=${summary.first['status']}, '
              'ActiveOrderID=${summary.first['active_order_id']}, '
              'JoinOrderID=${summary.first['order_id']}');
      }
      
      return Response.ok(jsonEncode(summary));
    });

  }
}
