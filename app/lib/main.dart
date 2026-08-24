import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'core/app_settings.dart';
import 'core/strings.dart';
import 'theme/app_theme.dart';
import 'screens/dashboard_screen.dart';
import 'screens/history_screen.dart';
import 'screens/inspection_form_screen.dart';
import 'screens/production_screen.dart';
import 'screens/settings_screen.dart';
import 'services/api_client.dart';
import 'services/master_cache.dart';
import 'services/photo_service.dart';
import 'services/sync_queue.dart';
import 'widgets/ui_kit.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Hive: Android는 앱 문서 디렉터리, 웹(PWA)은 IndexedDB 백엔드
  await Hive.initFlutter();
  await Hive.openBox(AppSettings.boxName);
  await Hive.openBox(MasterCache.boxName);
  await Hive.openBox(SyncQueue.recordBoxName);
  await Hive.openBox(SyncQueue.photoBoxName);

  runApp(const TriApp());
}

class TriApp extends StatefulWidget {
  const TriApp({super.key});

  @override
  State<TriApp> createState() => _TriAppState();
}

class _TriAppState extends State<TriApp> {
  late final ApiClient _api;
  late final MasterCache _masters;
  late final SyncQueue _queue;
  late final PhotoService _photoService;
  late Locale _locale;
  late ThemeMode _themeMode;

  static ThemeMode _parseThemeMode(String v) => switch (v) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  @override
  void initState() {
    super.initState();
    _api = ApiClient();
    _masters = MasterCache();
    _queue = SyncQueue(_api)..start();
    _photoService = PhotoService();
    _locale = Locale(AppSettings.locale);
    _themeMode = _parseThemeMode(AppSettings.themeMode);

    // 시작 시 마스터 갱신 시도 — 실패해도 Hive 캐시로 동작 (오프라인 콜드스타트 방어)
    _masters.refresh(_api).catchError((_) => _masters.cached);
  }

  @override
  void dispose() {
    _queue.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TRI Product Management',
      debugShowCheckedModeBanner: false,
      locale: _locale,
      supportedLocales: S.supported,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: _themeMode,
      home: HomeShell(
        api: _api,
        masters: _masters,
        queue: _queue,
        photoService: _photoService,
        onLocaleChanged: (code) => setState(() => _locale = Locale(code)),
        onThemeChanged: (mode) => setState(() {
          AppSettings.themeMode = mode;
          _themeMode = _parseThemeMode(mode);
        }),
      ),
    );
  }
}

class HomeShell extends StatefulWidget {
  final ApiClient api;
  final MasterCache masters;
  final SyncQueue queue;
  final PhotoService photoService;
  final void Function(String locale) onLocaleChanged;
  final void Function(String themeMode) onThemeChanged;

  const HomeShell({
    super.key,
    required this.api,
    required this.masters,
    required this.queue,
    required this.photoService,
    required this.onLocaleChanged,
    required this.onThemeChanged,
  });

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  final _prodKey = GlobalKey<ProductionScreenState>();
  final _inspKey = GlobalKey<InspectionFormScreenState>();
  final _dashKey = GlobalKey<DashboardScreenState>();

  @override
  void initState() {
    super.initState();
    widget.queue.addListener(_onQueue);
  }

  void _onQueue() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.queue.removeListener(_onQueue);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pendingTotal =
        widget.queue.pendingRecords + widget.queue.pendingPhotos;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: BorderRadius.circular(AppRadius.button),
              ),
              child: const Icon(Icons.verified_outlined,
                  color: Colors.white, size: 18),
            ),
            const SizedBox(width: AppSpacing.sm + 2),
            Text(S.t(context, 'appTitle')),
          ],
        ),
        actions: [
          _SyncIndicator(
            warning: widget.queue.warning,
            pending: pendingTotal,
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: IndexedStack(
        index: _index,
        children: [
          DashboardScreen(key: _dashKey, api: widget.api, queue: widget.queue),
          ProductionScreen(key: _prodKey, api: widget.api, masters: widget.masters),
          InspectionFormScreen(
            key: _inspKey,
            api: widget.api,
            queue: widget.queue,
            masters: widget.masters,
            photoService: widget.photoService,
          ),
          HistoryScreen(api: widget.api, masters: widget.masters),
          SettingsScreen(
            api: widget.api,
            masters: widget.masters,
            queue: widget.queue,
            onLocaleChanged: widget.onLocaleChanged,
            onThemeChanged: widget.onThemeChanged,
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) {
          setState(() => _index = i);
          // 각 탭은 열 때마다 서버 최신 상태로 갱신 (앱 시작 시점 조회 오류 방지)
          if (i == 0) _dashKey.currentState?.refresh();
          if (i == 1) _prodKey.currentState?.refresh();
          if (i == 2) _inspKey.currentState?.refreshLots();
        },
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.bar_chart_outlined),
            selectedIcon: const Icon(Icons.bar_chart),
            label: S.t(context, 'tabDashboard'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.precision_manufacturing_outlined),
            selectedIcon: const Icon(Icons.precision_manufacturing),
            label: S.t(context, 'tabProduction'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.fact_check_outlined),
            selectedIcon: const Icon(Icons.fact_check),
            label: S.t(context, 'tabInspect'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.history_outlined),
            selectedIcon: const Icon(Icons.history),
            label: S.t(context, 'tabHistory'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: S.t(context, 'tabSettings'),
          ),
        ],
      ),
    );
  }
}

/// AppBar 우측 동기화 상태 — 대기/오류를 색+아이콘+숫자로 함께 표기.
/// 모두 동기화되면 아무것도 표시하지 않아 시각적 잡음을 줄인다.
class _SyncIndicator extends StatelessWidget {
  final bool warning;
  final int pending;

  const _SyncIndicator({required this.warning, required this.pending});

  @override
  Widget build(BuildContext context) {
    if (warning) {
      return StatusChip(
        kind: StatusKind.fail,
        label: pending > 0 ? '$pending' : S.t(context, 'syncStatus'),
        icon: Icons.cloud_off_rounded,
        dense: true,
      );
    }
    if (pending > 0) {
      return StatusChip(
        kind: StatusKind.info,
        label: '$pending',
        icon: Icons.cloud_upload_rounded,
        dense: true,
      );
    }
    return const SizedBox.shrink();
  }
}
