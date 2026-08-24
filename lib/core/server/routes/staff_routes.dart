import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../database_helper.dart';
import '../api_context.dart';
import '../auth_token_service.dart';

/// `/waiters`, `/users` — xodimlar. PIN kodlar javoblarga tushmaydi.
class StaffRoutes {
  const StaffRoutes._();

  static void register(Router router) {
    // 4. Waiters
    router.get('/waiters', (Request request) async {
      final isStaff = ApiContext.requireStaff(request) == null;
      final data = await DatabaseHelper.instance.queryAll('waiters');
      final mapped = data.map((waiter) {
        final newWaiter = Map<String, dynamic>.from(waiter);
        final permsStr = newWaiter['permissions']?.toString() ?? '';
        newWaiter['permissions'] = permsStr.isEmpty ? [] : permsStr.split(',');
        // PIN kodni faqat administrator ko'ra oladi — ilgari u har qanday
        // mijozga ochiq qaytarilardi va boshqa xodim nomidan kirish mumkin edi.
        if (!isStaff) newWaiter.remove('pin_code');
        return newWaiter;
      }).toList();
      return Response.ok(jsonEncode(mapped), headers: ApiContext.jsonHeaders);
    });

    router.post('/waiters', (Request request) async {
      final denied = ApiContext.requireStaff(request);
      if (denied != null) return denied;
      final payload = jsonDecode(await request.readAsString());
      final db = await DatabaseHelper.instance.database;
      if (payload['id'] != null) {
        await db.update(
          'waiters',
          payload,
          where: 'id = ?',
          whereArgs: [payload['id']],
        );
      } else {
        await db.insert('waiters', payload);
      }
      return Response.ok(jsonEncode({'status': 'success'}));
    });

    router.delete('/waiters/<id>', (Request request, String id) async {
      final denied = ApiContext.requireStaff(request);
      if (denied != null) return denied;
      final db = await DatabaseHelper.instance.database;
      await db.delete('waiters', where: 'id = ?', whereArgs: [id]);
      // Xodim o'chirildi — uning ochiq sessiyalari ham bekor qilinsin.
      final waiterId = int.tryParse(id);
      if (waiterId != null) {
        await AuthTokenService.instance.revokeUser(
          userId: waiterId,
          role: 'waiter',
        );
      }
      return Response.ok(
        jsonEncode({'status': 'success'}),
        headers: ApiContext.jsonHeaders,
      );
    });

    // 5. Users
    router.get('/users', (Request request) async {
      final denied = ApiContext.requireStaff(request);
      if (denied != null) return denied;
      final data = await DatabaseHelper.instance.queryAll('users');
      // PIN hech qachon tarmoqqa chiqmasin.
      final safe = data.map((u) {
        final copy = Map<String, dynamic>.from(u);
        copy.remove('pin');
        return copy;
      }).toList();
      return Response.ok(jsonEncode(safe), headers: ApiContext.jsonHeaders);
    });

    router.post('/users', (Request request) async {
      final denied = ApiContext.requireStaff(request);
      if (denied != null) return denied;
      final payload = jsonDecode(await request.readAsString());
      final db = await DatabaseHelper.instance.database;
      if (payload['id'] != null) {
        await db.update(
          'users',
          payload,
          where: 'id = ?',
          whereArgs: [payload['id']],
        );
      } else {
        await db.insert('users', payload);
      }
      return Response.ok(jsonEncode({'status': 'success'}));
    });

    router.delete('/users/<id>', (Request request, String id) async {
      final denied = ApiContext.requireStaff(request);
      if (denied != null) return denied;
      final db = await DatabaseHelper.instance.database;
      await db.delete('users', where: 'id = ?', whereArgs: [id]);
      final userId = int.tryParse(id);
      if (userId != null) {
        for (final role in const ['admin', 'cashier', 'manager', 'owner']) {
          await AuthTokenService.instance.revokeUser(
            userId: userId,
            role: role,
          );
        }
      }
      return Response.ok(
        jsonEncode({'status': 'success'}),
        headers: ApiContext.jsonHeaders,
      );
    });

  }
}
