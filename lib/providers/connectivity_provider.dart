import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/database_helper.dart';
import 'package:http/http.dart' as http;
import '../core/server/api_server.dart';
import '../core/server/websocket_manager.dart';
import '../core/services/ws_client_service.dart';
import '../core/services/relay_service.dart';
import '../core/services/tunnel_service.dart';
import '../models/order.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

enum ConnectivityMode { local, server, client }

class ConnectivityProvider extends ChangeNotifier {
  ConnectivityMode _mode = ConnectivityMode.local;
  String? _serverIp;
  int _port = 8080;
  String? _clientBaseUrl;
  bool _isServerRunning = false;
  String? _authToken;
  Map<String, dynamic>? _currentUser;
  String _connectionStatus = '';
  bool _isSuccess = false;
  String? _lastError;
  String? _localImagesDirPath;

  ConnectivityMode get mode => _mode;
  String? get serverIp => _serverIp;
  int get port => _port;
  String? get clientBaseUrl => _clientBaseUrl;
  bool get isServerRunning => _isServerRunning;
  String? get authToken => _authToken;
  Map<String, dynamic>? get currentUser => _currentUser;
  String get connectionStatus => _connectionStatus;
  bool get isSuccess => _isSuccess;
  String? get lastError => _lastError;

  /// Exposes server-pushed events to UI listeners (client mode only).
  Stream<Map<String, dynamic>> get wsEvents => WsClientService.instance.events;

  /// Broadcast an event to all connected WS clients (server/local mode).
  void broadcastEvent(String event, [Map<String, dynamic>? data]) {
    WebSocketManager.instance.broadcast(event, data);
  }

  ConnectivityProvider() {
    loadSettings();
  }

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _mode = ConnectivityMode.values[prefs.getInt('connectivity_mode') ?? 0];
    _clientBaseUrl = prefs.getString('client_base_url');
    _port = prefs.getInt('server_port') ?? 8080;

    if (_mode == ConnectivityMode.server) {
      startServer();
    } else if (_mode == ConnectivityMode.client && _clientBaseUrl != null) {
      WsClientService.instance.connect(_clientBaseUrl!);
    }

    final appDocDir = await getApplicationSupportDirectory();
    _localImagesDirPath = p.join(appDocDir.path, 'product_images');

    notifyListeners();
  }

  Future<void> setMode(ConnectivityMode mode) async {
    _mode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('connectivity_mode', mode.index);

    if (mode == ConnectivityMode.server) {
      WsClientService.instance.disconnect();
      startServer();
    } else if (mode == ConnectivityMode.client) {
      stopServer();
      if (_clientBaseUrl != null) {
        WsClientService.instance.connect(_clientBaseUrl!);
      }
    } else {
      stopServer();
      WsClientService.instance.disconnect();
    }
    notifyListeners();
  }

  Future<void> startServer() async {
    if (_isServerRunning) return;

    String? foundIp;
    try {
      // 1. WiFi IP ni tekshirish
      final info = NetworkInfo();
      foundIp = await info.getWifiIP();

      // 2. Agar WiFi bo'lmasa, barcha interfeyslarni tekshirish (Ethernet va h.k.)
      if (foundIp == null || foundIp == '0.0.0.0' || foundIp == '127.0.0.1') {
        final interfaces = await NetworkInterface.list(
          includeLoopback: false,
          type: InternetAddressType.IPv4,
        );
        if (interfaces.isNotEmpty) {
          foundIp = interfaces.first.addresses.first.address;
        }
      }
    } catch (e) {
      debugPrint('IP detection error: $e');
    }

    _serverIp = foundIp;

    final success = await ApiServer.start(_port);
    if (success != null) {
      _isServerRunning = true;
      if (success != '0.0.0.0') {
        _serverIp = success;
      }
      // Barqaror domen (sozlangan bo'lsa) — Telegram WebApp havolasi
      // shundan olinadi. Cloudflare tunneli zaxira sifatida qoladi.
      RelayService.instance.start(_port);
      TunnelService.instance.start(_port);
    }
    notifyListeners();
  }

  void stopServer() {
    ApiServer.stop();
    RelayService.instance.stop();
    TunnelService.instance.stop();
    _isServerRunning = false;
    notifyListeners();
  }

  Future<void> setPort(int port) async {
    _port = port;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('server_port', port);
    if (_mode == ConnectivityMode.server) {
      stopServer();
      startServer();
    }
    notifyListeners();
  }

  Future<void> setClientBaseUrl(String url) async {
    _clientBaseUrl = url;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('client_base_url', url);
    if (_mode == ConnectivityMode.client && url.isNotEmpty) {
      WsClientService.instance.connect(url);
    }
    notifyListeners();
  }

  Future<void> testConnection() async {
    _connectionStatus = 'Tekshirilmoqda...';
    _isSuccess = false;
    notifyListeners();

    try {
      if (_mode == ConnectivityMode.client) {
        if (_clientBaseUrl == null || !_clientBaseUrl!.startsWith('http')) {
          _connectionStatus =
              'Xato: URL noto‘g‘ri shaklda (http://1.2.3.4:8080)';
          notifyListeners();
          return;
        }
        final response = await http
            .get(Uri.parse('$_clientBaseUrl/locations'))
            .timeout(const Duration(seconds: 5));
        if (response.statusCode == 200) {
          _connectionStatus = 'Ulandi! Server ishlamoqda.';
          _isSuccess = true;
        } else {
          _connectionStatus =
              'Xato: Serverdan nojo‘ya javob (${response.statusCode})';
        }
      } else if (_mode == ConnectivityMode.server) {
        if (_isServerRunning) {
          _connectionStatus = 'Server ishlamoqda: $_serverIp:$_port';
          _isSuccess = true;
        } else {
          _connectionStatus = 'Xato: Server ishlamayapti!';
        }
      } else {
        _connectionStatus = 'Lokal rejim: Server talab qilinmaydi.';
        _isSuccess = true;
      }
    } catch (e) {
      _connectionStatus = 'Ulanmadi: $e';
    }
    notifyListeners();
  }

  bool shouldFetchRemote({bool forceRemote = false}) {
    if (forceRemote) return true;
    // Only client-mode devices fetch from a remote server.
    // Server/local devices always read their own DB regardless of logged-in role.
    return _mode == ConnectivityMode.client;
  }

  void setCurrentUser(Map<String, dynamic>? user) {
    _currentUser = user;
    notifyListeners();
  }

  Future<String?> updateCurrentUserPin(String oldPin, String newPin) async {
    if (_currentUser == null) return 'Foydalanuvchi aniqlanmadi';

    // 1. Verify old PIN locally (assuming we have it in _currentUser or database)
    final db = DatabaseHelper.instance;
    final userId = _currentUser!['id'];

    if (userId == null) {
      // For fallback admin account without real ID in DB
      return "Ushbu foydalanuvchi PIN kodini o'zgartira olmaydi. Tizim admini bilan bog'laning.";
    }

    final userInDb = await db.queryByColumn('users', 'id', userId);
    if (userInDb.isEmpty || userInDb.first['pin'] != oldPin) {
      return "Joriy PIN kod noto'g'ri";
    }

    // 2. Check for duplicate PIN across ALL users
    final duplicateCheck = await db.queryByColumn('users', 'pin', newPin);
    if (duplicateCheck.isNotEmpty) {
      final otherUser = duplicateCheck.first;
      if (otherUser['id'] != userId) {
        return 'Ushbu PIN kod allaqachon boshqa foydalanuvchi tomonidan ishlatilmoqda';
      }
    }

    // 3. Update PIN in DB
    await db.update('users', {'pin': newPin}, 'id = ?', [userId]);

    // 4. Update local state
    final updatedUser = Map<String, dynamic>.from(_currentUser!);
    updatedUser['pin'] = newPin;
    _currentUser = updatedUser;

    notifyListeners();
    return null; // Success
  }

  // API Methods for Client
  Future<bool> login(String pin) async {
    _lastError = null;
    notifyListeners();

    if (_mode == ConnectivityMode.local) {
      // Logic handled in LoginScreen via AppSettingsProvider for now
      return false;
    }

    try {
      final response = await http
          .post(
            Uri.parse('$_clientBaseUrl/auth/login'),
            body: jsonEncode({'pin': pin}),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 5));

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        _authToken = data['token'];
        _currentUser = data['user'];
        notifyListeners();
        return true;
      } else {
        _lastError = data['error'] ?? 'Kirishda xatolik yuz berdi';
      }
    } catch (e) {
      _lastError = 'Server bilan ulanishda xatolik: $e';
    }
    notifyListeners();
    return false;
  }

  /// Sessiya muddati tugaganda (401) chaqiriladi — UI qayta login so'raydi.
  bool _sessionExpired = false;
  bool get sessionExpired => _sessionExpired;

  /// [responseBody] — serverning 401 javobi. Undagi `error` matni sababni
  /// aniq aytadi ("bu token boshqa kassaniki", "muddati tugagan"), shuning
  /// uchun uni o'z umumiy matnimiz bilan almashtirmaymiz.
  void _handleUnauthorized([String? responseBody]) {
    if (_authToken == null) return;
    _authToken = null;
    _sessionExpired = true;
    _lastError =
        _serverError(responseBody) ??
        'Sessiya muddati tugadi. Qaytadan kiring.';
    notifyListeners();
  }

  static String? _serverError(String? body) {
    if (body == null || body.isEmpty) return null;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] is String) {
        return decoded['error'] as String;
      }
    } catch (_) {
      // JSON emas (nginx/relay xatosi) — umumiy matnga qaytamiz.
    }
    return null;
  }

  void clearSessionExpiredFlag() {
    _sessionExpired = false;
  }

  /// Serverdagi sessiyani yopadi. Ilovadan chiqishda chaqirilishi kerak —
  /// aks holda token muddati tugagunicha ishlab qolaveradi.
  Future<void> logout() async {
    final token = _authToken;
    _authToken = null;
    _currentUser = null;
    _sessionExpired = false;
    WsClientService.instance.disconnect();
    notifyListeners();
    if (token == null || _clientBaseUrl == null) return;
    try {
      await http
          .post(
            Uri.parse('$_clientBaseUrl/auth/logout'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 3));
    } catch (e) {
      debugPrint('Logout error: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getRemoteData(String path) async {
    try {
      final response = await http
          .get(
            Uri.parse('$_clientBaseUrl$path'),
            headers: {'Authorization': 'Bearer $_authToken'},
          )
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(jsonDecode(response.body));
      }
      if (response.statusCode == 401) _handleUnauthorized(response.body);
    } catch (e) {
      debugPrint('Remote Data Error: $e');
    }
    return [];
  }

  Future<bool> postRemoteData(String path, Map<String, dynamic> data) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_clientBaseUrl$path'),
            body: jsonEncode(data),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $_authToken',
            },
          )
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 401) _handleUnauthorized(response.body);
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Post Remote Data Error: $e');
      return false;
    }
  }

  Future<bool> payOrder(
    String orderId,
    Map<String, dynamic> paymentData, {
    double roomCharge = 0,
    double serviceFee = 0,
    double foodTotal = 0,
    double grandTotal = 0,
    int? waiterId,
  }) async {
    final Map<String, dynamic> fullData = Map<String, dynamic>.from(paymentData);
    fullData['room_charge'] = roomCharge;
    fullData['service_total'] = serviceFee;
    fullData['food_total'] = foodTotal;
    fullData['grand_total'] = grandTotal;
    fullData['waiter_id'] = waiterId;

    return await postRemoteData('/orders/$orderId/pay', fullData);
  }

  Future<bool> deleteRemoteData(String path) async {
    try {
      final response = await http
          .delete(
            Uri.parse('$_clientBaseUrl$path'),
            headers: {'Authorization': 'Bearer $_authToken'},
          )
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 401) _handleUnauthorized(response.body);
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Delete Remote Data Error: $e');
      return false;
    }
  }

  /// Sends a print job to the server (client mode) or prints locally.
  /// Returns an error message on failure, null on success.
  Future<String?> requestPrint(Order order) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_clientBaseUrl/print_job'),
            body: jsonEncode(order.toPrintPayload()),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $_authToken',
            },
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) return null;
      // 409 — serverda tayyor mahsulot qoldig'i yetmadi (§8). Chaqiruvchi
      // buni oddiy printer xatosidan ajratishi kerak, shu sabab prefiks.
      if (response.statusCode == 409) {
        String message = 'Mahsulot qoldig\'i yetarli emas';
        try {
          final data = jsonDecode(response.body);
          if (data is Map && data['error'] is String) {
            message = data['error'] as String;
          }
        } catch (_) {}
        return 'STOCK:$message';
      }
      return 'Server chop etishda xatolik: ${response.statusCode}';
    } catch (e) {
      debugPrint('requestPrint error: $e');
      return 'Printer serverga ulanishda xatolik: $e';
    }
  }

  Future<String?> uploadImage(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final response = await http
          .post(
            Uri.parse('$_clientBaseUrl/upload/image'),
            body: bytes,
            headers: {'Authorization': 'Bearer $_authToken'},
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['fileName'];
      }
    } catch (e) {
      debugPrint('Upload Image Error: $e');
    }
    return null;
  }

  String? getImageUrl(String? path) {
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http')) return path;

    // If it's a filename (no slash or drive letter), and we're in client mode
    if (_mode == ConnectivityMode.client &&
        !path.contains('/') &&
        !path.contains('\\')) {
      return '$_clientBaseUrl/uploads/$path';
    }

    // If it's a server and it's just a filename, it might be in our own uploads
    if (_mode == ConnectivityMode.server &&
        !path.contains('/') &&
        !path.contains('\\')) {
      return 'http://localhost:$_port/uploads/$path';
    }

    // Fallback for local/server mode filename resolution to local path
    if (_localImagesDirPath != null &&
        !path.contains('/') &&
        !path.contains('\\')) {
      final localPath = p.join(_localImagesDirPath!, path);
      if (File(localPath).existsSync()) {
        return localPath;
      }
    }

    return path;
  }
}
