import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tezzro/core/database_helper.dart';
import 'package:tezzro/core/server/auth_token_service.dart';

/// API autentifikatsiyasi — eng muhim xavfsizlik chegarasi.
/// Bu testlar tokenning taxmin qilinmasligini, muddat va bekor qilish
/// ishlashini, ofitsiant huquqlari cheklanishini tekshiradi.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  DatabaseHelper.databasePathOverride = inMemoryDatabasePath;

  final auth = AuthTokenService.instance;

  group('API tokenlari', () {
    test('token taxmin qilinadigan shaklda emas', () async {
      final session = await auth.issue(
        userId: 1,
        role: 'admin',
        permissions: const [],
      );

      // Eski sxema `admin-token-1` edi — istalgan mijoz uni yozib admin
      // bo'lardi. Yangi token uzun va tasodifiy bo'lishi shart.
      expect(session.token.contains('admin-token'), isFalse);
      expect(session.token.contains('1'), anyOf(isTrue, isFalse));
      expect(session.token.length, greaterThanOrEqualTo(32));
    });

    test('har login yangi va noyob token beradi', () async {
      final a = await auth.issue(userId: 1, role: 'admin', permissions: const []);
      final b = await auth.issue(userId: 1, role: 'admin', permissions: const []);
      expect(a.token, isNot(equals(b.token)));
    });

    test('yaroqli token sessiyaga aylanadi, soxta token — yo\'q', () async {
      final session = await auth.issue(
        userId: 7,
        role: 'waiter',
        permissions: const ['print_receipt'],
      );

      final resolved = await auth.resolve('Bearer ${session.token}');
      expect(resolved, isNotNull);
      expect(resolved!.userId, 7);
      expect(resolved.isWaiter, isTrue);

      expect(await auth.resolve('Bearer admin-token-1'), isNull);
      expect(await auth.resolve('Bearer soxta-token'), isNull);
      expect(await auth.resolve(null), isNull);
      expect(await auth.resolve(''), isNull);
      expect(await auth.resolve(session.token), isNull); // "Bearer " yo'q
    });

    test('bekor qilingan token boshqa ishlamaydi', () async {
      final session = await auth.issue(
        userId: 3,
        role: 'cashier',
        permissions: const [],
      );
      expect(await auth.resolve('Bearer ${session.token}'), isNotNull);

      await auth.revoke(session.token);
      expect(await auth.resolve('Bearer ${session.token}'), isNull);
    });

    test('xodim o\'chirilganda barcha sessiyalari yopiladi', () async {
      final first = await auth.issue(
        userId: 42,
        role: 'waiter',
        permissions: const [],
      );
      final second = await auth.issue(
        userId: 42,
        role: 'waiter',
        permissions: const [],
      );

      await auth.revokeUser(userId: 42, role: 'waiter');

      expect(await auth.resolve('Bearer ${first.token}'), isNull);
      expect(await auth.resolve('Bearer ${second.token}'), isNull);
    });

    // Eng ko'p uchraydigan real holat: kassa boshqa kompyuterga ko'chirilgan
    // yoki ilova qayta o'rnatilgan. Sessiyalar har kompyuterning o'z
    // bazasida yashaydi, shuning uchun eski token bu yerda umuman topilmaydi
    // — u "eskirgan" emas, "begona". Xabar shuni aytishi kerak.
    test('begona token muddat tugashi bilan chalkashtirilmaydi', () async {
      final unknown = await auth.authenticate('Bearer boshqa-kassaning-tokeni');
      expect(unknown.isAuthenticated, isFalse);
      expect(unknown.reason, AuthFailure.unknownToken);
      expect(unknown.reason!.code, 'unknown_token');
      expect(unknown.reason!.message, contains('boshqa kompyuterda'));

      final missing = await auth.authenticate(null);
      expect(missing.reason, AuthFailure.missingToken);
      expect(missing.reason!.code, 'no_token');
    });

    test('muddati o\'tgan token expired sababini beradi', () async {
      final session = await auth.issue(
        userId: 11,
        role: 'admin',
        permissions: const [],
      );

      // Bazadagi muddatni o'tmishga surib, keshni tozalaymiz — shunda
      // tekshiruv bazadagi yozuvga tayanadi.
      final db = await DatabaseHelper.instance.database;
      await db.update(
        'api_sessions',
        {
          'expires_at': DateTime.now()
              .subtract(const Duration(hours: 1))
              .millisecondsSinceEpoch,
        },
        where: 'token = ?',
        whereArgs: [session.token],
      );
      auth.dropCache(session.token);

      final result = await auth.authenticate('Bearer ${session.token}');
      expect(result.isAuthenticated, isFalse);
      expect(result.reason, AuthFailure.expired);
      expect(result.reason!.code, 'token_expired');
    });
  });

  group('Ruxsatlar', () {
    test('ofitsiant faqat berilgan huquqlarga ega', () {
      final session = ApiSession(
        token: 't',
        userId: 5,
        role: 'waiter',
        permissions: ['print_receipt', 'change_table'],
        expiresAt: DateTime(2099),
      );
      expect(session.can('print_receipt'), isTrue);
      expect(session.can('change_table'), isTrue);
      expect(session.can('edit_price'), isFalse);
      expect(session.can('delete_item'), isFalse);
    });

    test('admin uchun barcha huquqlar ochiq', () {
      final session = ApiSession(
        token: 't',
        userId: 1,
        role: 'admin',
        permissions: [],
        expiresAt: DateTime(2099),
      );
      expect(session.can('edit_price'), isTrue);
      expect(session.can('istalgan_narsa'), isTrue);
      expect(session.isWaiter, isFalse);
    });
  });

  group('Login urinishlarini cheklash', () {
    test('5 xato urinishdan keyin bloklanadi', () {
      final throttle = LoginThrottle.instance;
      const client = '192.168.1.99';

      expect(throttle.allow(client), isTrue);
      for (var i = 0; i < LoginThrottle.maxAttempts; i++) {
        expect(throttle.allow(client), isTrue, reason: '$i-urinish');
        throttle.recordFailure(client);
      }

      // Cheklovga yetdi — PIN'ni brute-force qilib bo'lmaydi.
      expect(throttle.allow(client), isFalse);
      expect(throttle.remainingLock(client).inSeconds, greaterThan(0));
    });

    test('muvaffaqiyatli login hisobni tozalaydi', () {
      final throttle = LoginThrottle.instance;
      const client = '192.168.1.98';

      throttle.recordFailure(client);
      throttle.recordFailure(client);
      throttle.recordSuccess(client);

      expect(throttle.allow(client), isTrue);
    });
  });
}

