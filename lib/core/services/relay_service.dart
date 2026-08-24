import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../app_logger.dart';
import '../../data/repositories/settings_repository.dart';
import 'tunnel_service.dart';

/// Relay ulanishining holati.
enum RelayStatus {
  /// Sozlanmagan yoki to'xtatilgan.
  idle,

  /// Sozlamalar to'liq emas (domen/server/token yo'q).
  notConfigured,

  /// `frpc.exe` topilmadi.
  noExe,

  /// Ulanmoqda.
  starting,

  /// Ulandi — [RelayService.publicUrl] ishlaydi.
  connected,

  /// Ulanib bo'lmadi (server o'chiq, token noto'g'ri, domen band...).
  error,
}

/// POS API'sini barqaror domen orqali internetga chiqaradi.
///
/// [TunnelService] (Cloudflare) dan farqi — **URL o'zgarmaydi**. Cloudflare
/// har ishga tushishda yangi `https://tasodifiy.trycloudflare.com` beradi,
/// natijada Telegram'dagi eski WebApp tugmalari o'lik bo'lib qoladi. Bu yerda
/// domen sozlamalarda saqlanadi va hech qachon o'zgarmaydi:
///
///     https://mehmon.zelly.uz/reports/view
///
/// Ishlash sxemasi (`deploy/README.md`):
///
///     Telefon ──HTTPS──► server (nginx + frps) ──tunnel──► POS (frpc → :8080)
///
/// POS serverga **o'zi** ulanadi, shuning uchun kafeda oq IP yoki port
/// forwarding kerak emas.
class RelayService extends ChangeNotifier {
  RelayService._();
  static final RelayService instance = RelayService._();

  /// Sozlama kalitlari (`settings` jadvali).
  static const kDomain = 'relay_domain';
  static const kServer = 'relay_server';
  static const kToken = 'relay_token';
  static const kEnabled = 'relay_enabled';

  /// Boshqaruv kanali **443-port** orqali ketadi.
  ///
  /// Sabab: kafe tarmoqlari va hosting provayderlari 22/80/443 dan boshqa
  /// portlarni bloklaydi — `5.104.108.235:7000` ga ulanish `i/o timeout`
  /// beradi (serverga SYN paketi ham yetib bormaydi). Shuning uchun frpc
  /// `wss` bilan nginx'ga ulanadi, nginx esa uni frps ga uzatadi.
  static const _defaultServer = 'mehmon.zelly.uz:443';

  final SettingsRepository _settings = SettingsRepository();

  Process? _process;
  RelayStatus _status = RelayStatus.idle;
  String? _domain;
  String? _exePath;
  String? _lastError;
  int _port = 8080;
  bool _enabled = false;

  /// Sozlamalarda yoqilganmi. [TunnelService] shunga qarab Telegram xabarini
  /// yuborish-yubormaslikni hal qiladi (ikkita xabar ketmasligi uchun).
  bool get isEnabled => _enabled;

  RelayStatus get status => _status;
  String? get domain => _domain;
  String? get exePath => _exePath;
  String? get lastError => _lastError;
  bool get isConnected => _status == RelayStatus.connected;

  /// Hisobot paneli va mobil ilova ishlatadigan barqaror manzil.
  /// Ulanmagan bo'lsa `null` — chaqiruvchi [TunnelService] ga qaytishi mumkin.
  String? get publicUrl =>
      _status == RelayStatus.connected && _domain != null
          ? 'https://$_domain'
          : null;

  /// Telegram WebApp tugmasi uchun to'liq manzil.
  String? get reportsUrl =>
      publicUrl == null ? null : '$publicUrl/reports/view';

  // ── Sozlamalar ───────────────────────────────────────────────────────────

  /// Developer bo'limi shu metod orqali saqlaydi.
  Future<void> saveConfig({
    required String domain,
    required String server,
    required String token,
    required bool enabled,
  }) async {
    await _settings.setValue(kDomain, domain.trim());
    await _settings.setValue(kServer, server.trim());
    await _settings.setValue(kToken, token.trim());
    await _settings.setValue(kEnabled, enabled ? '1' : '0');
    AppLogger.i('Relay', 'Sozlamalar saqlandi | domen: ${domain.trim()}');
  }

  Future<Map<String, String>> loadConfig() async {
    return {
      kDomain: await _settings.getValue(kDomain) ?? '',
      kServer: await _settings.getValue(kServer) ?? _defaultServer,
      kToken: await _settings.getValue(kToken) ?? '',
      kEnabled: await _settings.getValue(kEnabled) ?? '0',
    };
  }

  // ── Hayot sikli ──────────────────────────────────────────────────────────

  /// [ConnectivityProvider] server rejimida ishga tushirganda chaqiriladi.
  Future<void> start(int port) async {
    if (_process != null) return;
    _port = port;
    _lastError = null;

    final cfg = await loadConfig();
    _enabled = cfg[kEnabled] == '1';
    if (!_enabled) {
      _set(RelayStatus.idle);
      return;
    }

    final domain = cfg[kDomain]!;
    final server = cfg[kServer]!;
    final token = cfg[kToken]!;

    if (domain.isEmpty || server.isEmpty || token.isEmpty) {
      _lastError = 'Domen, server yoki token kiritilmagan';
      _set(RelayStatus.notConfigured);
      return;
    }

    _exePath = _findFrpc();
    if (_exePath == null) {
      _lastError = 'frpc.exe topilmadi';
      _set(RelayStatus.noExe);
      AppLogger.w('Relay', 'frpc.exe topilmadi — relay ishga tushmadi');
      return;
    }

    final configFile = await _writeConfig(
      domain: domain,
      server: server,
      token: token,
    );
    if (configFile == null) {
      _lastError = 'Konfiguratsiya faylini yozib bo\'lmadi';
      _set(RelayStatus.error);
      return;
    }

    _domain = domain;
    _set(RelayStatus.starting);

    // Ilova to'satdan yopilsa (Task Manager, quvvat uzilishi) frpc yetim
    // bo'lib qoladi va domenni band qilib turadi — yangi nusxa
    // "domen band" xatosini oladi. Shuning uchun ishga tushishdan oldin
    // eski nusxalar yopiladi.
    await _killStaleProcesses();

    try {
      _process = await Process.start(
        _exePath!,
        ['-c', configFile.path],
        runInShell: false,
      );

      _process!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_onLine);
      _process!.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_onLine);

      // Jarayon o'lsa holat "connected" bo'lib qolmasin.
      unawaited(_process!.exitCode.then(_onExit));

      AppLogger.i('Relay', 'frpc ishga tushdi | domen: $domain');
    } catch (e) {
      _lastError = '$e';
      _process = null;
      _set(RelayStatus.error);
      AppLogger.e('Relay', 'frpc ishga tushmadi', e);
    }
  }

  void stop() {
    _process?.kill();
    _process = null;
    _domain = null;
    _lastError = null;
    _set(RelayStatus.idle);
    AppLogger.i('Relay', 'To\'xtatildi');
  }

  /// Sozlama o'zgargandan keyin qayta ulanish.
  Future<void> restart() async {
    final port = _port;
    stop();
    await start(port);
  }

  // ── frpc chiqishini o'qish ───────────────────────────────────────────────

  void _onLine(String line) {
    if (line.trim().isEmpty) return;
    AppLogger.d('Relay', line);

    // frpc muvaffaqiyatli ro'yxatdan o'tganda shu qatorni yozadi.
    if (line.contains('start proxy success') ||
        line.contains('login to server success')) {
      if (_status != RelayStatus.connected) {
        _lastError = null;
        _set(RelayStatus.connected);
        AppLogger.i('Relay', 'Ulandi: $publicUrl');
        _announce();
      }
      return;
    }

    // Eng ko'p uchraydigan xatolar — foydalanuvchiga tushunarli qilib.
    if (line.contains('authentication failed') ||
        line.contains('token not match')) {
      _fail('Token noto\'g\'ri — serverdagi token bilan solishtiring');
    } else if (line.contains('already exists') ||
        line.contains('custom domain') && line.contains('conflict')) {
      _fail('Bu domen boshqa kassa tomonidan band qilingan');
    } else if (line.contains('connection refused') ||
        line.contains('i/o timeout') ||
        line.contains('dial tcp')) {
      _fail('Serverga ulanib bo\'lmadi — internet yoki server manzilini '
          'tekshiring');
    }
  }

  /// Telegram'ga "server ishga tushdi" xabarini **barqaror** havola bilan
  /// yuboradi. Xabar bir marta — qayta ulanishlarda takrorlanmaydi, chunki
  /// [_announce] faqat holat `connected` ga o'tganda chaqiriladi.
  void _announce() {
    final url = reportsUrl;
    if (url == null) return;
    TunnelService.instance.notifyServerStarted(url).catchError((Object e) {
      AppLogger.w('Relay', 'Telegram xabari yuborilmadi: $e');
    });
  }

  void _onExit(int code) {
    if (_process == null) return; // stop() orqali to'xtatilgan
    _process = null;
    _fail('frpc to\'xtab qoldi (kod: $code)');
    AppLogger.w('Relay', 'frpc kutilmaganda to\'xtadi | kod: $code');
  }

  void _fail(String message) {
    _lastError = message;
    _set(RelayStatus.error);
  }

  void _set(RelayStatus s) {
    if (_status == s) return;
    _status = s;
    notifyListeners();
  }

  // ── Fayllar ──────────────────────────────────────────────────────────────

  /// `frpc.toml` ni ish paytida yaratadi.
  ///
  /// ⚠️ TOML tuzog'i: `transport.*` kabi nuqtali kalitlar har qanday
  /// `[bo'lim]` dan **oldin** turishi shart, aks holda ular oldingi bo'limning
  /// ichiga tushib qoladi va frpc "unknown field" deb yiqiladi.
  Future<File?> _writeConfig({
    required String domain,
    required String server,
    required String token,
  }) async {
    try {
      final parts = server.split(':');
      final host = parts.first.trim();
      final port = parts.length > 1 ? int.tryParse(parts[1].trim()) ?? 443 : 443;

      final dir = Directory(_configDir());
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final file = File('${dir.path}${Platform.pathSeparator}frpc.toml');

      // Proxy nomi serverda yagona bo'lishi kerak — domenning o'zidan olamiz.
      final proxyName = 'zelly-${domain.replaceAll('.', '-')}';

      file.writeAsStringSync('''
# Bu fayl Zelly POS tomonidan avtomatik yaratiladi — qo'lda tahrirlamang.
# Sozlamalar: Developer → Tashqi domen (relay).

serverAddr = "$host"
serverPort = $port

# 443 orqali WebSocket-over-TLS. To'g'ridan-to'g'ri frp portiga ulanish
# ko'p tarmoqlarda bloklanadi — 443 esa hamma joyda ochiq.
transport.protocol = "wss"

auth.method = "token"
auth.token  = "$token"

loginFailExit = false

log.to      = "frpc.log"
log.level   = "info"
log.maxDays = 7

transport.tcpMux            = true
transport.poolCount         = 3
transport.heartbeatInterval = 20
transport.heartbeatTimeout  = 60

[[proxies]]
name = "$proxyName"
type = "http"
customDomains = ["$domain"]
localIP   = "127.0.0.1"
localPort = $_port
transport.useCompression = true
''');
      return file;
    } catch (e) {
      AppLogger.e('Relay', 'frpc.toml yozilmadi', e);
      return null;
    }
  }

  /// Oldingi ishdan qolgan `frpc.exe` jarayonlarini yopadi.
  ///
  /// POS kompyuterida frpc'ni faqat shu ilova ishlatadi, shuning uchun
  /// nom bo'yicha yopish xavfsiz.
  Future<void> _killStaleProcesses() async {
    if (!Platform.isWindows) return;
    try {
      final r = await Process.run('taskkill', ['/IM', 'frpc.exe', '/F']);
      if (r.exitCode == 0) {
        AppLogger.i('Relay', 'Eski frpc jarayonlari yopildi');
      }
    } catch (e) {
      AppLogger.w('Relay', 'Eski frpc yopilmadi: $e');
    }
  }

  String _configDir() {
    final base = Platform.environment['LOCALAPPDATA'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.systemTemp.path;
    return '$base${Platform.pathSeparator}Zelly${Platform.pathSeparator}relay';
  }

  /// `frpc.exe` ni qidiradi.
  ///
  /// Birinchi navbatda ilova papkasidan — u dastur bilan birga tarqatiladi.
  /// [TunnelService] dagi kabi faqat `Downloads` ga tayanish ishonchsiz:
  /// foydalanuvchi faylni ko'chirsa ulanish yo'qoladi.
  String? _findFrpc() {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final sep = Platform.pathSeparator;
    final home = Platform.environment['USERPROFILE'] ?? '';

    final candidates = [
      '$exeDir${sep}frpc.exe',
      '$exeDir${sep}data${sep}frpc.exe',
      '$exeDir${sep}relay${sep}frpc.exe',
      r'C:\frp\frpc.exe',
      if (home.isNotEmpty) '$home\\Downloads\\frpc.exe',
      'frpc.exe',
    ];

    for (final path in candidates) {
      try {
        if (File(path).existsSync()) return path;
      } catch (_) {
        // Yo'l yaroqsiz bo'lsa keyingisiga o'tamiz.
      }
    }
    return null;
  }
}
