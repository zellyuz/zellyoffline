import 'dart:convert';

import 'package:shelf/shelf.dart';

import 'api_context.dart';

/// Ro'yxat qaytaradigan endpoint'lar uchun sahifalash.
///
/// **Orqaga muvofiqlik muhim:** hozirgi desktop mijoz (`client` rejimi) bu
/// endpoint'lardan **yalang'och massiv** kutadi (`BaseRepository.getAll`).
/// Shuning uchun sahifalash — *ixtiyoriy*:
///
///  * `?limit` berilmasa → eski xatti-harakat, butun massiv qaytadi;
///  * `?limit` berilsa   → `{ "data": [...], "meta": {...} }` konverti.
///
/// Mobil ilova doim `?limit` yuboradi va konvert bilan ishlaydi. Eski
/// mijozlar hech narsa sezmaydi.
class Pagination {
  /// Bir sahifadagi yozuvlar soni.
  final int limit;

  /// Nechta yozuv tashlab ketiladi.
  final int offset;

  /// Mijoz sahifalashni so'radimi (`?limit` berildimi).
  final bool enabled;

  const Pagination._({
    required this.limit,
    required this.offset,
    required this.enabled,
  });

  /// Standart sahifa hajmi — mijoz `?limit` bersa-yu, qiymati noto'g'ri bo'lsa.
  static const int defaultLimit = 50;

  /// Eng katta ruxsat etilgan sahifa. Telefon 500 ta yozuvni ko'tarmaydi va
  /// bu — DoS himoyasi ham (`?limit=999999` bilan bazani band qilib bo'lmaydi).
  static const int maxLimit = 200;

  /// So'rovdan `?limit` / `?offset` ni o'qiydi.
  factory Pagination.of(Request request) {
    final q = request.url.queryParameters;
    final rawLimit = q['limit'];
    if (rawLimit == null) {
      return const Pagination._(limit: 0, offset: 0, enabled: false);
    }
    var limit = int.tryParse(rawLimit) ?? defaultLimit;
    if (limit <= 0) limit = defaultLimit;
    if (limit > maxLimit) limit = maxLimit;

    var offset = int.tryParse(q['offset'] ?? '0') ?? 0;
    if (offset < 0) offset = 0;

    return Pagination._(limit: limit, offset: offset, enabled: true);
  }

  /// SQL oxiriga qo'shiladigan band. Sahifalash so'ralmagan bo'lsa — bo'sh.
  ///
  /// `limit`/`offset` — `int.tryParse` dan o'tgan va chegaralangan sonlar,
  /// shuning uchun to'g'ridan-to'g'ri qo'yish xavfsiz (SQL injection yo'q).
  String get sqlSuffix => enabled ? ' LIMIT $limit OFFSET $offset' : '';

  /// Javobni to'g'ri shaklda qaytaradi.
  ///
  /// [total] — filtrga mos **umumiy** yozuvlar soni (sahifalashsiz).
  /// Sahifalash so'ralmagan bo'lsa e'tiborga olinmaydi.
  Response respond(List<Object?> rows, {int? total}) {
    if (!enabled) {
      return Response.ok(jsonEncode(rows), headers: ApiContext.jsonHeaders);
    }
    final count = total ?? rows.length;
    return Response.ok(
      jsonEncode({
        'data': rows,
        'meta': {
          'total': count,
          'limit': limit,
          'offset': offset,
          'has_more': offset + rows.length < count,
        },
      }),
      headers: ApiContext.jsonHeaders,
    );
  }
}
