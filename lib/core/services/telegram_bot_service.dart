import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../database_helper.dart';
import '../utils/price_formatter.dart';
import 'relay_service.dart';
import 'tunnel_service.dart';

class TelegramBotService {
  static final TelegramBotService instance = TelegramBotService._();
  TelegramBotService._();

  Timer? _pollingTimer;
  int _lastUpdateId = 0;
  String? _token;
  bool _isRunning = false;
  String _restaurantName = 'ZELLY';
  // Ruxsat berilgan chat ID'lar (ilovada telegram_chat_id sozlamasidan, vergul bilan ajratilgan)
  Set<int> _allowedChatIds = {};

  bool get isRunning => _isRunning;
  String get _base => 'https://api.telegram.org/bot$_token';

  // ─── Lifecycle ─────────────────────────────────────────────────────────────

  void start({required String token, String restaurantName = 'ZELLY', String? allowedChatId}) {
    if (token.isEmpty) return;
    _token = token;
    _restaurantName = restaurantName;
    _allowedChatIds = allowedChatId != null && allowedChatId.isNotEmpty
        ? allowedChatId
            .split(',')
            .map((s) => int.tryParse(s.trim()))
            .whereType<int>()
            .toSet()
        : {};
    if (_isRunning && (_pollingTimer?.isActive ?? false)) return;
    _pollingTimer?.cancel();
    _isRunning = true;
    _schedulePoll();
    debugPrint('TelegramBot: polling started, allowedChatIds=$_allowedChatIds');
  }

  void stop() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    _isRunning = false;
    debugPrint('TelegramBot: stopped');
  }

  void _schedulePoll() {
    if (!_isRunning) return;
    _pollingTimer = Timer(const Duration(seconds: 3), () async {
      await _poll();
      _schedulePoll();
    });
  }

  void updateRestaurantName(String name) => _restaurantName = name;

  // ─── Polling ───────────────────────────────────────────────────────────────

  Future<void> _poll() async {
    if (_token == null || _token!.isEmpty) return;
    try {
      final uri = Uri.parse(
        '$_base/getUpdates?offset=${_lastUpdateId + 1}&timeout=1'
        '&allowed_updates=%5B%22message%22%2C%22callback_query%22%5D',
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) return;

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (data['ok'] != true) return;

      final updates = (data['result'] as List).cast<Map<String, dynamic>>();
      for (final update in updates) {
        final id = update['update_id'] as int;
        if (id > _lastUpdateId) {
          _lastUpdateId = id;
          await _processUpdate(update);
        }
      }
    } catch (_) {}
  }

  Future<void> _processUpdate(Map<String, dynamic> update) async {
    try {
      if (update.containsKey('message')) {
        await _handleMessage(update['message'] as Map<String, dynamic>);
      } else if (update.containsKey('callback_query')) {
        await _handleCallback(
          update['callback_query'] as Map<String, dynamic>,
        );
      }
    } catch (e) {
      debugPrint('TelegramBot processUpdate error: $e');
    }
  }

  // ─── Message Handler ───────────────────────────────────────────────────────

  // Kiruvchi chatId ga ruxsat bor-yo'qligini tekshiradi
  bool _isAuthorized(int chatId) {
    if (_allowedChatIds.isEmpty) return true; // ID sozlanmagan — hamma ruxsatli
    return _allowedChatIds.contains(chatId);
  }

  Future<void> _handleMessage(Map<String, dynamic> msg) async {
    final chatId = msg['chat']['id'] as int;
    final text = (msg['text'] as String? ?? '').trim();

    if (!_isAuthorized(chatId)) {
      debugPrint('TelegramBot: unauthorized chatId=$chatId');
      return;
    }

    // Persist chatId so proactive notifications reach this user
    await _saveKnownChat(chatId);

    if (text.startsWith('/start') || text.startsWith('/menu')) {
      await _sendMainMenu(chatId);
    } else if (text == '/hisobot') {
      await _sendGeneralReport(chatId);
    } else {
      await _sendMainMenu(chatId);
    }
  }

  // ─── Known chats persistence ───────────────────────────────────────────────

  Future<void> _saveKnownChat(int chatId) async {
    try {
      final db = await DatabaseHelper.instance.database;
      final rows = await db.query('settings', where: 'key = ?', whereArgs: ['telegram_notify_chats']);
      final existing = rows.isNotEmpty ? (rows.first['value'] as String? ?? '') : '';
      final ids = existing.isEmpty ? <String>[] : existing.split(',');
      final idStr = chatId.toString();
      if (!ids.contains(idStr)) {
        ids.add(idStr);
        await db.rawInsert(
          'INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)',
          ['telegram_notify_chats', ids.join(',')],
        );
      }
    } catch (_) {}
  }

  Future<List<int>> _getKnownChats() async {
    try {
      final db = await DatabaseHelper.instance.database;
      final rows = await db.query('settings', where: 'key = ?', whereArgs: ['telegram_notify_chats']);
      if (rows.isEmpty) return [];
      final val = rows.first['value'] as String? ?? '';
      return val.split(',').where((s) => s.isNotEmpty).map(int.parse).toList();
    } catch (_) {
      return [];
    }
  }

  // ─── Proactive notifications ───────────────────────────────────────────────

  Future<void> notifyNewDelivery({
    required String customerName,
    required String phone,
    required String address,
    required double total,
    required double deliveryFee,
    required int dailyNumber,
    required String itemsSummary,
    String? note,
  }) async {
    if (_token == null || _token!.isEmpty) return;
    final chats = await _getKnownChats();
    if (chats.isEmpty) return;

    final sb = StringBuffer();
    sb.writeln('🚀 <b>Yangi yetkazib berish buyurtmasi!</b>');
    sb.writeln('📋 Buyurtma #$dailyNumber');
    sb.writeln('');
    sb.writeln('👤 <b>$customerName</b>');
    if (phone.isNotEmpty) sb.writeln('📞 $phone');
    sb.writeln('📍 $address');
    if (note != null && note.isNotEmpty) sb.writeln('📝 $note');
    sb.writeln('');
    sb.writeln('🍽 $itemsSummary');
    sb.writeln('');
    if (deliveryFee > 0) {
      sb.writeln('🚗 Yetkazish: ${PriceFormatter.format(deliveryFee)}');
    }
    sb.writeln('💰 Jami: <b>${PriceFormatter.format(total)}</b>');

    final text = sb.toString();
    for (final chatId in chats) {
      await _sendMsg(chatId, text);
    }
  }

  // ─── Callback Handler ──────────────────────────────────────────────────────

  Future<void> _handleCallback(Map<String, dynamic> cb) async {
    final chatId = cb['message']['chat']['id'] as int;
    final msgId = cb['message']['message_id'] as int;
    final data = cb['data'] as String;
    final cbId = cb['id'] as String;

    if (!_isAuthorized(chatId)) {
      debugPrint('TelegramBot: unauthorized callback chatId=$chatId');
      await _answerCallback(cbId);
      return;
    }

    await _answerCallback(cbId);

    switch (data) {
      case 'menu':
        await _editMainMenu(chatId, msgId);
      case 'orders':
        await _editOrdersMenu(chatId, msgId);
      case 'orders_today':
        await _editOrders(chatId, msgId, 'today');
      case 'orders_week':
        await _editOrders(chatId, msgId, 'week');
      case 'orders_month':
        await _editOrders(chatId, msgId, 'month');
      case 'products':
        await _editProducts(chatId, msgId);
      case 'waiters':
        await _editWaiters(chatId, msgId);
      case 'tables':
        await _editTables(chatId, msgId);
      case 'locations':
        await _editLocations(chatId, msgId);
      case 'general':
      case 'refresh_general':
        await _editGeneralReport(chatId, msgId);
    }
  }

  // ─── Main Menu ─────────────────────────────────────────────────────────────

  Future<void> _sendMainMenu(int chatId) async {
    final now = DateTime.now();
    final text =
        '🏪 <b>$_restaurantName — ZELLY POS</b>\n'
        '📅 ${_fmtDate(now)}  🕐 ${_fmtTime(now)}\n\n'
        'Quyidagi bo\'limlardan birini tanlang:';
    await _sendMsg(chatId, text, kb: _mainKb());
  }

  Future<void> _editMainMenu(int chatId, int msgId) async {
    final now = DateTime.now();
    final text =
        '🏪 <b>$_restaurantName — ZELLY POS</b>\n'
        '📅 ${_fmtDate(now)}  🕐 ${_fmtTime(now)}\n\n'
        'Quyidagi bo\'limlardan birini tanlang:';
    await _editMsg(chatId, msgId, text, kb: _mainKb());
  }

  List<List<Map<String, dynamic>>> _mainKb() {
    // Barqaror domen ustunroq: Cloudflare URL'i har qayta ishga tushishda
    // o'zgaradi va eski xabarlardagi tugmalar o'lik bo'lib qoladi.
    final reportsUrl = RelayService.instance.reportsUrl ??
        (TunnelService.instance.tunnelUrl == null
            ? null
            : '${TunnelService.instance.tunnelUrl}/reports/view');
    return [
      if (reportsUrl != null)
        [
          {
            'text': '📊 Hisobot Paneli',
            'web_app': {'url': reportsUrl},
          }
        ],
      [
        {'text': '📋 Buyurtmalar', 'callback_data': 'orders'},
        {'text': '🍽 Taomlar', 'callback_data': 'products'},
      ],
      [
        {'text': '👨‍🍳 Ofisantlar', 'callback_data': 'waiters'},
        {'text': '🪑 Stollar', 'callback_data': 'tables'},
      ],
      [
        {'text': '📍 Joylar', 'callback_data': 'locations'},
        {'text': '📈 Umumiy Hisobot', 'callback_data': 'general'},
      ],
    ];
  }

  // ─── Buyurtmalar ───────────────────────────────────────────────────────────

  Future<void> _editOrdersMenu(int chatId, int msgId) async {
    await _editMsg(
      chatId,
      msgId,
      '📋 <b>BUYURTMALAR</b>\n\nQaysi davr uchun ko\'rmoqchisiz?',
      kb: [
        [
          {'text': '📅 Bugun', 'callback_data': 'orders_today'},
          {'text': '📆 Hafta', 'callback_data': 'orders_week'},
          {'text': '🗓 Oy', 'callback_data': 'orders_month'},
        ],
        [{'text': '⬅️ Orqaga', 'callback_data': 'menu'}],
      ],
    );
  }

  Future<void> _editOrders(int chatId, int msgId, String period) async {
    final db = await DatabaseHelper.instance.database;
    final dayStart = await DatabaseHelper.instance.getDayStartTime();
    final dayStartStr = dayStart.toIso8601String();

    String where;
    List<dynamic> whereArgs = [];
    String label;
    switch (period) {
      case 'week':
        where = 'o.created_at >= ?';
        whereArgs = [dayStart.subtract(const Duration(days: 7)).toIso8601String()];
        label = 'So\'nggi 7 kun';
      case 'month':
        where = 'o.created_at >= ?';
        whereArgs = [dayStart.subtract(const Duration(days: 30)).toIso8601String()];
        label = 'So\'nggi 30 kun';
      default:
        where = 'o.created_at >= ?';
        whereArgs = [dayStartStr];
        label = 'Bugun';
    }

    final metrics = await db.rawQuery('''
      SELECT
        COUNT(*) as cnt,
        COALESCE(SUM(grand_total),0) as total,
        COALESCE(AVG(grand_total),0) as avg_check,
        COALESCE(SUM(CASE WHEN payment_type IN ('Cash','Naqd') THEN grand_total ELSE 0 END),0) as cash,
        COALESCE(SUM(CASE WHEN payment_type IN ('Card','Karta') THEN grand_total ELSE 0 END),0) as card,
        COALESCE(SUM(CASE WHEN payment_type='Terminal' THEN grand_total ELSE 0 END),0) as terminal,
        COALESCE(SUM(CASE WHEN order_type=0 THEN 1 ELSE 0 END),0) as dine_in,
        COALESCE(SUM(CASE WHEN order_type=1 THEN 1 ELSE 0 END),0) as takeaway
      FROM orders o
      WHERE o.status=1 AND $where
    ''', whereArgs);

    final last = await db.rawQuery('''
      SELECT o.daily_number, o.id, o.grand_total, o.payment_type,
             w.name as wname, t.name as tname, o.created_at
      FROM orders o
      LEFT JOIN waiters w ON o.waiter_id=w.id
      LEFT JOIN tables t ON o.table_id=t.id
      WHERE o.status=1 AND $where
      ORDER BY o.created_at DESC LIMIT 7
    ''', whereArgs);

    final m = metrics.first;
    final cnt = m['cnt'] as int? ?? 0;
    final total = _n(m['total']);
    final avg = _n(m['avg_check']);
    final cash = _n(m['cash']);
    final card = _n(m['card']);
    final terminal = _n(m['terminal']);
    final dineIn = m['dine_in'] as int? ?? 0;
    final takeaway = m['takeaway'] as int? ?? 0;

    final buf = StringBuffer();
    buf.writeln('📋 <b>BUYURTMALAR — $label</b>');
    buf.writeln('━━━━━━━━━━━━━━━━━━━━');
    buf.writeln('✅ Jami buyurtmalar: <b>$cnt ta</b>');
    buf.writeln('💰 Umumiy tushum: <b>${_f(total)} so\'m</b>');
    buf.writeln('📊 O\'rtacha chek: <b>${_f(avg)} so\'m</b>');
    buf.writeln('━━━━━━━━━━━━━━━━━━━━');
    buf.writeln('💵 Naqd: <b>${_f(cash)} so\'m</b>');
    buf.writeln('💳 Karta: <b>${_f(card)} so\'m</b>');
    if (terminal > 0) buf.writeln('🖥 Terminal: <b>${_f(terminal)} so\'m</b>');
    buf.writeln('━━━━━━━━━━━━━━━━━━━━');
    buf.writeln('🍽 Zal: <b>$dineIn ta</b>  |  🥡 Olib ketish: <b>$takeaway ta</b>');

    if (last.isNotEmpty) {
      buf.writeln('━━━━━━━━━━━━━━━━━━━━');
      buf.writeln('🕐 <b>So\'nggi buyurtmalar:</b>');
      for (final o in last) {
        final no = o['daily_number'] ?? o['id'];
        final amt = _n(o['grand_total']);
        final pay = o['payment_type'] as String? ?? '';
        final waiter = o['wname'] as String? ?? '';
        final table = o['tname'] as String? ?? '';
        final time = _timeIso(o['created_at'] as String? ?? '');
        final icon = pay.contains('Cash') || pay.contains('Naqd') ? '💵' : '💳';
        buf.write('  #$no  $icon ${_f(amt)}  👤$waiter');
        if (table.isNotEmpty) buf.write(' 🪑$table');
        buf.writeln('  <i>$time</i>');
      }
    }

    await _editMsg(
      chatId,
      msgId,
      buf.toString(),
      kb: [
        [
          {'text': '📅 Bugun', 'callback_data': 'orders_today'},
          {'text': '📆 Hafta', 'callback_data': 'orders_week'},
          {'text': '🗓 Oy', 'callback_data': 'orders_month'},
        ],
        [{'text': '⬅️ Orqaga', 'callback_data': 'menu'}],
      ],
    );
  }

  // ─── Taomlar ───────────────────────────────────────────────────────────────

  Future<void> _editProducts(int chatId, int msgId) async {
    final db = await DatabaseHelper.instance.database;
    final dayStart = await DatabaseHelper.instance.getDayStartTime();
    final dayStartStr = dayStart.toIso8601String();

    final topSold = await db.rawQuery('''
      SELECT p.name, SUM(oi.qty) as qty, SUM(oi.qty*oi.price) as revenue
      FROM order_items oi
      JOIN products p ON oi.product_id=p.id
      JOIN orders o ON oi.order_id=o.id
      WHERE o.status=1 AND o.created_at >= ?
      GROUP BY p.id ORDER BY qty DESC LIMIT 10
    ''', [dayStartStr]);

    final lowStock = await db.rawQuery('''
      SELECT name, quantity FROM products
      WHERE is_active=1 AND quantity IS NOT NULL AND quantity>0 AND quantity<=5
      ORDER BY quantity ASC LIMIT 10
    ''');

    final totalRes = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM products WHERE is_active=1',
    );

    final buf = StringBuffer();
    buf.writeln('🍽 <b>TAOMLAR — Bugungi statistika</b>');
    buf.writeln('Aktiv taomlar: <b>${totalRes.first['cnt']} ta</b>');
    buf.writeln('━━━━━━━━━━━━━━━━━━━━');

    if (topSold.isNotEmpty) {
      buf.writeln('🏆 <b>Top 10 sotilgan (bugun):</b>');
      for (var i = 0; i < topSold.length; i++) {
        final p = topSold[i];
        final qty = (p['qty'] as num?)?.toInt() ?? 0;
        final rev = _n(p['revenue']);
        final medal =
            i == 0
                ? '🥇'
                : i == 1
                ? '🥈'
                : i == 2
                ? '🥉'
                : '  ${i + 1}.';
        buf.writeln('$medal ${p['name']} — <b>$qty ta</b> | ${_f(rev)} so\'m');
      }
    } else {
      buf.writeln('ℹ️ Bugun hali buyurtma yo\'q');
    }

    if (lowStock.isNotEmpty) {
      buf.writeln('━━━━━━━━━━━━━━━━━━━━');
      buf.writeln('⚠️ <b>Omborda kam qolganlar:</b>');
      for (final p in lowStock) {
        final qty = (p['quantity'] as num?)?.toInt() ?? 0;
        buf.writeln('  🔴 ${p['name']} — <b>$qty ta</b> qoldi');
      }
    }

    await _editMsg(chatId, msgId, buf.toString(), kb: [
      [
        {'text': '🔄 Yangilash', 'callback_data': 'products'},
        {'text': '⬅️ Orqaga', 'callback_data': 'menu'},
      ],
    ]);
  }

  // ─── Ofisantlar ────────────────────────────────────────────────────────────

  Future<void> _editWaiters(int chatId, int msgId) async {
    final db = await DatabaseHelper.instance.database;
    final dayStart = await DatabaseHelper.instance.getDayStartTime();
    final dayStartStr = dayStart.toIso8601String();

    final stats = await db.rawQuery('''
      SELECT
        w.name, w.type, w.value,
        COUNT(o.id) as cnt,
        COALESCE(SUM(o.grand_total),0) as sales,
        COALESCE(SUM(o.service_total),0) as commission
      FROM waiters w
      LEFT JOIN orders o ON o.waiter_id=w.id
        AND o.status=1
        AND o.created_at >= ?
      WHERE w.name != 'Kassa'
      GROUP BY w.id
      ORDER BY sales DESC
    ''', [dayStartStr]);

    final buf = StringBuffer();
    buf.writeln('👨‍🍳 <b>OFISANTLAR — Bugun</b>');
    buf.writeln('━━━━━━━━━━━━━━━━━━━━');

    if (stats.isEmpty) {
      buf.writeln('ℹ️ Ofisantlar topilmadi');
    } else {
      for (final w in stats) {
        final name = w['name'] as String? ?? 'Noma\'lum';
        final cnt = w['cnt'] as int? ?? 0;
        final sales = _n(w['sales']);
        final commission = _n(w['commission']);
        final wType = w['type'] as int? ?? 0;
        final wValue = _n(w['value']);

        buf.writeln('👤 <b>$name</b>');
        buf.writeln('   📋 Buyurtmalar: <b>$cnt ta</b>');
        buf.writeln('   💰 Savdo: <b>${_f(sales)} so\'m</b>');
        if (commission > 0) {
          buf.writeln('   💸 Komissiya: <b>${_f(commission)} so\'m</b>');
        }
        if (wType == 1 && wValue > 0) {
          buf.writeln('   📊 Stavka: $wValue%');
        } else if (wType == 0 && wValue > 0) {
          buf.writeln('   📊 Fiksal: ${_f(wValue)} so\'m');
        }
        buf.writeln();
      }
    }

    await _editMsg(chatId, msgId, buf.toString(), kb: [
      [
        {'text': '🔄 Yangilash', 'callback_data': 'waiters'},
        {'text': '⬅️ Orqaga', 'callback_data': 'menu'},
      ],
    ]);
  }

  // ─── Stollar ───────────────────────────────────────────────────────────────

  Future<void> _editTables(int chatId, int msgId) async {
    final db = await DatabaseHelper.instance.database;
    final dayStart = await DatabaseHelper.instance.getDayStartTime();
    final dayStartStr = dayStart.toIso8601String();

    final tables = await db.rawQuery('''
      SELECT t.name, t.active_order_id,
             l.name as lname,
             o.grand_total, o.opened_at
      FROM tables t
      LEFT JOIN locations l ON t.location_id=l.id
      LEFT JOIN orders o ON t.active_order_id=o.id
      ORDER BY t.location_id, t.name
    ''');

    final stats = await db.rawQuery('''
      SELECT
        COUNT(DISTINCT t.id) as used,
        COUNT(o.id) as orders,
        COALESCE(SUM(o.grand_total),0) as revenue
      FROM orders o
      JOIN tables t ON o.table_id=t.id
      WHERE o.status=1 AND o.created_at >= ?
    ''', [dayStartStr]);

    final active = tables.where((t) => t['active_order_id'] != null).toList();
    final free = tables.where((t) => t['active_order_id'] == null).toList();
    final s = stats.first;

    final buf = StringBuffer();
    buf.writeln('🪑 <b>STOLLAR</b>');
    buf.writeln('━━━━━━━━━━━━━━━━━━━━');
    buf.writeln(
      '🟢 Bo\'sh: <b>${free.length} ta</b>  |  '
      '🔴 Band: <b>${active.length} ta</b>',
    );

    if (active.isNotEmpty) {
      buf.writeln('━━━━━━━━━━━━━━━━━━━━');
      buf.writeln('🔴 <b>Hozir band stollar:</b>');
      for (final t in active) {
        final name = t['name'] as String? ?? '';
        final loc = t['lname'] as String? ?? '';
        final total = _n(t['grand_total']);
        final since = _timeIso(t['opened_at'] as String? ?? '');
        buf.write('  🪑 <b>$name</b>');
        if (loc.isNotEmpty) buf.write(' ($loc)');
        buf.writeln(' — ${_f(total)} so\'m  <i>$since dan</i>');
      }
    }

    buf.writeln('━━━━━━━━━━━━━━━━━━━━');
    buf.writeln('📊 <b>Bugungi natijalar:</b>');
    buf.writeln('  🪑 Ishlatilgan stollar: ${s['used']} ta');
    buf.writeln('  📋 Jami buyurtmalar: ${s['orders']} ta');
    buf.writeln('  💰 Jami tushum: ${_f(_n(s['revenue']))} so\'m');

    await _editMsg(chatId, msgId, buf.toString(), kb: [
      [
        {'text': '🔄 Yangilash', 'callback_data': 'tables'},
        {'text': '⬅️ Orqaga', 'callback_data': 'menu'},
      ],
    ]);
  }

  // ─── Joylar ────────────────────────────────────────────────────────────────

  Future<void> _editLocations(int chatId, int msgId) async {
    final db = await DatabaseHelper.instance.database;
    final dayStart = await DatabaseHelper.instance.getDayStartTime();
    final dayStartStr = dayStart.toIso8601String();

    final today = await db.rawQuery('''
      SELECT
        l.name,
        COUNT(o.id) as cnt,
        COALESCE(SUM(o.grand_total),0) as revenue,
        COUNT(DISTINCT o.table_id) as tables_used
      FROM locations l
      LEFT JOIN orders o ON o.location_id=l.id
        AND o.status=1
        AND o.created_at >= ?
      GROUP BY l.id ORDER BY revenue DESC
    ''', [dayStartStr]);

    final allTime = await db.rawQuery('''
      SELECT l.name,
             COUNT(o.id) as cnt,
             COALESCE(SUM(o.grand_total),0) as revenue
      FROM locations l
      LEFT JOIN orders o ON o.location_id=l.id AND o.status=1
      GROUP BY l.id ORDER BY revenue DESC
    ''');

    final buf = StringBuffer();
    buf.writeln('📍 <b>JOYLAR — Bugungi statistika</b>');
    buf.writeln('━━━━━━━━━━━━━━━━━━━━');

    if (today.isEmpty) {
      buf.writeln('ℹ️ Joylar topilmadi');
    } else {
      for (var i = 0; i < today.length; i++) {
        final loc = today[i];
        buf.writeln('${i + 1}. 📍 <b>${loc['name']}</b>');
        buf.writeln(
          '   📋 ${loc['cnt']} ta  |  🪑 ${loc['tables_used']} stol',
        );
        buf.writeln('   💰 ${_f(_n(loc['revenue']))} so\'m');
        buf.writeln();
      }

      buf.writeln('━━━━━━━━━━━━━━━━━━━━');
      buf.writeln('📊 <b>Barcha vaqt:</b>');
      for (final loc in allTime) {
        buf.writeln(
          '  📍 ${loc['name']} — ${loc['cnt']} ta | '
          '${_f(_n(loc['revenue']))} so\'m',
        );
      }
    }

    await _editMsg(chatId, msgId, buf.toString(), kb: [
      [
        {'text': '🔄 Yangilash', 'callback_data': 'locations'},
        {'text': '⬅️ Orqaga', 'callback_data': 'menu'},
      ],
    ]);
  }

  // ─── Umumiy Hisobot ────────────────────────────────────────────────────────

  Future<void> _editGeneralReport(int chatId, int msgId) async {
    final text = await _buildGeneral();
    await _editMsg(chatId, msgId, text, kb: [
      [
        {'text': '🔄 Yangilash', 'callback_data': 'refresh_general'},
        {'text': '⬅️ Orqaga', 'callback_data': 'menu'},
      ],
    ]);
  }

  Future<void> _sendGeneralReport(int chatId) async {
    final text = await _buildGeneral();
    await _sendMsg(chatId, text, kb: [
      [
        {'text': '🔄 Yangilash', 'callback_data': 'refresh_general'},
        {'text': '⬅️ Asosiy menyu', 'callback_data': 'menu'},
      ],
    ]);
  }

  Future<String> _buildGeneral() async {
    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now();
    final dayStart = await DatabaseHelper.instance.getDayStartTime();
    final dayStartStr = dayStart.toIso8601String();

    final metrics = await db.rawQuery('''
      SELECT
        COUNT(*) as cnt,
        COALESCE(SUM(grand_total),0) as total,
        COALESCE(AVG(grand_total),0) as avg_check,
        COALESCE(SUM(CASE WHEN payment_type IN ('Cash','Naqd') THEN grand_total ELSE 0 END),0) as cash,
        COALESCE(SUM(CASE WHEN payment_type IN ('Card','Karta') THEN grand_total ELSE 0 END),0) as card,
        COALESCE(SUM(CASE WHEN payment_type='Terminal' THEN grand_total ELSE 0 END),0) as terminal,
        COALESCE(SUM(CASE WHEN order_type=0 THEN 1 ELSE 0 END),0) as dine_in,
        COALESCE(SUM(CASE WHEN order_type=1 THEN 1 ELSE 0 END),0) as takeaway
      FROM orders
      WHERE status=1 AND created_at >= ?
    ''', [dayStartStr]);

    final topProducts = await db.rawQuery('''
      SELECT p.name, SUM(oi.qty) as qty, SUM(oi.qty*oi.price) as revenue
      FROM order_items oi
      JOIN products p ON oi.product_id=p.id
      JOIN orders o ON oi.order_id=o.id
      WHERE o.status=1 AND o.created_at >= ?
      GROUP BY p.id ORDER BY revenue DESC LIMIT 5
    ''', [dayStartStr]);

    final waiters = await db.rawQuery('''
      SELECT w.name, COUNT(o.id) as cnt,
             COALESCE(SUM(o.grand_total),0) as sales
      FROM waiters w
      JOIN orders o ON o.waiter_id=w.id
      WHERE o.status=1 AND o.created_at >= ?
        AND w.name!='Kassa'
      GROUP BY w.id ORDER BY sales DESC LIMIT 5
    ''', [dayStartStr]);

    final locations = await db.rawQuery('''
      SELECT l.name, COUNT(o.id) as cnt,
             COALESCE(SUM(o.grand_total),0) as revenue
      FROM locations l
      JOIN orders o ON o.location_id=l.id
      WHERE o.status=1 AND o.created_at >= ?
      GROUP BY l.id ORDER BY revenue DESC
    ''', [dayStartStr]);

    final m = metrics.first;
    final cnt = m['cnt'] as int? ?? 0;
    final total = _n(m['total']);
    final avg = _n(m['avg_check']);
    final cash = _n(m['cash']);
    final card = _n(m['card']);
    final terminal = _n(m['terminal']);
    final dineIn = m['dine_in'] as int? ?? 0;
    final takeaway = m['takeaway'] as int? ?? 0;

    final buf = StringBuffer();
    buf.writeln('📈 <b>UMUMIY HISOBOT — Bugun</b>');
    buf.writeln('🏪 <b>$_restaurantName</b>');
    buf.writeln('📅 ${_fmtDate(now)}  🕐 ${_fmtTime(now)}');
    buf.writeln('━━━━━━━━━━━━━━━━━━━━');
    buf.writeln('✅ Buyurtmalar: <b>$cnt ta</b>');
    buf.writeln('💰 Jami tushum: <b>${_f(total)} so\'m</b>');
    buf.writeln('📊 O\'rtacha chek: <b>${_f(avg)} so\'m</b>');
    buf.writeln('━━━━━━━━━━━━━━━━━━━━');
    buf.writeln('💵 Naqd: <b>${_f(cash)} so\'m</b>');
    buf.writeln('💳 Karta: <b>${_f(card)} so\'m</b>');
    if (terminal > 0) {
      buf.writeln('🖥 Terminal: <b>${_f(terminal)} so\'m</b>');
    }
    buf.writeln('━━━━━━━━━━━━━━━━━━━━');
    buf.writeln(
      '🍽 Zal: <b>$dineIn ta</b>  |  🥡 Olib ketish: <b>$takeaway ta</b>',
    );

    if (topProducts.isNotEmpty) {
      buf.writeln('━━━━━━━━━━━━━━━━━━━━');
      buf.writeln('🏆 <b>Top Taomlar:</b>');
      for (var i = 0; i < topProducts.length; i++) {
        final p = topProducts[i];
        final qty = (p['qty'] as num?)?.toInt() ?? 0;
        final medal =
            i == 0
                ? '🥇'
                : i == 1
                ? '🥈'
                : i == 2
                ? '🥉'
                : '  ${i + 1}.';
        buf.writeln(
          '$medal ${p['name']} — $qty ta | ${_f(_n(p['revenue']))} so\'m',
        );
      }
    }

    if (waiters.isNotEmpty) {
      buf.writeln('━━━━━━━━━━━━━━━━━━━━');
      buf.writeln('👨‍🍳 <b>Ofisantlar:</b>');
      for (final w in waiters) {
        buf.writeln(
          '  👤 ${w['name']} — ${w['cnt']} ta | '
          '${_f(_n(w['sales']))} so\'m',
        );
      }
    }

    if (locations.isNotEmpty) {
      buf.writeln('━━━━━━━━━━━━━━━━━━━━');
      buf.writeln('📍 <b>Joylar:</b>');
      for (final l in locations) {
        buf.writeln(
          '  📍 ${l['name']} — ${l['cnt']} ta | '
          '${_f(_n(l['revenue']))} so\'m',
        );
      }
    }

    return buf.toString();
  }

  // ─── API Helpers ───────────────────────────────────────────────────────────

  Future<void> _answerCallback(String id) async {
    try {
      await http
          .post(
            Uri.parse('$_base/answerCallbackQuery'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'callback_query_id': id}),
          )
          .timeout(const Duration(seconds: 3));
    } catch (_) {}
  }

  Future<void> _sendMsg(
    int chatId,
    String text, {
    List<List<Map<String, dynamic>>>? kb,
  }) async {
    try {
      final body = <String, dynamic>{
        'chat_id': chatId,
        'text': text,
        'parse_mode': 'HTML',
      };
      if (kb != null) body['reply_markup'] = {'inline_keyboard': kb};
      await http
          .post(
            Uri.parse('$_base/sendMessage'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('TelegramBot sendMsg error: $e');
    }
  }

  Future<void> _editMsg(
    int chatId,
    int msgId,
    String text, {
    List<List<Map<String, dynamic>>>? kb,
  }) async {
    try {
      final body = <String, dynamic>{
        'chat_id': chatId,
        'message_id': msgId,
        'text': text,
        'parse_mode': 'HTML',
      };
      if (kb != null) body['reply_markup'] = {'inline_keyboard': kb};
      await http
          .post(
            Uri.parse('$_base/editMessageText'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('TelegramBot editMsg error: $e');
    }
  }

  // ─── Utils ─────────────────────────────────────────────────────────────────

  double _n(dynamic v) => (v as num?)?.toDouble() ?? 0.0;
  String _f(double v) => PriceFormatter.format(v);
  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  String _fmtTime(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  String _timeIso(String iso) {
    try {
      return _fmtTime(DateTime.parse(iso).toLocal());
    } catch (_) {
      return '';
    }
  }
}
