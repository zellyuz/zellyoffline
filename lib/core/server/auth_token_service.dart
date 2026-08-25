import 'dart:convert';
import 'dart:math';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../app_logger.dart';
import '../database_helper.dart';

const String _logTag = 'ApiAuth';

/// Server tomonidagi autentifikatsiya sessiyasi.
///
/// Eski `admin-token-<id>` / `waiter-token-<id>` sxemasi taxmin qilinardi —
/// istalgan mijoz `Bearer admin-token-1` yuborib to'liq admin huquqini olardi.
/// Endi token kriptografik tasodifiy qator, muddatga ega va serverda
/// saqlanadi, ya'ni istalgan payt bekor qilinishi mumkin.
class ApiSession {
  const ApiSession({
    required this.token,
    required this.userId,
    required this.role,
    required this.permissions,
    required this.expiresAt,
  });

  final String token;
  final int userId;

  /// `admin`, `cashier`, `manager`, `waiter` ...
  final String role;
  final List<String> permissions;
  final DateTime expiresAt;

  bool get isWaiter => role == 'waiter';

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  /// Ruxsat tekshiruvi. Ofitsiant bo'lmaganlar (admin/kassir) uchun ochiq.
  bool can(String permission) {
    if (!isWaiter) return true;
    return permissions.contains(permission);
  }

  Map<String, dynamic> toJson() => {
    'id': userId,
    'role': role,
    'permissions': permissions,
    'expires_at': expiresAt.toIso8601String(),
  };
}

/// Autentifikatsiya nima uchun rad etilgani.
///
/// Ilgari uchala holat bitta "Token yaroqsiz yoki muddati tugagan" xabariga
/// tushardi. Amalda esa ular butunlay boshqa muammolar va foydalanuvchining
/// keyingi qadami ham boshqacha — masalan [unknownToken] da domen yoki
/// internetni tekshirish mutlaqo befoyda, faqat qayta kirish kerak.
enum AuthFailure {
  /// `Authorization: Bearer <token>` sarlavhasi yo'q yoki noto'g'ri shaklda.
  missingToken,

  /// Token bu kompyuterning bazasida yo'q — boshqa kassada olingan,
  /// ilova qayta o'rnatilgan yoki sessiya bekor qilingan.
  unknownToken,

  /// Token shu kompyuterniki, lekin muddati o'tgan.
  expired,
}

extension AuthFailureMessage on AuthFailure {
  /// Mijozga ko'rsatiladigan matn. Nima bo'lganini **va** nima qilish
  /// kerakligini aytadi.
  String get message => switch (this) {
    AuthFailure.missingToken =>
      'Kirish tokeni yuborilmadi. PIN kod bilan qaytadan kiring.',
    AuthFailure.unknownToken =>
      'Bu token shu kassaga tegishli emas — u boshqa kompyuterda olingan '
          'yoki ilova qaytadan o\'rnatilgan. Chiqib, shu kassaning PIN kodi '
          'bilan qaytadan kiring.',
    AuthFailure.expired =>
      'Sessiya muddati tugagan (12 soat). PIN kod bilan qaytadan kiring.',
  };

  /// Mijoz dasturiy tarzda ajratishi uchun barqaror kod.
  String get code => switch (this) {
    AuthFailure.missingToken => 'no_token',
    AuthFailure.unknownToken => 'unknown_token',
    AuthFailure.expired => 'token_expired',
  };
}

/// Tekshiruv natijasi: sessiya **yoki** rad etish sababi.
class AuthResult {
  const AuthResult({this.session, this.reason});

  final ApiSession? session;
  final AuthFailure? reason;

  bool get isAuthenticated => session != null;
}

class AuthTokenService {
  AuthTokenService._();
  static final AuthTokenService instance = AuthTokenService._();

  /// Sessiya muddati. Har so'rovda uzayadi (sliding expiry), shuning uchun
  /// smena davomida ofitsiant qayta PIN kiritmaydi.
  static const Duration sessionTtl = Duration(hours: 12);

  static const String _table = 'api_sessions';

  final Map<String, ApiSession> _cache = {};
  final Random _rng = Random.secure();
  bool _tableReady = false;

  Future<Database> _db() async {
    final db = await DatabaseHelper.instance.database;
    if (!_tableReady) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $_table (
          token TEXT PRIMARY KEY,
          user_id INTEGER NOT NULL,
          role TEXT NOT NULL,
          permissions TEXT,
          created_at INTEGER NOT NULL,
          expires_at INTEGER NOT NULL,
          last_seen_at INTEGER NOT NULL
        )
      ''');
      _tableReady = true;
      await _purgeExpired(db);
    }
    return db;
  }

  String _generateToken() {
    final bytes = List<int>.generate(32, (_) => _rng.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  /// Muvaffaqiyatli login'dan keyin yangi sessiya ochadi.
  Future<ApiSession> issue({
    required int userId,
    required String role,
    required List<String> permissions,
  }) async {
    final db = await _db();
    final now = DateTime.now();
    final session = ApiSession(
      token: _generateToken(),
      userId: userId,
      role: role,
      permissions: permissions,
      expiresAt: now.add(sessionTtl),
    );

    await db.insert(_table, {
      'token': session.token,
      'user_id': session.userId,
      'role': session.role,
      'permissions': session.permissions.join(','),
      'created_at': now.millisecondsSinceEpoch,
      'expires_at': session.expiresAt.millisecondsSinceEpoch,
      'last_seen_at': now.millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    _cache[session.token] = session;
    AppLogger.i(_logTag, 'Sessiya ochildi: $role#$userId');
    return session;
  }

  /// `Authorization: Bearer <token>` sarlavhasidan sessiyani topadi.
  ///
  /// Xato sababi kerak bo'lsa [authenticate] dan foydalaning — bu metod
  /// faqat "bor/yo'q" javobini beradi.
  Future<ApiSession?> resolve(String? authHeader) async =>
      (await authenticate(authHeader)).session;

  /// [resolve] bilan bir xil, lekin **nega** rad etilganini ham qaytaradi.
  ///
  /// Sabab muhim: eng ko'p uchraydigan holat — token haqiqatan eskirgani
  /// emas, balki uni **boshqa kassa** bergani. Sessiyalar har kompyuterning
  /// o'z SQLite bazasida (`api_sessions`) yashaydi va ko'chma emas. Umumiy
  /// "token yaroqsiz yoki muddati tugagan" xabari bu holatda foydalanuvchini
  /// noto'g'ri yo'ldan olib borardi — u sabab domen yoki litsenziyada deb
  /// o'ylardi.
  Future<AuthResult> authenticate(String? authHeader) async {
    final token = extractToken(authHeader);
    if (token == null) {
      return const AuthResult(reason: AuthFailure.missingToken);
    }
    return validateDetailed(token);
  }

  static String? extractToken(String? authHeader) {
    if (authHeader == null || authHeader.isEmpty) return null;
    const prefix = 'Bearer ';
    if (!authHeader.startsWith(prefix)) return null;
    final token = authHeader.substring(prefix.length).trim();
    return token.isEmpty ? null : token;
  }

  Future<ApiSession?> validate(String token) async =>
      (await validateDetailed(token)).session;

  /// [validate] ning rad etish sababini ham qaytaradigan varianti.
  Future<AuthResult> validateDetailed(String token) async {
    final cached = _cache[token];
    if (cached != null && !cached.isExpired) {
      await _touch(token);
      return AuthResult(session: _cache[token]);
    }
    if (cached != null) {
      await revoke(token);
      return const AuthResult(reason: AuthFailure.expired);
    }

    final db = await _db();
    final rows = await db.query(
      _table,
      where: 'token = ?',
      whereArgs: [token],
      limit: 1,
    );
    // Bu bazada bunday token umuman uchramadi: boshqa kassaning tokeni,
    // ilova qayta o'rnatilgan yoki sessiya bekor qilingan.
    if (rows.isEmpty) {
      return const AuthResult(reason: AuthFailure.unknownToken);
    }

    final row = rows.first;
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(
      row['expires_at'] as int,
    );
    if (DateTime.now().isAfter(expiresAt)) {
      await revoke(token);
      return const AuthResult(reason: AuthFailure.expired);
    }

    final permsStr = (row['permissions'] ?? '').toString();
    final session = ApiSession(
      token: token,
      userId: row['user_id'] as int,
      role: (row['role'] ?? '').toString(),
      permissions: permsStr.isEmpty ? const [] : permsStr.split(','),
      expiresAt: expiresAt,
    );
    _cache[token] = session;
    await _touch(token);
    return AuthResult(session: _cache[token]);
  }

  Future<void> _touch(String token) async {
    final now = DateTime.now();
    final newExpiry = now.add(sessionTtl);
    final cached = _cache[token];
    if (cached != null) {
      _cache[token] = ApiSession(
        token: cached.token,
        userId: cached.userId,
        role: cached.role,
        permissions: cached.permissions,
        expiresAt: newExpiry,
      );
    }
    try {
      final db = await _db();
      await db.update(
        _table,
        {
          'last_seen_at': now.millisecondsSinceEpoch,
          'expires_at': newExpiry.millisecondsSinceEpoch,
        },
        where: 'token = ?',
        whereArgs: [token],
      );
    } catch (e) {
      AppLogger.w(_logTag, 'Sessiya yangilanmadi', e);
    }
  }

  /// Faqat test uchun: xotiradagi keshni tashlab, tekshiruvni bazaga
  /// tayanishga majbur qiladi.
  void dropCache([String? token]) {
    if (token == null) {
      _cache.clear();
    } else {
      _cache.remove(token);
    }
  }

  Future<void> revoke(String token) async {
    _cache.remove(token);
    try {
      final db = await _db();
      await db.delete(_table, where: 'token = ?', whereArgs: [token]);
    } catch (e) {
      AppLogger.w(_logTag, 'Sessiya o\'chirilmadi', e);
    }
  }

  /// Xodim o'chirilganda yoki PIN o'zgarganda uning barcha sessiyalarini
  /// bekor qiladi — aks holda eski token ishlab qolaveradi.
  Future<void> revokeUser({required int userId, required String role}) async {
    _cache.removeWhere((_, s) => s.userId == userId && s.role == role);
    try {
      final db = await _db();
      await db.delete(
        _table,
        where: 'user_id = ? AND role = ?',
        whereArgs: [userId, role],
      );
    } catch (e) {
      AppLogger.w(_logTag, 'Sessiyalar o\'chirilmadi', e);
    }
  }

  Future<void> _purgeExpired(Database db) async {
    try {
      await db.delete(
        _table,
        where: 'expires_at < ?',
        whereArgs: [DateTime.now().millisecondsSinceEpoch],
      );
    } catch (e) {
      AppLogger.w(_logTag, 'Eskirgan sessiyalar tozalanmadi', e);
    }
  }
}

/// Login urinishlarini cheklab PIN'ni brute-force qilishni to'xtatadi.
/// 4 xonali PIN — atigi 10 000 variant; cheklovsiz server uni bir necha
/// soniyada topib beradi.
class LoginThrottle {
  LoginThrottle._();
  static final LoginThrottle instance = LoginThrottle._();

  static const int maxAttempts = 5;
  static const Duration window = Duration(minutes: 5);
  static const Duration lockout = Duration(minutes: 5);

  final Map<String, _Attempts> _attempts = {};

  /// `true` — urinishga ruxsat bor.
  bool allow(String clientKey) {
    final entry = _attempts[clientKey];
    if (entry == null) return true;
    final lockedUntil = entry.lockedUntil;
    if (lockedUntil != null && DateTime.now().isBefore(lockedUntil)) {
      return false;
    }
    if (DateTime.now().difference(entry.firstAttempt) > window) {
      _attempts.remove(clientKey);
      return true;
    }
    return entry.count < maxAttempts;
  }

  Duration remainingLock(String clientKey) {
    final until = _attempts[clientKey]?.lockedUntil;
    if (until == null) return Duration.zero;
    final left = until.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  void recordFailure(String clientKey) {
    final now = DateTime.now();
    final entry = _attempts[clientKey];
    if (entry == null || now.difference(entry.firstAttempt) > window) {
      _attempts[clientKey] = _Attempts(firstAttempt: now, count: 1);
      return;
    }
    entry.count++;
    if (entry.count >= maxAttempts) {
      entry.lockedUntil = now.add(lockout);
      AppLogger.w(_logTag, 'Login bloklandi ($clientKey): ketma-ket xatolar');
    }
  }

  void recordSuccess(String clientKey) => _attempts.remove(clientKey);
}

class _Attempts {
  _Attempts({required this.firstAttempt, required this.count});
  final DateTime firstAttempt;
  int count;
  DateTime? lockedUntil;
}
