import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shelf/shelf.dart';

import '../database_helper.dart';
import 'auth_token_service.dart';

/// Route modullari uchun umumiy yordamchilar.
///
/// Ilgari bularning hammasi `ApiServer` ichida edi va endpoint'lar bilan
/// bitta faylda yashardi. Endi route'lar modullarga bo'lingani uchun
/// sarlavhalar, ruxsat tekshiruvi va sessiya kaliti shu yerda —
/// bitta manba.
class ApiContext {
  const ApiContext._();

  static const Map<String, String> jsonHeaders = {
    'Content-Type': 'application/json; charset=utf-8',
  };

  /// So'rov konteksti kaliti — handler'lar sessiyani shu orqali oladi.
  static const String sessionKey = 'zelly.session';

  /// Autentifikatsiyasiz ochiq yo'llar.
  ///  * `/auth/login` — token shu yerdan olinadi;
  ///  * `/reports/view` — brauzerda ochiladigan HTML qobiq (o'zi ichida
  ///    login so'raydi va keyingi so'rovlarni token bilan yuboradi);
  ///  * `/uploads/...` — rasm `<img src>` orqali yuklanadi, brauzer u yerga
  ///    sarlavha qo'sha olmaydi;
  ///  * `/ws` — WebSocket qo'l berish bosqichi (token query orqali).
  static bool isPublicPath(String path) {
    final normalized = path.startsWith('/') ? path : '/$path';
    return normalized == '/auth/login' ||
        normalized == '/reports/view' ||
        normalized == '/ws' ||
        normalized.startsWith('/uploads/');
  }

  /// Faqat admin/kassir kira oladigan yo'llar. Ofitsiantning mobil ilovasi
  /// bu ma'lumotlarga muhtoj emas: umumiy savdo hisobotlari, boshqa
  /// xodimlar ro'yxati, xarajatlar va to'lovlar tarixi — bularning barchasi
  /// biznes uchun maxfiy.
  static bool isStaffOnlyPath(String path) {
    final normalized = path.startsWith('/') ? path : '/$path';
    if (normalized == '/reports/view') return false; // ochiq HTML qobiq
    return normalized.startsWith('/reports/') ||
        normalized.startsWith('/admin/') ||
        normalized.startsWith('/inventory/') ||
        normalized.startsWith('/users') ||
        normalized.startsWith('/expenses') ||
        normalized.startsWith('/expense_categories') ||
        normalized.startsWith('/transactions') ||
        normalized.startsWith('/customers');
  }

  static ApiSession? sessionOf(Request request) =>
      request.context[sessionKey] as ApiSession?;

  static Response unauthorized(String message) => Response.unauthorized(
    jsonEncode({'error': message}),
    headers: jsonHeaders,
  );

  static Response forbidden(String message) => Response.forbidden(
    jsonEncode({'error': message}),
    headers: jsonHeaders,
  );

  /// Faqat admin/kassir uchun: boshqaruv va hisobot endpoint'lari.
  /// Qaytgan qiymat `null` bo'lsa — ruxsat bor.
  static Response? requireStaff(Request request) {
    final session = sessionOf(request);
    if (session == null) return unauthorized('Token topilmadi');
    if (session.isWaiter) {
      return forbidden('Bu amal uchun administrator huquqi kerak');
    }
    return null;
  }

  /// Ofitsiantning granular huquqini tekshiradi (`print_receipt`,
  /// `change_table`, `edit_price` ...). Admin/kassirga hamma narsa ochiq.
  static Response? requirePermission(Request request, String permission) {
    final session = sessionOf(request);
    if (session == null) return unauthorized('Token topilmadi');
    if (!session.can(permission)) {
      return forbidden('Sizda "$permission" huquqi yo\'q');
    }
    return null;
  }

  /// Rate-limit va audit uchun mijoz kaliti (IP manzil).
  static String clientKey(Request request) {
    final forwarded = request.headers['x-forwarded-for'];
    if (forwarded != null && forwarded.isNotEmpty) {
      return forwarded.split(',').first.trim();
    }
    final conn = request.context['shelf.io.connection_info'];
    if (conn is HttpConnectionInfo) return conn.remoteAddress.address;
    return 'unknown';
  }

  /// Mahsulot rasmlari saqlanadigan papka (yo'q bo'lsa yaratiladi).
  static Future<Directory> getImagesDir() async {
    final appDocDir = await getApplicationSupportDirectory();
    final imagesDir = Directory(p.join(appDocDir.path, 'product_images'));
    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }
    return imagesDir;
  }

  /// Ombor moduli yoqilganmi (`settings.enable_inventory`).
  static Future<bool> inventoryEnabled() async {
    try {
      final db = await DatabaseHelper.instance.database;
      final rows = await db.query(
        'settings',
        where: 'key = ?',
        whereArgs: ['enable_inventory'],
        limit: 1,
      );
      return rows.isNotEmpty && rows.first['value'] == 'true';
    } catch (e) {
      debugPrint('[inventory] settings read error: $e');
      return false;
    }
  }
}
