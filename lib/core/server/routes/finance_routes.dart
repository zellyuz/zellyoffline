import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../models/customer.dart';
import '../../database_helper.dart';
import '../pagination.dart';

/// `/expenses`, `/expense_categories`, `/customers`, `/transactions` —
/// kassa bo'limi (faqat admin/kassir).
class FinanceRoutes {
  const FinanceRoutes._();

  static void register(Router router) {
    // 6. Expenses & Categories
    router.get('/expense_categories', (Request request) async {
      final data = await DatabaseHelper.instance.queryAll('expense_categories');
      return Response.ok(jsonEncode(data));
    });

    router.post('/expense_categories', (Request request) async {
      final payload = jsonDecode(await request.readAsString());
      final db = await DatabaseHelper.instance.database;
      if (payload['id'] != null) {
        await db.update(
          'expense_categories',
          payload,
          where: 'id = ?',
          whereArgs: [payload['id']],
        );
      } else {
        await db.insert('expense_categories', payload);
      }
      return Response.ok(jsonEncode({'status': 'success'}));
    });

    router.get('/expenses', (Request request) async {
      final page = Pagination.of(request);
      final db = await DatabaseHelper.instance.database;
      final rows = await db.rawQuery(
        'SELECT * FROM expenses ORDER BY created_at DESC${page.sqlSuffix}',
      );
      return page.respond(rows, total: await _countOf(db, 'expenses', page));
    });

    router.post('/expenses', (Request request) async {
      final payload = jsonDecode(await request.readAsString());
      final db = await DatabaseHelper.instance.database;
      if (payload['id'] != null) {
        await db.update(
          'expenses',
          payload,
          where: 'id = ?',
          whereArgs: [payload['id']],
        );
      } else {
        await db.insert('expenses', payload);
      }
      return Response.ok(jsonEncode({'status': 'success'}));
    });

    router.delete('/expenses/<id>', (Request request, String id) async {
      final db = await DatabaseHelper.instance.database;
      await db.delete('expenses', where: 'id = ?', whereArgs: [id]);
      return Response.ok(jsonEncode({'status': 'success'}));
    });

    // 7. Customers
    router.get('/customers', (Request request) async {
      final page = Pagination.of(request);
      final search = request.url.queryParameters['search'];
      final db = await DatabaseHelper.instance.database;

      // Mijozlar bazasi minglab yozuvga yetadi — telefonda qidiruv shart.
      final where = search != null && search.trim().isNotEmpty
          ? 'WHERE name LIKE ? OR phone LIKE ?'
          : '';
      final args = where.isEmpty
          ? <Object?>[]
          : <Object?>['%${search!.trim()}%', '%${search.trim()}%'];

      final rows = await db.rawQuery(
        'SELECT * FROM customers $where ORDER BY name ASC${page.sqlSuffix}',
        args,
      );
      int? total;
      if (page.enabled) {
        final countRows = await db.rawQuery(
          'SELECT COUNT(*) AS c FROM customers $where',
          args,
        );
        total = (countRows.first['c'] as num?)?.toInt() ?? 0;
      }
      return page.respond(rows, total: total);
    });

    router.post('/customers', (Request request) async {
      final payload = jsonDecode(await request.readAsString());
      final db = await DatabaseHelper.instance.database;
      if (payload['id'] != null) {
        await db.update(
          'customers',
          payload,
          where: 'id = ?',
          whereArgs: [payload['id']],
        );
      } else {
        await db.insert('customers', payload);
      }
      return Response.ok(jsonEncode({'status': 'success'}));
    });

    router.delete('/customers/<id>', (Request request, String id) async {
      final db = await DatabaseHelper.instance.database;
      await db.delete('customers', where: 'id = ?', whereArgs: [id]);
      return Response.ok(jsonEncode({'status': 'success'}));
    });

    router.get('/transactions', (Request request) async {
      final customerId = request.url.queryParameters['customer_id'];
      final page = Pagination.of(request);
      final db = await DatabaseHelper.instance.database;

      final where = customerId != null ? 'WHERE customer_id = ?' : '';
      final args = customerId != null ? <Object?>[customerId] : <Object?>[];

      final rows = await db.rawQuery(
        'SELECT * FROM transactions $where '
        'ORDER BY created_at DESC${page.sqlSuffix}',
        args,
      );
      int? total;
      if (page.enabled) {
        final countRows = await db.rawQuery(
          'SELECT COUNT(*) AS c FROM transactions $where',
          args,
        );
        total = (countRows.first['c'] as num?)?.toInt() ?? 0;
      }
      return page.respond(rows, total: total);
    });

    router.post('/transactions', (Request request) async {
      final payload = jsonDecode(await request.readAsString());
      final db = await DatabaseHelper.instance.database;

      await db.transaction((txn) async {
        await txn.insert('transactions', payload);

        if (payload['customer_id'] != null) {
          final customerRes = await txn.query(
            'customers',
            where: 'id = ?',
            whereArgs: [payload['customer_id']],
            limit: 1,
          );

          if (customerRes.isNotEmpty) {
            final customer = Customer.fromMap(customerRes.first);
            double newDebt = customer.debt;
            double newCredit = customer.credit;
            final double amount = (payload['amount'] as num).toDouble();

            if (payload['type'] == 'outlay') {
              newDebt += amount;
            } else if (payload['type'] == 'payment') {
              if (newDebt >= amount) {
                newDebt -= amount;
              } else {
                double remainder = amount - newDebt;
                newDebt = 0;
                newCredit += remainder;
              }
            }

            await txn.update(
              'customers',
              {'debt': newDebt, 'credit': newCredit},
              where: 'id = ?',
              whereArgs: [payload['customer_id']],
            );
          }
        }
      });

      return Response.ok(jsonEncode({'success': true}));
    });

  }

  /// Filtrsiz jadval uchun umumiy yozuvlar soni.
  /// Sahifalash so'ralmagan bo'lsa — ortiqcha so'rov yubormaydi.
  static Future<int?> _countOf(
    Database db,
    String table,
    Pagination page,
  ) async {
    if (!page.enabled) return null;
    final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM $table');
    return (rows.first['c'] as num?)?.toInt() ?? 0;
  }
}
