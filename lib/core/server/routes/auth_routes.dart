import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../database_helper.dart';
import '../api_context.dart';
import '../auth_token_service.dart';

/// `/auth/*` — kirish, chiqish va joriy foydalanuvchi.
class AuthRoutes {
  const AuthRoutes._();

  static void register(Router router) {
    // 1. Auth
    router.post('/auth/login', (Request request) async {
      final clientKey = ApiContext.clientKey(request);

      // Brute-force himoyasi: 4 xonali PIN cheklovsiz serverda soniyalarda
      // topiladi, shuning uchun urinishlar soni cheklanadi.
      if (!LoginThrottle.instance.allow(clientKey)) {
        final left = LoginThrottle.instance.remainingLock(clientKey);
        return Response(
          429,
          body: jsonEncode({
            'error':
                'Juda ko\'p noto\'g\'ri urinish. '
                '${left.inMinutes + 1} daqiqadan keyin qayta urinib ko\'ring.',
            'retry_after': left.inSeconds,
          }),
          headers: ApiContext.jsonHeaders,
        );
      }

      final payload = jsonDecode(await request.readAsString());
      final pin = payload['pin'] as String?;

      if (pin == null || pin.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({'error': 'PIN kodi kiritilmadi'}),
          headers: ApiContext.jsonHeaders,
        );
      }

      final db = await DatabaseHelper.instance.database;

      // Waiters login
      final waiters = await db.query(
        'waiters',
        where: 'pin_code = ? AND is_active = 1',
        whereArgs: [pin],
      );

      if (waiters.isNotEmpty) {
        final waiter = waiters.first;
        final permsStr = waiter['permissions']?.toString() ?? '';
        final permsList = permsStr.isEmpty
            ? <String>[]
            : permsStr.split(',').map((e) => e.trim()).toList();

        final session = await AuthTokenService.instance.issue(
          userId: waiter['id'] as int,
          role: 'waiter',
          permissions: permsList,
        );
        LoginThrottle.instance.recordSuccess(clientKey);

        return Response.ok(
          jsonEncode({
            'token': session.token,
            'expires_at': session.expiresAt.toIso8601String(),
            'user': {
              'id': waiter['id'],
              'name': waiter['name'],
              'role': 'waiter',
              'permissions': permsList,
            },
          }),
          headers: ApiContext.jsonHeaders,
        );
      }

      // Fallback for Admin (Local/Server mode admin access)
      final users = await db.query(
        'users',
        where: 'pin = ? AND is_active = 1',
        whereArgs: [pin],
      );

      if (users.isNotEmpty) {
        final user = users.first;
        final userPermsStr = user['permissions']?.toString() ?? '';
        final userPerms = userPermsStr.isEmpty
            ? <String>[]
            : userPermsStr.split(',').map((e) => e.trim()).toList();

        final session = await AuthTokenService.instance.issue(
          userId: user['id'] as int,
          role: (user['role'] ?? 'admin').toString(),
          permissions: userPerms,
        );
        LoginThrottle.instance.recordSuccess(clientKey);

        return Response.ok(
          jsonEncode({
            'token': session.token,
            'expires_at': session.expiresAt.toIso8601String(),
            'user': {
              'id': user['id'],
              'name': user['name'],
              'role': user['role'], // admin or cashier
              'permissions': userPerms,
            },
          }),
          headers: ApiContext.jsonHeaders,
        );
      }

      LoginThrottle.instance.recordFailure(clientKey);
      // 401 — autentifikatsiya muvaffaqiyatsiz (403 emas: 403 "kirdingiz,
      // lekin huquqingiz yo'q" degani).
      return Response.unauthorized(
        jsonEncode({'error': 'PIN kod noto‘g‘ri yoki xodim faol emas'}),
        headers: ApiContext.jsonHeaders,
      );
    });

    // Chiqish — tokenni serverda bekor qiladi.
    router.post('/auth/logout', (Request request) async {
      final token = AuthTokenService.extractToken(
        request.headers['Authorization'],
      );
      if (token != null) await AuthTokenService.instance.revoke(token);
      return Response.ok(
        jsonEncode({'success': true}),
        headers: ApiContext.jsonHeaders,
      );
    });

    // /auth/me — token bo'yicha joriy foydalanuvchi ma'lumotlarini qaytaradi.
    // Sessiya middleware'da allaqachon tekshirilgan, shuning uchun bu yerda
    // faqat bazadan yangi ma'lumot olamiz (nomi/huquqi o'zgargan bo'lishi
    // mumkin).
    router.get('/auth/me', (Request request) async {
      try {
        final session = ApiContext.sessionOf(request);
        if (session == null) {
          return ApiContext.unauthorized(
          AuthFailure.missingToken.message,
          code: AuthFailure.missingToken.code,
        );
        }

        final db = await DatabaseHelper.instance.database;
        final table = session.isWaiter ? 'waiters' : 'users';
        final rows = await db.query(
          table,
          where: 'id = ? AND is_active = 1',
          whereArgs: [session.userId],
        );
        if (rows.isEmpty) {
          // Xodim o'chirilgan yoki faolsizlantirilgan — sessiyani yopamiz.
          await AuthTokenService.instance.revoke(session.token);
          return ApiContext.unauthorized('Foydalanuvchi topilmadi yoki faol emas');
        }

        final row = rows.first;
        final permsStr = row['permissions']?.toString() ?? '';
        return Response.ok(
          jsonEncode({
            'id': row['id'],
            'name': row['name'],
            'role': session.isWaiter ? 'waiter' : row['role'],
            'permissions': permsStr.isEmpty
                ? <String>[]
                : permsStr.split(',').map((e) => e.trim()).toList(),
            'expires_at': session.expiresAt.toIso8601String(),
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
}
