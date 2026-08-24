import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../app_logger.dart';
import 'middleware/auth_middleware.dart';
import 'middleware/cors_middleware.dart';
import 'routes/admin_routes.dart';
import 'routes/auth_routes.dart';
import 'routes/catalog_routes.dart';
import 'routes/finance_routes.dart';
import 'routes/inventory_routes.dart';
import 'routes/media_routes.dart';
import 'routes/order_routes.dart';
import 'routes/print_routes.dart';
import 'routes/report_routes.dart';
import 'routes/staff_routes.dart';
import 'routes/table_routes.dart';
import 'websocket_manager.dart';

/// Kafedagi POS kompyuterida ishlaydigan lokal HTTP server.
///
/// Bu klass faqat **yig'uvchi**: pipeline (CORS → auth), WebSocket kanali va
/// route modullarini ro'yxatdan o'tkazish. Endpoint'larning o'zi
/// `routes/` papkasidagi modullarda, umumiy yordamchilar
/// [ApiContext] da (`api_context.dart`).
///
/// Hujjat: loyiha ildizidagi `API.md`.
class ApiServer {
  static HttpServer? _server;
  static final _router = Router();
  static bool _routesReady = false;

  static Future<String?> start(int port) async {
    _setupRoutes();

    try {
      _server = await io.serve(
        Pipeline()
            .addMiddleware(logRequests())
            .addMiddleware(corsMiddleware())
            .addMiddleware(authMiddleware())
            .addHandler(_router.call),
        InternetAddress.anyIPv4,
        port,
      );
      AppLogger.i(
        'ApiServer',
        'Server ishga tushdi: ${_server!.address.address}:${_server!.port}',
      );
      return _server!.address.address;
    } catch (e) {
      AppLogger.e('ApiServer', 'Serverni ishga tushirib bo\'lmadi', e);
      return null;
    }
  }

  static void stop() {
    _server?.close();
    _server = null;
  }

  /// Route'larni bir marta ro'yxatdan o'tkazadi.
  ///
  /// `_router` — static, shuning uchun serverni to'xtatib qayta ishga
  /// tushirganda route'lar ikki marta qo'shilmasligi kerak.
  static void _setupRoutes() {
    if (_routesReady) return;
    _routesReady = true;

    // WebSocket real-time kanali.
    // Eslatma: kanal orqali faqat "nimadir o'zgardi" signali (event nomi va
    // ID) yuboriladi — maxfiy ma'lumot emas. Ma'lumotning o'zi baribir
    // autentifikatsiyalangan REST so'rovi orqali olinadi.
    _router.get(
      '/ws',
      webSocketHandler((WebSocketChannel channel, String? protocol) {
        WebSocketManager.instance.addClient(channel);
      }),
    );

    AuthRoutes.register(_router);
    TableRoutes.register(_router);
    CatalogRoutes.register(_router);
    StaffRoutes.register(_router);
    FinanceRoutes.register(_router);
    OrderRoutes.register(_router);
    ReportRoutes.register(_router);
    MediaRoutes.register(_router);
    PrintRoutes.register(_router);
    InventoryRoutes.register(_router);

    // Admin oxirida: '/orders' kabi umumiy yo'llar domen
    // route'laridan keyin ro'yxatdan o'tsin.
    AdminRoutes.register(_router);
  }
}
