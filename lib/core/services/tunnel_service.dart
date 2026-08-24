import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../database_helper.dart';
import 'relay_service.dart';

enum TunnelStatus { idle, starting, connected, noExe }

class TunnelService extends ChangeNotifier {
  static final TunnelService instance = TunnelService._();
  TunnelService._();

  Process? _process;
  String?  _tunnelUrl;
  String?  _botToken;
  String?  _chatId;
  TunnelStatus _status = TunnelStatus.idle;
  String?  _exePath;

  String?      get tunnelUrl => _tunnelUrl;
  TunnelStatus get status    => _status;
  String?      get exePath   => _exePath;
  bool         get isConnected => _status == TunnelStatus.connected;

  Future<void> start(int port) async {
    if (_process != null) return;

    await _loadCredentials();

    _exePath = _findCloudflared();
    if (_exePath == null) {
      _status = TunnelStatus.noExe;
      notifyListeners();
      debugPrint('[Tunnel] cloudflared.exe topilmadi');
      return;
    }

    _status = TunnelStatus.starting;
    notifyListeners();

    try {
      _process = await Process.start(
        _exePath!,
        ['tunnel', '--url', 'http://localhost:$port'],
        runInShell: false,
      );

      _process!.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_onLine);

      _process!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_onLine);

      debugPrint('[Tunnel] cloudflared ishga tushdi');
    } catch (e) {
      debugPrint('[Tunnel] start xato: $e');
      _process = null;
      _status = TunnelStatus.idle;
      notifyListeners();
    }
  }

  void _onLine(String line) {
    debugPrint('[CF] $line');
    if (_tunnelUrl != null) return;

    final match = RegExp(r'https://[a-z0-9\-]+\.trycloudflare\.com').firstMatch(line);
    if (match == null) return;

    _tunnelUrl = match.group(0);
    _status    = TunnelStatus.connected;
    notifyListeners();
    debugPrint('[Tunnel] URL topildi: $_tunnelUrl');

    // Relay yoqilgan bo'lsa, ishga tushish xabarini U yuboradi — uning
    // manzili barqaror. Ikkalasi yuborsa foydalanuvchi ikkita xabar oladi
    // va qaysi tugma "to'g'ri" ekani noaniq bo'lib qoladi.
    if (RelayService.instance.isEnabled) {
      debugPrint('[Tunnel] Relay yoqilgan — Telegram xabarini relay yuboradi');
      return;
    }

    if (_botToken != null && _botToken!.isNotEmpty &&
        _chatId   != null && _chatId!.isNotEmpty) {
      _sendTelegram('$_tunnelUrl/reports/view');
    } else {
      debugPrint('[Tunnel] Telegram sozlanmagan');
    }
  }

  /// Boshqa xizmat (masalan [RelayService]) o'z manzili bilan "server ishga
  /// tushdi" xabarini yuborishi uchun. Bot token/chat ID shu yerda o'qiladi.
  Future<void> notifyServerStarted(String webAppUrl) async {
    await _loadCredentials();
    if (_botToken == null || _botToken!.isEmpty ||
        _chatId == null || _chatId!.isEmpty) {
      debugPrint('[Tunnel] Telegram sozlanmagan');
      return;
    }
    await _sendTelegram(webAppUrl);
  }

  Future<void> _sendTelegram(String webAppUrl) async {
    final body = jsonEncode({
      'chat_id': _chatId,
      'text': '✅ *POS serveri ishga tushdi*\n🕐 ${_nowStr()}',
      'parse_mode': 'Markdown',
      'reply_markup': {
        'inline_keyboard': [
          [
            {
              'text': '📊 Hisobotni ochish',
              'web_app': {'url': webAppUrl},
            }
          ]
        ],
      },
    });

    try {
      final res = await http.post(
        Uri.parse('https://api.telegram.org/bot$_botToken/sendMessage'),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
        body: body,
      );
      if (res.statusCode == 200) {
        debugPrint('[Tunnel] Telegram ga yuborildi ✅');
      } else {
        debugPrint('[Tunnel] Telegram xato: ${res.statusCode} ${res.body}');
      }
    } catch (e) {
      debugPrint('[Tunnel] Telegram ulanish xato: $e');
    }
  }

  Future<void> _loadCredentials() async {
    try {
      final db = await DatabaseHelper.instance.database;
      final rows = await db.query(
        'settings',
        where: "key IN ('telegram_bot_token','telegram_chat_id')",
      );
      for (final r in rows) {
        final key = r['key'] as String?;
        final val = r['value'] as String?;
        if (key == 'telegram_bot_token') _botToken = val;
        if (key == 'telegram_chat_id')   _chatId   = val;
      }
    } catch (e) {
      debugPrint('[Tunnel] credentials yuklanmadi: $e');
    }
  }

  void stop() {
    _process?.kill();
    _process   = null;
    _tunnelUrl = null;
    _botToken  = null;
    _chatId    = null;
    _status    = TunnelStatus.idle;
    notifyListeners();
  }

  String? _findCloudflared() {
    final candidates = [
      '${Platform.environment['USERPROFILE']}\\Downloads\\cloudflared-windows-386.exe',
      '${Platform.environment['USERPROFILE']}\\Downloads\\cloudflared.exe',
      r'C:\cloudflared\cloudflared.exe',
      'cloudflared.exe',
    ];
    for (final path in candidates) {
      if (File(path).existsSync()) return path;
    }
    return null;
  }

  String _nowStr() {
    final n = DateTime.now();
    return '${_p(n.hour)}:${_p(n.minute)} ${_p(n.day)}.${_p(n.month)}.${n.year}';
  }

  String _p(int v) => v.toString().padLeft(2, '0');
}
