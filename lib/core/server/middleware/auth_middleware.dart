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

      final result = await AuthTokenService.instance.authenticate(
        request.headers['Authorization'],
      );
      final session = result.session;
      if (session == null) {
        // Sabab aniq aytiladi: "muddati tugagan" degan umumiy xabar eng ko'p
        // uchraydigan holatni (boshqa kassaning tokeni) yashirib, domen yoki
        // litsenziyani qidirishga majbur qilardi.
        final reason = result.reason ?? AuthFailure.missingToken;
        return ApiContext.unauthorized(reason.message, code: reason.code);
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
