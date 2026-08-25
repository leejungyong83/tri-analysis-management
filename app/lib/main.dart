import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/app_settings.dart';
import 'core/ict_time.dart';
import 'core/strings.dart';
import 'theme/app_theme.dart';
import 'screens/dashboard_screen.dart';
import 'screens/history_screen.dart';
import 'screens/inspection_form_screen.dart';
import 'screens/login_screen.dart';
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

  // 앱 접근 게이트(직원 ID/비밀번호) — 데이터 API 자체의 보안(app_token)과는 별개로,
  // "누가 이 앱을 열 수 있는가"만 통제한다. 세션은 supabase_flutter가 자동 저장/갱신.
  await Supabase.initialize(
    url: ApiClient.supabaseUrl,
    publishableKey: ApiClient.supabaseAnonKey,
  );

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
      home: StreamBuilder<AuthState>(
        stream: Supabase.instance.client.auth.onAuthStateChange,
        initialData: AuthState(
          AuthChangeEvent.initialSession,
          Supabase.instance.client.auth.currentSession,
        ),
        builder: (context, snapshot) {
          final loggedIn = snapshot.data?.session != null;
          if (!loggedIn) return const LoginScreen();
          // 계정 role(Supabase User Metadata: {"role":"admin"})로 관리자/검사자 구분.
          // 미설정 시 최소 권한(검사자)으로 취급 — 관리자는 명시적으로 지정해야 함.
          final role = Supabase
              .instance.client.auth.currentUser?.userMetadata?['role'];
          final isAdmin = role == 'admin';
          return HomeShell(
            api: _api,
            masters: _masters,
            queue: _queue,
            photoService: _photoService,
            isAdmin: isAdmin,
            onLocaleChanged: (code) => setState(() => _locale = Locale(code)),
            onThemeChanged: (mode) => setState(() {
              AppSettings.themeMode = mode;
              _themeMode = _parseThemeMode(mode);
            }),
          );
        },
      ),
    );
  }
}

class HomeShell extends StatefulWidget {
  final ApiClient api;
  final MasterCache masters;
  final SyncQueue queue;
  final PhotoService photoService;
  final bool isAdmin;
  final void Function(String locale) onLocaleChanged;
  final void Function(String themeMode) onThemeChanged;

  const HomeShell({
    super.key,
    required this.api,
    required this.masters,
    required this.queue,
    required this.photoService,
    required this.isAdmin,
    required this.onLocaleChanged,
    required this.onThemeChanged,
  });

  @override
  State<HomeShell> createState() => _HomeShellState();
}

/// 탭 1개 정의 — 관리자 전용 탭은 build 시 isAdmin 여부로 제외한다.
class _Tab {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final Widget screen;
  final VoidCallback? onSelected; // 탭 진입 시 최신 데이터로 갱신
  const _Tab({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.screen,
    this.onSelected,
  });
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

  /// 탭은 전 역할 공통 공개(조회는 누구나) — 실제 데이터를 바꾸는 액션(예: 이력의
  /// 무효화/void, 설정의 앱 토큰 변경)만 각 화면 내부에서 isAdmin으로 개별 제한한다.
  List<_Tab> _tabs(BuildContext context) {
    return [
      _Tab(
        icon: Icons.bar_chart_outlined,
        selectedIcon: Icons.bar_chart,
        label: S.t(context, 'tabDashboard'),
        screen: DashboardScreen(
            key: _dashKey, api: widget.api, queue: widget.queue),
        onSelected: () => _dashKey.currentState?.refresh(),
      ),
      _Tab(
        icon: Icons.precision_manufacturing_outlined,
        selectedIcon: Icons.precision_manufacturing,
        label: S.t(context, 'tabProduction'),
        screen: ProductionScreen(
            key: _prodKey, api: widget.api, masters: widget.masters),
        onSelected: () => _prodKey.currentState?.refresh(),
      ),
      _Tab(
        icon: Icons.fact_check_outlined,
        selectedIcon: Icons.fact_check,
        label: S.t(context, 'tabInspect'),
        screen: InspectionFormScreen(
          key: _inspKey,
          api: widget.api,
          queue: widget.queue,
          masters: widget.masters,
          photoService: widget.photoService,
        ),
        onSelected: () => _inspKey.currentState?.refreshLots(),
      ),
      _Tab(
        icon: Icons.history_outlined,
        selectedIcon: Icons.history,
        label: S.t(context, 'tabHistory'),
        screen: HistoryScreen(
            api: widget.api, masters: widget.masters, isAdmin: widget.isAdmin),
      ),
      _Tab(
        icon: Icons.settings_outlined,
        selectedIcon: Icons.settings,
        label: S.t(context, 'tabSettings'),
        screen: SettingsScreen(
          api: widget.api,
          masters: widget.masters,
          queue: widget.queue,
          isAdmin: widget.isAdmin,
          onLocaleChanged: widget.onLocaleChanged,
          onThemeChanged: widget.onThemeChanged,
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final pendingTotal =
        widget.queue.pendingRecords + widget.queue.pendingPhotos;
    final tabs = _tabs(context);
    if (_index >= tabs.length) _index = 0; // 역할 전환 등으로 탭 수가 줄어든 경우 방어
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.button),
              child: Image.asset('assets/logo.png', width: 30, height: 30),
            ),
            const SizedBox(width: AppSpacing.sm + 2),
            Text(S.t(context, 'appTitle')),
          ],
        ),
        actions: [
          const _LiveClock(),
          const SizedBox(width: AppSpacing.sm),
          _LanguageButton(onChanged: widget.onLocaleChanged),
          _ThemeButton(onChanged: widget.onThemeChanged),
          _SyncIndicator(
            warning: widget.queue.warning,
            pending: pendingTotal,
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: IndexedStack(
        index: _index,
        children: [for (final t in tabs) t.screen],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) {
          setState(() => _index = i);
          // 각 탭은 열 때마다 서버 최신 상태로 갱신 (앱 시작 시점 조회 오류 방지)
          tabs[i].onSelected?.call();
        },
        destinations: [
          for (final t in tabs)
            NavigationDestination(
              icon: Icon(t.icon),
              selectedIcon: Icon(t.selectedIcon),
              label: t.label,
            ),
        ],
      ),
    );
  }
}

/// AppBar 실시간 시계 (ICT, 초 단위) — 1초마다 갱신.
class _LiveClock extends StatefulWidget {
  const _LiveClock();

  @override
  State<_LiveClock> createState() => _LiveClockState();
}

class _LiveClockState extends State<_LiveClock> {
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = IctTime.nowIct();
    String p2(int v) => v.toString().padLeft(2, '0');
    return Text(
      '${p2(n.hour)}:${p2(n.minute)}:${p2(n.second)}',
      style: Theme.of(context)
          .textTheme
          .labelMedium
          ?.copyWith(color: context.scheme.onSurfaceVariant),
    );
  }
}

/// AppBar 언어 선택 (한국어/Tiếng Việt) — 설정 탭에도 동일 옵션 있음, 여기선 빠른 접근용.
class _LanguageButton extends StatelessWidget {
  final void Function(String locale) onChanged;
  const _LanguageButton({required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.language),
      tooltip: S.t(context, 'language'),
      onSelected: (v) {
        AppSettings.locale = v;
        onChanged(v);
      },
      itemBuilder: (context) => const [
        PopupMenuItem(value: 'vi', child: Text('Tiếng Việt')),
        PopupMenuItem(value: 'ko', child: Text('한국어')),
      ],
    );
  }
}

/// AppBar 테마 선택(시스템/라이트/다크) — 설정 탭에도 동일 옵션 있음, 여기선 빠른 접근용.
class _ThemeButton extends StatelessWidget {
  final void Function(String themeMode) onChanged;
  const _ThemeButton({required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.brightness_6_outlined),
      tooltip: S.t(context, 'appearance'),
      onSelected: onChanged,
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'system',
          child: Row(children: [
            const Icon(Icons.brightness_auto_outlined, size: 18),
            const SizedBox(width: AppSpacing.sm),
            Text(S.t(context, 'themeSystem')),
          ]),
        ),
        PopupMenuItem(
          value: 'light',
          child: Row(children: [
            const Icon(Icons.light_mode_outlined, size: 18),
            const SizedBox(width: AppSpacing.sm),
            Text(S.t(context, 'themeLight')),
          ]),
        ),
        PopupMenuItem(
          value: 'dark',
          child: Row(children: [
            const Icon(Icons.dark_mode_outlined, size: 18),
            const SizedBox(width: AppSpacing.sm),
            Text(S.t(context, 'themeDark')),
          ]),
        ),
      ],
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
