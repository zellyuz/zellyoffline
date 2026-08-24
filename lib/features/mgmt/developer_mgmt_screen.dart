import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/services/relay_service.dart';
import '../../providers/developer_provider.dart';
import '../../data/repositories/developer_repository.dart';
import '../settings/telegram_settings_screen.dart';

class DeveloperMgmtScreen extends StatefulWidget {
  const DeveloperMgmtScreen({super.key});

  @override
  State<DeveloperMgmtScreen> createState() => _DeveloperMgmtScreenState();
}

class _DeveloperMgmtScreenState extends State<DeveloperMgmtScreen> {
  String? _dbPath;
  String? _dbSize;
  Map<String, int> _rowCounts = {};
  bool _loadingCounts = false;
  final _sqlController = TextEditingController();
  String? _sqlResult;
  bool _sqlLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final dev = context.read<DeveloperProvider>();
      await dev.loadTables();
      await _loadMeta();
      await _loadRowCounts(dev.tables);
    });
  }

  @override
  void dispose() {
    _sqlController.dispose();
    super.dispose();
  }

  Future<void> _loadMeta() async {
    final path = await DeveloperRepository().getDatabasePath();
    final file = File(path);
    final size = file.existsSync()
        ? _formatSize(await file.length())
        : '—';
    if (mounted) setState(() { _dbPath = path; _dbSize = size; });
  }

  Future<void> _loadRowCounts(List<String> tables) async {
    setState(() => _loadingCounts = true);
    final repo = DeveloperRepository();
    final counts = <String, int>{};
    for (final t in tables) {
      counts[t] = await repo.getRowCount(t);
    }
    if (mounted) setState(() { _rowCounts = counts; _loadingCounts = false; });
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  Future<void> _refresh() async {
    final dev = context.read<DeveloperProvider>();
    await dev.loadTables();
    await _loadMeta();
    await _loadRowCounts(dev.tables);
  }

  @override
  Widget build(BuildContext context) {
    final dev = context.watch<DeveloperProvider>();
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Row(children: [
          Icon(Icons.terminal_rounded, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          const Text('Developer Tools',
              style: TextStyle(fontWeight: FontWeight.bold)),
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Yangilash',
            onPressed: _refresh,
          ),
        ],
      ),
      body: dev.isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTelegramCard(context, theme),
                  const SizedBox(height: 20),
                  _buildRelayCard(theme),
                  const SizedBox(height: 20),
                  _buildDbInfoCard(theme),
                  const SizedBox(height: 20),
                  _buildActionsRow(context, theme),
                  const SizedBox(height: 20),
                  _buildSqlCard(context, theme),
                  const SizedBox(height: 20),
                  _buildTablesSection(context, dev, theme),
                ],
              ),
            ),
    );
  }

  // ─── Telegram sync ───────────────────────────────────────────────────────
  Widget _buildTelegramCard(BuildContext context, ThemeData t) {
    return _ActionCard(
      icon: Icons.send_rounded,
      label: 'Telegram bot sinxronizatsiyasi',
      subtitle: 'Bot token va foydalanuvchi ID\'lari',
      color: const Color(0xFF0EA5E9),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const TelegramSettingsScreen()),
      ),
    );
  }

  // ─── Tashqi domen (relay) ────────────────────────────────────────────────
  //
  // Cloudflare tunneli har ishga tushishda YANGI manzil beradi — Telegram'dagi
  // eski "Hisobot Paneli" tugmalari o'lik bo'lib qoladi. Bu yerda kiritilgan
  // domen esa o'zgarmaydi: https://<domen>/reports/view
  Widget _buildRelayCard(ThemeData t) {
    final relay = RelayService.instance;

    return ListenableBuilder(
      listenable: relay,
      builder: (context, _) {
        final (color, icon, text) = switch (relay.status) {
          RelayStatus.connected =>
            (const Color(0xFF16A34A), Icons.cloud_done_rounded, 'Ulangan'),
          RelayStatus.starting =>
            (const Color(0xFFF59E0B), Icons.cloud_sync_rounded, 'Ulanmoqda…'),
          RelayStatus.error => (
              const Color(0xFFDC2626),
              Icons.cloud_off_rounded,
              relay.lastError ?? 'Xato'
            ),
          RelayStatus.noExe => (
              const Color(0xFFDC2626),
              Icons.error_outline_rounded,
              'frpc.exe topilmadi'
            ),
          RelayStatus.notConfigured => (
              const Color(0xFFF59E0B),
              Icons.settings_rounded,
              relay.lastError ?? 'Sozlanmagan'
            ),
          RelayStatus.idle =>
            (t.disabledColor, Icons.cloud_outlined, 'O\'chirilgan'),
        };

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(icon, size: 20, color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Tashqi domen (relay)',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      Text(text,
                          style: TextStyle(fontSize: 12, color: color)),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: _openRelayDialog,
                  icon: const Icon(Icons.edit_rounded, size: 16),
                  label: const Text('Sozlash'),
                ),
              ]),
              if (relay.publicUrl != null) ...[
                const SizedBox(height: 10),
                InkWell(
                  onTap: () {
                    Clipboard.setData(
                        ClipboardData(text: relay.reportsUrl ?? ''));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Havola nusxa olindi')),
                    );
                  },
                  child: Row(children: [
                    const Icon(Icons.link_rounded, size: 15),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        relay.reportsUrl ?? '',
                        style: const TextStyle(
                            fontSize: 12, fontFamily: 'monospace'),
                      ),
                    ),
                    const Icon(Icons.copy_rounded, size: 14),
                  ]),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _openRelayDialog() async {
    final relay = RelayService.instance;
    final cfg = await relay.loadConfig();
    if (!mounted) return;

    final domainCtrl =
        TextEditingController(text: cfg[RelayService.kDomain]);
    final serverCtrl =
        TextEditingController(text: cfg[RelayService.kServer]);
    final tokenCtrl = TextEditingController(text: cfg[RelayService.kToken]);
    var enabled = cfg[RelayService.kEnabled] == '1';

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Tashqi domen (relay)'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Bu domen orqali hisobot paneli va mobil ilova '
                    'internetdan ochiladi. Manzil o\'zgarmaydi — '
                    'Telegram tugmalari doim ishlaydi.',
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: domainCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Domen',
                      hintText: 'mehmon.zelly.uz',
                      helperText: 'Har kassada BOSHQA bo\'lishi shart',
                      prefixText: 'https://',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: serverCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Relay server',
                      hintText: '5.104.108.235:7000',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: tokenCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Token',
                      helperText: 'Serverdagi /etc/frp/token',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Yoqilgan'),
                    subtitle: const Text(
                      'O\'chirilsa Cloudflare tunneli ishlatiladi',
                      style: TextStyle(fontSize: 11),
                    ),
                    value: enabled,
                    onChanged: (v) => setLocal(() => enabled = v),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Bekor qilish'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Saqlash va ulash'),
            ),
          ],
        ),
      ),
    );

    if (saved != true) return;

    await relay.saveConfig(
      domain: domainCtrl.text,
      server: serverCtrl.text,
      token: tokenCtrl.text,
      enabled: enabled,
    );
    await relay.restart();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(relay.isConnected
            ? 'Ulandi: ${relay.publicUrl}'
            : 'Saqlandi — ulanish holati kartada ko\'rinadi'),
      ),
    );
  }

  // ─── DB info card ────────────────────────────────────────────────────────
  Widget _buildDbInfoCard(ThemeData t) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.colorScheme.primaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.colorScheme.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.storage_rounded, size: 16, color: t.colorScheme.primary),
            const SizedBox(width: 8),
            Text('Ma\'lumotlar bazasi',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: t.colorScheme.primary,
                    fontSize: 13)),
          ]),
          const SizedBox(height: 10),
          _infoRow('Hajmi', _dbSize ?? '...'),
          const SizedBox(height: 4),
          _infoRow('Jadvallar soni',
              '${context.read<DeveloperProvider>().tables.length} ta'),
          const SizedBox(height: 6),
          if (_dbPath != null)
            Row(children: [
              Expanded(
                child: Text(_dbPath!,
                    style: TextStyle(
                        fontSize: 11,
                        color: t.colorScheme.onSurface.withValues(alpha: 0.5)),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              ),
              IconButton(
                icon: const Icon(Icons.copy_rounded, size: 14),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: 'Nusxa olish',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _dbPath!));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Yo\'l nusxa olindi'),
                      duration: Duration(seconds: 1)));
                },
              ),
            ]),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    final t = Theme.of(context);
    return Row(children: [
      Text('$label: ',
          style: TextStyle(
              fontSize: 13,
              color: t.colorScheme.onSurface.withValues(alpha: 0.6))),
      Text(value,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
    ]);
  }

  // ─── Backup / Restore ────────────────────────────────────────────────────
  Widget _buildActionsRow(BuildContext context, ThemeData t) {
    return Row(children: [
      Expanded(
        child: _ActionCard(
          icon: Icons.backup_rounded,
          label: 'Zaxira olish',
          subtitle: 'DB faylni saqlash',
          color: const Color(0xFF3B82F6),
          onTap: _backupDatabase,
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: _ActionCard(
          icon: Icons.restore_rounded,
          label: 'Tiklash',
          subtitle: 'Zaxiradan yuklash',
          color: const Color(0xFFF59E0B),
          onTap: _restoreDatabase,
        ),
      ),
    ]);
  }

  // ─── Raw SQL ─────────────────────────────────────────────────────────────
  Widget _buildSqlCard(BuildContext context, ThemeData t) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.colorScheme.outline.withValues(alpha: 0.15)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.code_rounded, size: 16, color: t.colorScheme.secondary),
          const SizedBox(width: 8),
          Text('SQL Konsol',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: t.colorScheme.secondary,
                  fontSize: 13)),
        ]),
        const SizedBox(height: 10),
        TextField(
          controller: _sqlController,
          maxLines: 3,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          decoration: InputDecoration(
            hintText: 'SELECT * FROM orders LIMIT 10',
            hintStyle: TextStyle(
                fontFamily: 'monospace',
                color: t.colorScheme.onSurface.withValues(alpha: 0.3)),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            isDense: true,
          ),
        ),
        const SizedBox(height: 8),
        Row(children: [
          const Spacer(),
          TextButton.icon(
            onPressed: _sqlLoading ? null : () => _runSql(context),
            icon: _sqlLoading
                ? const SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.play_arrow_rounded, size: 18),
            label: const Text('Bajarish'),
          ),
        ]),
        if (_sqlResult != null) ...[
          const Divider(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: t.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              _sqlResult!,
              style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: _sqlResult!.startsWith('Xato')
                      ? t.colorScheme.error
                      : t.colorScheme.onSurface),
            ),
          ),
        ],
      ]),
    );
  }

  Future<void> _runSql(BuildContext context) async {
    final query = _sqlController.text.trim();
    if (query.isEmpty) return;
    setState(() { _sqlLoading = true; _sqlResult = null; });
    try {
      final repo = DeveloperRepository();
      final upper = query.toUpperCase().trimLeft();
      if (upper.startsWith('SELECT') || upper.startsWith('PRAGMA')) {
        final rows = await repo.runRawQuery(query);
        setState(() {
          _sqlResult = rows.isEmpty
              ? '(Natija yo\'q)'
              : rows.map((r) => r.toString()).join('\n');
        });
      } else {
        await repo.executeRawQuery(query);
        setState(() { _sqlResult = 'Muvaffaqiyatli bajarildi.'; });
        await _refresh();
      }
    } catch (e) {
      setState(() { _sqlResult = 'Xato: $e'; });
    } finally {
      setState(() => _sqlLoading = false);
    }
  }

  // ─── Tables list ─────────────────────────────────────────────────────────
  Widget _buildTablesSection(
      BuildContext context, DeveloperProvider dev, ThemeData t) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(children: [
          Icon(Icons.table_chart_rounded, size: 16, color: t.colorScheme.primary),
          const SizedBox(width: 8),
          Text('Jadvallar (${dev.tables.length})',
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 15)),
        ]),
      ),
      ...dev.tables.map((name) {
        final count = _rowCounts[name];
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: t.colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: t.colorScheme.outline.withValues(alpha: 0.12)),
          ),
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            leading: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: t.colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.table_rows_rounded,
                  size: 18, color: t.colorScheme.primary),
            ),
            title: Text(name,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 14)),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              if (_loadingCounts)
                const SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2))
              else if (count != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: count == 0
                        ? t.colorScheme.outline.withValues(alpha: 0.1)
                        : t.colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('$count qator',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: count == 0
                              ? t.colorScheme.onSurface.withValues(alpha: 0.4)
                              : t.colorScheme.primary)),
                ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded,
                  color: t.colorScheme.outline, size: 20),
            ]),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => TableDetailScreen(tableName: name),
                ),
              );
              await _loadRowCounts(dev.tables);
            },
          ),
        );
      }),
    ]);
  }

  // ─── Backup / Restore ────────────────────────────────────────────────────
  Future<void> _backupDatabase() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final dbPath = await DeveloperRepository().getDatabasePath();
      final dbFile = File(dbPath);
      if (!dbFile.existsSync()) throw Exception('Baza fayli topilmadi!');

      final now = DateTime.now();
      final stamp =
          '${now.year}${_pad(now.month)}${_pad(now.day)}_${_pad(now.hour)}${_pad(now.minute)}';
      final out = await FilePicker.platform.saveFile(
        dialogTitle: 'Zaxira faylni saqlang',
        fileName: 'tezzro_backup_$stamp.db',
      );
      if (out != null) {
        await dbFile.copy(out);
        if (!mounted) return;
        messenger.showSnackBar(const SnackBar(
            content: Text('Zaxira muvaffaqiyatli saqlandi!'),
            backgroundColor: Colors.green));
      }
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
          content: Text('Xatolik: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _restoreDatabase() async {
    final messenger = ScaffoldMessenger.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Tiklash'),
        content: const Text(
            'Barcha mavjud ma\'lumotlar o\'chib ketadi. Davom etasizmi?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Bekor qilish')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Tiklash',
                  style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.any);
      if (result?.files.single.path == null) return;

      final pickedFile = File(result!.files.single.path!);
      final devRepo = DeveloperRepository();
      final dbPath = await devRepo.getDatabasePath();
      await devRepo.close();
      await pickedFile.copy(dbPath);

      if (!mounted) return;
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: const Text('Muvaffaqiyatli'),
          content: const Text(
              'Ma\'lumotlar tiklandi. Ilovani qayta ishga tushiring.'),
          actions: [
            TextButton(
                onPressed: () => exit(0),
                child: const Text('Ilovadan chiqish')),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
          content: Text('Xatolik: $e'), backgroundColor: Colors.red));
    }
  }

  String _pad(int n) => n.toString().padLeft(2, '0');
}

// ─── Action card widget ───────────────────────────────────────────────────────
class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: color)),
                Text(subtitle,
                    style: TextStyle(
                        fontSize: 11,
                        color: color.withValues(alpha: 0.7))),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

// ─── Table detail screen ──────────────────────────────────────────────────────
class TableDetailScreen extends StatefulWidget {
  final String tableName;
  const TableDetailScreen({super.key, required this.tableName});

  @override
  State<TableDetailScreen> createState() => _TableDetailScreenState();
}

class _TableDetailScreenState extends State<TableDetailScreen> {
  List<Map<String, dynamic>> _data = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _loading = true;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
    _searchCtrl.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final data = await context.read<DeveloperProvider>().getTableData(
          widget.tableName,
        );
    if (mounted) {
      setState(() {
        _data = data;
        _filtered = data;
        _loading = false;
      });
    }
  }

  void _applyFilter() {
    final q = _searchCtrl.text.toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? _data
          : _data.where((row) =>
              row.values.any((v) => v.toString().toLowerCase().contains(q))).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.tableName,
              style: const TextStyle(fontWeight: FontWeight.bold)),
          Text('${_filtered.length} / ${_data.length} qator',
              style: TextStyle(
                  fontSize: 11,
                  color: t.colorScheme.onSurface.withValues(alpha: 0.5))),
        ]),
        actions: [
          IconButton(
              icon: const Icon(Icons.add_rounded),
              tooltip: 'Yangi qator',
              onPressed: _loading || _data.isEmpty ? null : _addRow),
          IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Yangilash',
              onPressed: _loadData),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              // Search bar
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Qidirish...',
                    prefixIcon:
                        const Icon(Icons.search_rounded, size: 20),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            onPressed: () => _searchCtrl.clear(),
                          )
                        : null,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    isDense: true,
                  ),
                ),
              ),
              Expanded(
                child: _filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.inbox_rounded,
                                size: 48,
                                color: t.colorScheme.outline
                                    .withValues(alpha: 0.4)),
                            const SizedBox(height: 12),
                            Text('Ma\'lumot topilmadi',
                                style: TextStyle(
                                    color: t.colorScheme.outline)),
                          ],
                        ),
                      )
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SingleChildScrollView(
                          child: DataTable(
                            headingRowColor: WidgetStatePropertyAll(
                                t.colorScheme.surfaceContainerHighest),
                            border: TableBorder.symmetric(
                              inside: BorderSide(
                                  color: t.colorScheme.outline
                                      .withValues(alpha: 0.1)),
                            ),
                            columnSpacing: 16,
                            dataRowMinHeight: 44,
                            dataRowMaxHeight: 44,
                            columns: [
                              ..._filtered.first.keys.map((k) => DataColumn(
                                    label: Text(k,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12)),
                                  )),
                              const DataColumn(
                                  label: Text('',
                                      style: TextStyle(fontSize: 12))),
                            ],
                            rows: _filtered.map((row) {
                              return DataRow(cells: [
                                ...row.entries.map((e) => DataCell(
                                      ConstrainedBox(
                                        constraints: const BoxConstraints(
                                            maxWidth: 200),
                                        child: Text(
                                          e.value?.toString() ?? 'null',
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: e.value == null
                                                ? t.colorScheme.outline
                                                : null,
                                            fontStyle: e.value == null
                                                ? FontStyle.italic
                                                : null,
                                          ),
                                        ),
                                      ),
                                    )),
                                DataCell(Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: Icon(Icons.edit_rounded,
                                          size: 16,
                                          color: t.colorScheme.primary),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(
                                          minWidth: 32, minHeight: 32),
                                      onPressed: () => _editRow(row),
                                    ),
                                    IconButton(
                                      icon: Icon(Icons.delete_rounded,
                                          size: 16,
                                          color: t.colorScheme.error),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(
                                          minWidth: 32, minHeight: 32),
                                      onPressed: () => _deleteRow(row),
                                    ),
                                  ],
                                )),
                              ]);
                            }).toList(),
                          ),
                        ),
                      ),
              ),
            ]),
    );
  }

  Future<void> _deleteRow(Map<String, dynamic> row) async {
    final idCol = row.containsKey('id') ? 'id' : row.keys.first;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('O\'chirish'),
        content: Text('$idCol = ${row[idCol]} qatorini o\'chirish?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Bekor qilish')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('O\'chirish',
                  style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm == true) {
      if (!mounted) return;
      final dev = context.read<DeveloperProvider>();
      final ok = await dev.deleteRow(widget.tableName, idCol, row[idCol]);
      if (ok) _loadData();
    }
  }

  Future<void> _editRow(Map<String, dynamic> row) async {
    final idCol = row.containsKey('id') ? 'id' : row.keys.first;
    final edited = Map<String, dynamic>.from(row);
    final dev = context.read<DeveloperProvider>();

    await showDialog(
      context: context,
      builder: (ctx) => _RowFormDialog(
        title: 'Tahrirlash  •  $idCol = ${row[idCol]}',
        data: edited,
        idColumn: idCol,
        onSave: () async {
          final ok = await dev.updateRow(
              widget.tableName, idCol, row[idCol], edited);
          if (ok && ctx.mounted) {
            Navigator.pop(ctx);
            _loadData();
          }
        },
      ),
    );
  }

  Future<void> _addRow() async {
    final newData = <String, dynamic>{
      for (final k in _data.first.keys)
        if (k != 'id') k: ''
    };
    final dev = context.read<DeveloperProvider>();

    await showDialog(
      context: context,
      builder: (ctx) => _RowFormDialog(
        title: 'Yangi qator  •  ${widget.tableName}',
        data: newData,
        onSave: () async {
          final ok = await dev.addRow(widget.tableName, newData);
          if (ok && ctx.mounted) {
            Navigator.pop(ctx);
            _loadData();
          }
        },
      ),
    );
  }
}

// ─── Row form dialog ──────────────────────────────────────────────────────────
class _RowFormDialog extends StatefulWidget {
  final String title;
  final Map<String, dynamic> data;
  final String? idColumn;
  final VoidCallback onSave;

  const _RowFormDialog({
    required this.title,
    required this.data,
    this.idColumn,
    required this.onSave,
  });

  @override
  State<_RowFormDialog> createState() => _RowFormDialogState();
}

class _RowFormDialogState extends State<_RowFormDialog> {
  late final Map<String, TextEditingController> _ctrls;

  @override
  void initState() {
    super.initState();
    _ctrls = {
      for (final e in widget.data.entries)
        if (e.key != widget.idColumn)
          e.key: TextEditingController(text: e.value?.toString() ?? '')
    };
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) { c.dispose(); }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: _ctrls.entries.map((e) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TextField(
                  controller: e.value,
                  decoration: InputDecoration(
                    labelText: e.key,
                    border: const OutlineInputBorder(),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                  onChanged: (v) {
                    final num = double.tryParse(v);
                    widget.data[e.key] = num ?? v;
                  },
                ),
              );
            }).toList(),
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Bekor qilish')),
        FilledButton(
            onPressed: widget.onSave, child: const Text('Saqlash')),
      ],
    );
  }
}
