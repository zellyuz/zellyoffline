import 'package:shelf/shelf.dart';

import '../api_context.dart';
import '../auth_token_service.dart';

/// Har bir so'rovni tekshiradigan markazlashgan qatlam.
///
/// Ilgari autentifikatsiya endpoint'lar ichida qo'lda va nomuvofiq
/// bajarilardi — ko'p endpoint umuman tekshirmasdi. Endi qoida bitta
/// joyda: ochiq yo'llardan tashqari hamma narsa yaroqli token talab qiladi.
Middleware authMiddleware() {
  return (Handler innerHandler) {
    return (Request request) async {
      if (ApiContext.isPublicPath(request.url.path) ||
          request.method == 'OPTIONS') {
        return innerHandler(request);
      }

      final session = await AuthTokenService.instance.resolve(
        request.headers['Authorization'],
      );
      if (session == null) {
        return ApiContext.unauthorized(
          'Token yaroqsiz yoki muddati tugagan. Qaytadan kiring.',
        );
      }

      if (session.isWaiter && ApiContext.isStaffOnlyPath(request.url.path)) {
        return ApiContext.forbidden(
          'Bu bo\'lim uchun administrator huquqi kerak',
        );
      }

      return innerHandler(
        request.change(context: {ApiContext.sessionKey: session}),
      );
    };
  };
}
