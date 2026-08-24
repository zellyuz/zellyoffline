import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tezzro/core/database_helper.dart';
import 'package:tezzro/core/server/api_server.dart';
import 'package:tezzro/core/server/auth_token_service.dart';

/// Admin API — mobil admin ilovasi shu endpoint'lar ustiga quriladi.
///
/// Testlar **haqiqiy HTTP server** orqali ishlaydi: routing, auth middleware
/// va rol tekshiruvi birgalikda sinaladi. Faqat handler'ni chaqirish
/// middleware'ni chetlab o'tardi — aynan u yerda xavfsizlik hal bo'ladi.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  DatabaseHelper.databasePathOverride = inMemoryDatabasePath;

  const port = 18099;
  const base = 'http://127.0.0.1:$port';

  late String adminToken;
  late String waiterToken;
  final client = HttpClient();

  /// Bugungi (kun boshidan keyingi) vaqt — `getDayStartTime` sozlamasiz
  /// yarim tunni qaytaradi, shuning uchun "hozir" doim shu kun ichida.
  String nowIso() => DateTime.now().toIso8601String();

  Future<Map<String, dynamic>> getJson(String path, String? token) async {
    final req = await client.getUrl(Uri.parse('$base$path'));
    if (token != null) req.headers.set('Authorization', 'Bearer $token');
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    return {'status': res.statusCode, 'body': body};
  }

  setUpAll(() async {
    final db = await DatabaseHelper.instance.database;

    // Admin (id 1) va "Kassa" ofitsianti bazaning o'zi tomonidan yaratiladi
    // (`_ensureDefaultAdminExists`), shuning uchun faqat test ofitsianti
    // qo'shiladi.
    await db.insert('waiters', {
      'id': 5,
      'name': 'Aziz',
      'type': 0,
      'value': 0.0,
      'pin_code': '2222',
      'is_active': 1,
    });

    // Zal va stollar
    await db.insert('locations', {'id': 1, 'name': 'Zal'});
    await db.insert('tables', {'id': 1, 'location_id': 1, 'name': 'Stol 1', 'status': 1});
    await db.insert('tables', {'id': 2, 'location_id': 1, 'name': 'Stol 2', 'status': 0});

    // To'langan buyurtmalar: 3 ta admin/kassir, 1 ta ofitsiant Aziz
    for (var i = 0; i < 3; i++) {
      await db.insert('orders', {
        'id': 'paid-$i',
        'total': 100000.0,
        'grand_total': 100000.0,
        'payment_type': 'cash',
        'created_at': nowIso(),
        'status': 1,
        'table_id': 1,
        'location_id': 1,
        'waiter_id': 9,
      });
      await db.insert('order_payments', {
        'order_id': 'paid-$i',
        'payment_type': 'cash',
        'amount': 100000.0,
        'created_at': nowIso(),
      });
      await db.insert('order_items', {
        'order_id': 'paid-$i',
        'product_id': 10,
        'product_name': 'Osh',
        'qty': 2.0,
        'price': 35000.0,
      });
    }

    // Ochiq buyurtma — ofitsiant Aziz (id 5) niki
    await db.insert('orders', {
      'id': 'open-1',
      'total': 50000.0,
      'grand_total': 50000.0,
      'payment_type': '',
      'created_at': nowIso(),
      'status': 0,
      'table_id': 1,
      'location_id': 1,
      'waiter_id': 5,
      'bill_requested': 1,
    });

    adminToken = (await AuthTokenService.instance.issue(
      userId: 1,
      role: 'admin',
      permissions: const [],
    )).token;
    waiterToken = (await AuthTokenService.instance.issue(
      userId: 5,
      role: 'waiter',
      permissions: const ['print_receipt'],
    )).token;

    final address = await ApiServer.start(port);
    expect(address, isNotNull, reason: 'Test serveri ishga tushmadi');
  });

  tearDownAll(() {
    client.close(force: true);
    ApiServer.stop();
  });

  group('Ruxsatlar', () {
    test('/admin/* ofitsiant uchun yopiq', () async {
      final res = await getJson('/admin/dashboard', waiterToken);
      expect(res['status'], 403);
    });

    test('/inventory/* ofitsiant uchun yopiq', () async {
      final res = await getJson('/inventory/stock', waiterToken);
      expect(res['status'], 403);
    });

    test('tokensiz kirish mumkin emas', () async {
      final res = await getJson('/admin/dashboard', null);
      expect(res['status'], 401);
    });
  });

  group('GET /admin/dashboard', () {
    test('bosh ekran uchun kerakli hamma narsani bitta so\'rovda beradi', () async {
      final res = await getJson('/admin/dashboard', adminToken);
      expect(res['status'], 200);

      final data = jsonDecode(res['body'] as String) as Map<String, dynamic>;

      // Bugungi tushum: 3 × 100 000
      expect(data['today']['orders'], 3);
      expect(data['today']['revenue'], 300000.0);
      expect(data['today']['payments']['cash'], 300000.0);

      // Zal holati
      expect(data['tables']['total'], 2);
      expect(data['tables']['busy'], 1);
      expect(data['tables']['bill_requested'], 1);

      // Ochiq buyurtma (hali to'lanmagan pul)
      expect(data['open_orders']['count'], 1);
      expect(data['open_orders']['total'], 50000.0);

      // Top mahsulot
      expect(data['top_products'], isNotEmpty);
      expect(data['top_products'][0]['name'], 'Osh');

      // Ochiq smena yo'q
      expect(data['shift'], isNull);
    });
  });

  group('GET /orders', () {
    test('admin barcha buyurtmalarni ko\'radi', () async {
      final res = await getJson('/orders', adminToken);
      expect(res['status'], 200);
      final rows = jsonDecode(res['body'] as String) as List;
      expect(rows.length, 4); // 3 to'langan + 1 ochiq
    });

    test('ofitsiant faqat o\'z buyurtmasini ko\'radi', () async {
      final res = await getJson('/orders', waiterToken);
      expect(res['status'], 200);
      final rows = jsonDecode(res['body'] as String) as List;
      expect(rows.length, 1);
      expect(rows.first['id'], 'open-1');
    });

    test('ofitsiant boshqaning ID sini so\'rasa ham o\'zinikini oladi', () async {
      // `?waiter_id=9` — boshqa xodim. Server uni e'tiborga olmasligi kerak.
      final res = await getJson('/orders?waiter_id=9', waiterToken);
      final rows = jsonDecode(res['body'] as String) as List;
      expect(rows.length, 1);
      expect(rows.first['waiter_id'], 5);
    });

    test('status bo\'yicha filtrlash', () async {
      final res = await getJson('/orders?status=0', adminToken);
      final rows = jsonDecode(res['body'] as String) as List;
      expect(rows.length, 1);
      expect(rows.first['id'], 'open-1');
    });
  });

  group('Sahifalash', () {
    test('?limit berilmasa — eski shakl (yalang\'och massiv)', () async {
      // Desktop mijoz (client rejimi) aynan shuni kutadi. Buzilmasligi shart.
      final res = await getJson('/orders', adminToken);
      expect(jsonDecode(res['body'] as String), isA<List<dynamic>>());
    });

    test('?limit berilsa — meta bilan konvert', () async {
      final res = await getJson('/orders?limit=2', adminToken);
      final data = jsonDecode(res['body'] as String) as Map<String, dynamic>;

      expect(data['data'], hasLength(2));
      expect(data['meta']['total'], 4);
      expect(data['meta']['limit'], 2);
      expect(data['meta']['offset'], 0);
      expect(data['meta']['has_more'], isTrue);
    });

    test('oxirgi sahifada has_more false bo\'ladi', () async {
      final res = await getJson('/orders?limit=2&offset=2', adminToken);
      final data = jsonDecode(res['body'] as String) as Map<String, dynamic>;
      expect(data['data'], hasLength(2));
      expect(data['meta']['has_more'], isFalse);
    });

    test('haddan katta ?limit chegaralanadi', () async {
      // Aks holda `?limit=999999` bilan bazani band qilib bo'lardi.
      final res = await getJson('/orders?limit=999999', adminToken);
      final data = jsonDecode(res['body'] as String) as Map<String, dynamic>;
      expect(data['meta']['limit'], 200);
    });

    test('/transactions ham sahifalanadi', () async {
      final res = await getJson('/transactions?limit=1', adminToken);
      expect(res['status'], 200);
      final data = jsonDecode(res['body'] as String) as Map<String, dynamic>;
      expect(data['meta'], isNotNull);
    });
  });

  group('GET /admin/shift/current', () {
    test('ochiq smena bo\'lmasa open: false', () async {
      final res = await getJson('/admin/shift/current', adminToken);
      expect(res['status'], 200);
      final data = jsonDecode(res['body'] as String) as Map<String, dynamic>;
      expect(data['open'], isFalse);
    });
  });

  group('GET /inventory/stock', () {
    test('admin uchun ochiq va tuzilma to\'g\'ri', () async {
      final res = await getJson('/inventory/stock', adminToken);
      expect(res['status'], 200);
      final data = jsonDecode(res['body'] as String) as Map<String, dynamic>;
      expect(data['items'], isA<List<dynamic>>());
      expect(data.containsKey('enabled'), isTrue);
      expect(data.containsKey('low_count'), isTrue);
    });
  });
}
