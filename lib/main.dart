import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ApexDemoApp());
}

const _ink = Color(0xFF0D0B16);
const _panel = Color(0xFF171321);
const _panelRaised = Color(0xFF211B2E);
const _violet = Color(0xFFA88BFF);
const _mint = Color(0xFF6DE5C1);
const _muted = Color(0xFFA7A0B5);
const _stroke = Color(0xFF342B44);

class ApexDemoApp extends StatefulWidget {
  const ApexDemoApp({super.key});

  @override
  State<ApexDemoApp> createState() => _ApexDemoAppState();
}

class _ApexDemoAppState extends State<ApexDemoApp> {
  final bridge = ApexBridge();

  @override
  void initState() {
    super.initState();
    bridge.connect();
  }

  @override
  void dispose() {
    bridge.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ApexScope(
      bridge: bridge,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Apex SDK Lab',
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: _ink,
          colorScheme: const ColorScheme.dark(
            primary: _violet,
            secondary: _mint,
            surface: _panel,
            onSurface: Color(0xFFF7F3FF),
            outline: _stroke,
          ),
          fontFamily: 'sans-serif',
          useMaterial3: true,
          cardTheme: const CardThemeData(
            color: _panel,
            elevation: 0,
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(22)),
              side: BorderSide(color: _stroke),
            ),
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              backgroundColor: _violet,
              foregroundColor: _ink,
              minimumSize: const Size(0, 50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              textStyle: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 50),
              side: const BorderSide(color: _stroke),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
        home: const AppShell(),
      ),
    );
  }
}

class ApexScope extends InheritedNotifier<ApexBridge> {
  const ApexScope({required ApexBridge bridge, required super.child, super.key})
    : super(notifier: bridge);

  static ApexBridge of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ApexScope>()!.notifier!;
}

class SdkEvent {
  SdkEvent({
    required this.format,
    required this.event,
    required this.message,
    required this.timestamp,
    required this.data,
  });

  factory SdkEvent.fromMap(Map<Object?, Object?> map) {
    return SdkEvent(
      format: map['format']?.toString() ?? 'sdk',
      event: map['event']?.toString() ?? 'info',
      message: map['message']?.toString() ?? '',
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        (map['timestamp'] as num?)?.toInt() ??
            DateTime.now().millisecondsSinceEpoch,
      ),
      data: Map<String, dynamic>.from(map['data'] as Map? ?? const {}),
    );
  }

  final String format;
  final String event;
  final String message;
  final DateTime timestamp;
  final Map<String, dynamic> data;
}

class ApexBridge extends ChangeNotifier {
  static const _methods = MethodChannel('com.apexads.flutter_demo/sdk');
  static const _events = EventChannel('com.apexads.flutter_demo/events');
  StreamSubscription<dynamic>? _subscription;
  final List<SdkEvent> logs = [];
  final Map<String, SdkEvent> latest = {};
  Map<String, dynamic> info = {};
  bool connected = false;

  Future<void> connect() async {
    if (!Platform.isAndroid) {
      _addLocal('sdk', 'error', 'The Apex SDK bridge is Android-only.');
      return;
    }
    _subscription = _events.receiveBroadcastStream().listen((dynamic raw) {
      final event = SdkEvent.fromMap(raw as Map<Object?, Object?>);
      logs.insert(0, event);
      if (logs.length > 100) logs.removeLast();
      latest[event.format] = event;
      connected = true;
      notifyListeners();
    }, onError: (Object error) => _addLocal('sdk', 'error', error.toString()));
    try {
      info = Map<String, dynamic>.from(
        await _methods.invokeMapMethod<String, dynamic>('getInfo') ?? const {},
      );
      connected = true;
      notifyListeners();
    } on PlatformException catch (error) {
      _addLocal('sdk', 'error', error.message ?? error.code);
    }
  }

  String statusFor(String format) => latest[format]?.event ?? 'idle';
  Map<String, dynamic> dataFor(String format) => latest[format]?.data ?? {};

  Future<void> load(String format) async {
    _addLocal(format, 'loading', 'Sending request to Apex SDK');
    await _invoke('loadAd', {'format': format});
  }

  Future<void> show(String format) => _invoke('showAd', {'format': format});
  Future<void> fetchBid() => _invoke('fetchBid');
  Future<void> simulateAuction() => _invoke('simulateAuction');
  Future<void> nativeClick({bool action = false}) =>
      _invoke('nativeClick', {'action': action});
  Future<void> conversationClick({bool action = false}) =>
      _invoke('conversationClick', {'action': action});
  Future<void> recordConversationRendered() =>
      _invoke('recordConversationRendered');

  Future<void> _invoke(String method, [Map<String, dynamic>? arguments]) async {
    if (!Platform.isAndroid) return;
    try {
      await _methods.invokeMethod<dynamic>(method, arguments);
    } on PlatformException catch (error) {
      _addLocal('sdk', 'error', error.message ?? error.code);
    }
  }

  void _addLocal(String format, String event, String message) {
    final item = SdkEvent(
      format: format,
      event: event,
      message: message,
      timestamp: DateTime.now(),
      data: const {},
    );
    logs.insert(0, item);
    latest[format] = item;
    notifyListeners();
  }

  void clearLogs() {
    logs.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int page = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomePage(onOpenLab: () => setState(() => page = 1)),
      const AdLabPage(),
      const SignalsPage(),
      const ConsolePage(),
    ];
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(index: page, children: pages),
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF12101A),
          border: Border(top: BorderSide(color: _stroke)),
        ),
        child: NavigationBar(
          selectedIndex: page,
          onDestinationSelected: (value) => setState(() => page = value),
          backgroundColor: Colors.transparent,
          indicatorColor: _violet.withValues(alpha: .16),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.space_dashboard_outlined),
              selectedIcon: Icon(Icons.space_dashboard_rounded),
              label: 'Overview',
            ),
            NavigationDestination(
              icon: Icon(Icons.science_outlined),
              selectedIcon: Icon(Icons.science_rounded),
              label: 'Ad lab',
            ),
            NavigationDestination(
              icon: Icon(Icons.hub_outlined),
              selectedIcon: Icon(Icons.hub_rounded),
              label: 'Signals',
            ),
            NavigationDestination(
              icon: Icon(Icons.terminal_outlined),
              selectedIcon: Icon(Icons.terminal_rounded),
              label: 'Console',
            ),
          ],
        ),
      ),
    );
  }
}

class PageFrame extends StatelessWidget {
  const PageFrame({
    required this.eyebrow,
    required this.title,
    required this.child,
    this.action,
    super.key,
  });

  final String eyebrow;
  final String title;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
          sliver: SliverToBoxAdapter(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        eyebrow.toUpperCase(),
                        style: const TextStyle(
                          color: _mint,
                          fontSize: 11,
                          letterSpacing: 1.8,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 28,
                          height: 1.05,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -.8,
                        ),
                      ),
                    ],
                  ),
                ),
                ?action,
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
          sliver: SliverToBoxAdapter(child: child),
        ),
      ],
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({required this.onOpenLab, super.key});
  final VoidCallback onOpenLab;

  @override
  Widget build(BuildContext context) {
    final bridge = ApexScope.of(context);
    return PageFrame(
      eyebrow: 'Apex SDK',
      title: 'Monetization,\nin one beautiful lab.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF49367D), Color(0xFF1B403B)],
              ),
              border: Border.all(color: Colors.white.withValues(alpha: .12)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    LiveDot(active: bridge.connected),
                    const SizedBox(width: 9),
                    Text(
                      bridge.connected ? 'SDK CONNECTED' : 'CONNECTING',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.3,
                      ),
                    ),
                    const Spacer(),
                    const Icon(Icons.bolt_rounded, color: _mint),
                  ],
                ),
                const SizedBox(height: 28),
                const Text(
                  '8 ad experiences.\n1 thin native bridge.',
                  style: TextStyle(
                    fontSize: 25,
                    height: 1.12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Real OpenRTB requests, native rendering, VAST playback and privacy-aware intent signals.',
                  style: TextStyle(
                    height: 1.45,
                    color: Colors.white.withValues(alpha: .72),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: onOpenLab,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Open ad lab'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const SectionTitle('Runtime'),
          const SizedBox(height: 12),
          Row(
            children: [
              const Expanded(
                child: MetricCard(
                  value: '8',
                  label: 'formats',
                  icon: Icons.grid_view_rounded,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: MetricCard(
                  value: '${bridge.logs.length}',
                  label: 'events',
                  icon: Icons.graphic_eq_rounded,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: MetricCard(
                  value: '2.6',
                  label: 'OpenRTB',
                  icon: Icons.swap_horiz_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          const SectionTitle('What this build proves'),
          const SizedBox(height: 12),
          const ProofRow(
            icon: Icons.layers_rounded,
            title: 'Flutter + native interoperability',
            body: 'Method events and Android platform views share one SDK runtime.',
          ),
          const ProofRow(
            icon: Icons.shield_outlined,
            title: 'Thin-client architecture',
            body: 'No on-device ML, native engines, or executable targeting rules.',
          ),
          const ProofRow(
            icon: Icons.visibility_outlined,
            title: 'Observable by design',
            body: 'Every SDK callback appears in the live console.',
          ),
        ],
      ),
    );
  }
}

class AdLabPage extends StatelessWidget {
  const AdLabPage({super.key});

  @override
  Widget build(BuildContext context) {
    final bridge = ApexScope.of(context);
    return PageFrame(
      eyebrow: 'Interactive',
      title: 'Ad format lab',
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            decoration: BoxDecoration(
              color: _panel,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _stroke),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline_rounded, color: _mint, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Start the Apex ad server on port 8080 for live demand.',
                    style: TextStyle(color: _muted, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          for (final spec in formatSpecs) ...[
            FormatTile(
              spec: spec,
              status: bridge.statusFor(spec.id),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ApexScope(
                    bridge: bridge,
                    child: FormatDetailPage(spec: spec),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class FormatSpec {
  const FormatSpec({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.tags,
  });
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final List<String> tags;
}

const formatSpecs = [
  FormatSpec(
    id: 'banner',
    title: 'Banner',
    subtitle: 'WebView creative with MRC viewability',
    icon: Icons.panorama_wide_angle_rounded,
    color: Color(0xFF7CC8FF),
    tags: ['320×50', 'MRAID 3.0'],
  ),
  FormatSpec(
    id: 'interstitial',
    title: 'Interstitial',
    subtitle: 'Immersive fullscreen HTML experience',
    icon: Icons.fullscreen_rounded,
    color: Color(0xFFFFA86D),
    tags: ['Fullscreen', 'Preload'],
  ),
  FormatSpec(
    id: 'native',
    title: 'Native',
    subtitle: 'Publisher-rendered OpenRTB Native 1.2',
    icon: Icons.article_outlined,
    color: Color(0xFFFF7DB1),
    tags: ['Native 1.2', 'Intent CTA'],
  ),
  FormatSpec(
    id: 'conversation',
    title: 'Conversational',
    subtitle: 'Sponsored suggestions for assistant surfaces',
    icon: Icons.forum_outlined,
    color: _mint,
    tags: ['Answer-safe', 'Structured intent'],
  ),
  FormatSpec(
    id: 'video',
    title: 'Rewarded video',
    subtitle: 'VAST playback and quartile tracking',
    icon: Icons.play_circle_outline_rounded,
    color: Color(0xFFFFD96D),
    tags: ['VAST 4.0', 'Reward'],
  ),
  FormatSpec(
    id: 'appopen',
    title: 'App open',
    subtitle: 'Lifecycle-aware foreground monetization',
    icon: Icons.open_in_new_rounded,
    color: Color(0xFF8EA8FF),
    tags: ['Preload', 'Frequency cap'],
  ),
  FormatSpec(
    id: 'bidding',
    title: 'In-app bidding',
    subtitle: 'Price signal before the mediation waterfall',
    icon: Icons.gavel_rounded,
    color: _violet,
    tags: ['30s token', 'MAX / LevelPlay'],
  ),
  FormatSpec(
    id: 'wallet',
    title: 'Wallet action',
    subtitle: 'Intent-to-action ads with Google Wallet',
    icon: Icons.account_balance_wallet_outlined,
    color: Color(0xFF78E49D),
    tags: ['Executable CTA', 'Fallback-safe'],
  ),
];

class FormatTile extends StatelessWidget {
  const FormatTile({
    required this.spec,
    required this.status,
    required this.onTap,
    super.key,
  });
  final FormatSpec spec;
  final String status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: spec.color.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(spec.icon, color: spec.color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            spec.title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        StatusDot(status: status),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      spec.subtitle,
                      style: const TextStyle(color: _muted, fontSize: 13),
                    ),
                    const SizedBox(height: 9),
                    Wrap(
                      spacing: 6,
                      children: spec.tags.map((tag) => TinyTag(tag)).toList(),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right_rounded, color: _muted),
            ],
          ),
        ),
      ),
    );
  }
}

class FormatDetailPage extends StatefulWidget {
  const FormatDetailPage({required this.spec, super.key});
  final FormatSpec spec;

  @override
  State<FormatDetailPage> createState() => _FormatDetailPageState();
}

class _FormatDetailPageState extends State<FormatDetailPage> {
  bool conversationRecorded = false;

  @override
  Widget build(BuildContext context) {
    final bridge = ApexScope.of(context);
    final status = bridge.statusFor(widget.spec.id);
    final event = bridge.latest[widget.spec.id];
    final ready = {'loaded', 'shown', 'completed', 'reward'}.contains(status);
    if (widget.spec.id == 'conversation' &&
        status == 'loaded' &&
        !conversationRecorded) {
      conversationRecorded = true;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => bridge.recordConversationRendered(),
      );
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: _ink,
        surfaceTintColor: Colors.transparent,
        title: Text(widget.spec.title),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 36),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: widget.spec.color.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: widget.spec.color.withValues(alpha: .28),
              ),
            ),
            child: Row(
              children: [
                Icon(widget.spec.icon, color: widget.spec.color, size: 38),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.spec.subtitle,
                        style: const TextStyle(fontSize: 15, height: 1.35),
                      ),
                      const SizedBox(height: 10),
                      StatusPill(status: status),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          if (event != null)
            EventNotice(event: event)
          else
            const EventNotice.empty(),
          const SizedBox(height: 18),
          FormatCanvas(spec: widget.spec, data: bridge.dataFor(widget.spec.id)),
          const SizedBox(height: 18),
          if (widget.spec.id == 'appopen')
            AppOpenActions(ready: ready)
          else if (widget.spec.id == 'bidding')
            BiddingActions(bridge: bridge, ready: ready)
          else ...[
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: status == 'loading'
                    ? null
                    : () => bridge.load(widget.spec.id),
                icon: status == 'loading'
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_download_outlined),
                label: Text(
                  status == 'loading' ? 'Requesting…' : 'Load live ad',
                ),
              ),
            ),
            if ({
              'interstitial',
              'video',
              'wallet',
            }.contains(widget.spec.id)) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: ready ? () => bridge.show(widget.spec.id) : null,
                  icon: const Icon(Icons.open_in_full_rounded),
                  label: const Text('Show'),
                ),
              ),
            ],
          ],
          const SizedBox(height: 24),
          const SectionTitle('Integration contract'),
          const SizedBox(height: 10),
          ContractCard(spec: widget.spec),
        ],
      ),
    );
  }
}

class FormatCanvas extends StatelessWidget {
  const FormatCanvas({required this.spec, required this.data, super.key});
  final FormatSpec spec;
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    if (spec.id == 'banner') return const BannerCanvas(slot: 'banner');
    if (spec.id == 'native') return NativeCanvas(data: data);
    if (spec.id == 'conversation') return ConversationCanvas(data: data);
    if (spec.id == 'wallet') return const WalletCanvas();
    if (spec.id == 'bidding') return BiddingCanvas(data: data);
    return GenericCanvas(spec: spec);
  }
}

class BannerCanvas extends StatelessWidget {
  const BannerCanvas({required this.slot, super.key});
  final String slot;

  @override
  Widget build(BuildContext context) {
    final width = slot == 'mrect' ? 300.0 : 320.0;
    final height = slot == 'mrect' ? 250.0 : 50.0;
    return PreviewFrame(
      label: slot == 'mrect'
          ? 'ANDROID VIEW · 300×250'
          : 'ANDROID VIEW · 320×50',
      child: Center(
        child: SizedBox(
          width: width,
          height: height,
          child: Platform.isAndroid
              ? AndroidView(
                  viewType: 'apexads/banner',
                  creationParams: {'slot': slot},
                  creationParamsCodec: const StandardMessageCodec(),
                )
              : const ColoredBox(color: _panelRaised),
        ),
      ),
    );
  }
}

class NativeCanvas extends StatelessWidget {
  const NativeCanvas({required this.data, super.key});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final bridge = ApexScope.of(context);
    if (data.isEmpty) {
      return const PlaceholderCanvas(
        icon: Icons.article_outlined,
        text: 'Native assets will render here in Flutter.',
      );
    }
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => bridge.nativeClick(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DisclosureBar(
              disclosure: '${data['disclosure'] ?? 'Sponsored'}',
              advertiser: '${data['advertiser'] ?? 'Advertiser'}',
            ),
            if (data['imageUrl'] != null)
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.network(
                  '${data['imageUrl']}',
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const CreativeFallback(),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (data['intentLabel'] != null)
                    TinyTag('${data['intentLabel']}'),
                  const SizedBox(height: 10),
                  Text(
                    '${data['title'] ?? ''}',
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${data['description'] ?? ''}',
                    style: const TextStyle(color: _muted, height: 1.4),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () =>
                          bridge.nativeClick(action: data['hasAction'] == true),
                      child: Text('${data['cta'] ?? 'Learn more'}'),
                    ),
                  ),
                  if (Platform.isAndroid)
                    const SizedBox(
                      width: 1,
                      height: 1,
                      child: AndroidView(viewType: 'apexads/native-tracker'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ConversationCanvas extends StatelessWidget {
  const ConversationCanvas({required this.data, super.key});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final bridge = ApexScope.of(context);
    return PreviewFrame(
      label: 'ASSISTANT SURFACE · ANSWER INDEPENDENCE',
      child: Column(
        children: [
          const ChatBubble(
            text: 'Weekend stay in Bengaluru, under ₹4,000?',
            mine: true,
          ),
          const ChatBubble(
            text:
                'I found 12 stays. Here is the strongest match for your dates.',
            mine: false,
          ),
          if (data.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: PlaceholderCanvas(
                icon: Icons.auto_awesome_outlined,
                text: 'A disclosed suggestion can appear between answers.',
                compact: true,
              ),
            )
          else
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: _panelRaised,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: _violet.withValues(alpha: .45)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DisclosureBar(
                    disclosure: '${data['disclosure'] ?? 'Sponsored'}',
                    advertiser: '${data['advertiser'] ?? 'Advertiser'}',
                  ),
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (data['relevance'] != null)
                          TinyTag('${data['relevance']}'),
                        const SizedBox(height: 9),
                        Text(
                          '${data['title'] ?? ''}',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${data['body'] ?? ''}',
                          style: const TextStyle(color: _muted, fontSize: 13),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: () => bridge.conversationClick(
                              action: data['hasAction'] == true,
                            ),
                            child: Text('${data['cta'] ?? 'View offer'}'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const ChatBubble(
            text: 'Want me to compare it with two similar stays?',
            mine: false,
          ),
        ],
      ),
    );
  }
}

class WalletCanvas extends StatelessWidget {
  const WalletCanvas({super.key});
  @override
  Widget build(BuildContext context) {
    return PreviewFrame(
      label: 'INTENT → ACTION',
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _mint.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Row(
          children: [
            Icon(Icons.account_balance_wallet_rounded, color: _mint, size: 34),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Save offer to Wallet',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'The SDK executes the action and falls back to click-through safely.',
                    style: TextStyle(color: _muted, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class BiddingCanvas extends StatelessWidget {
  const BiddingCanvas({required this.data, super.key});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final cpm = (data['cpm'] as num?)?.toDouble();
    return PreviewFrame(
      label: 'MEDIATION PRICE SIGNAL',
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Apex bid',
                  style: TextStyle(color: _muted, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  cpm == null ? '—' : '\$${cpm.toStringAsFixed(3)}',
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          Container(width: 1, height: 50, color: _stroke),
          const SizedBox(width: 18),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Token TTL',
                  style: TextStyle(color: _muted, fontSize: 12),
                ),
                SizedBox(height: 4),
                Text(
                  '30 sec',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class GenericCanvas extends StatelessWidget {
  const GenericCanvas({required this.spec, super.key});
  final FormatSpec spec;
  @override
  Widget build(BuildContext context) => PlaceholderCanvas(
    icon: spec.icon,
    text: spec.id == 'appopen'
        ? 'Background and reopen the app to trigger the lifecycle flow.'
        : 'The loaded creative opens in the native fullscreen SDK activity.',
  );
}

class BiddingActions extends StatelessWidget {
  const BiddingActions({required this.bridge, required this.ready, super.key});
  final ApexBridge bridge;
  final bool ready;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: bridge.fetchBid,
            icon: const Icon(Icons.price_check_rounded),
            label: const Text('1. Fetch Apex bid token'),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: ready ? bridge.simulateAuction : null,
            icon: const Icon(Icons.gavel_rounded),
            label: const Text('2. Simulate mediation auction'),
          ),
        ),
      ],
    );
  }
}

class AppOpenActions extends StatelessWidget {
  const AppOpenActions({required this.ready, super.key});
  final bool ready;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _stroke),
      ),
      child: Row(
        children: [
          Icon(
            ready ? Icons.check_circle_rounded : Icons.hourglass_top_rounded,
            color: ready ? _mint : _muted,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              ready
                  ? 'Ready. Background the app, then return.'
                  : 'The SDK automatically preloads this format.',
            ),
          ),
        ],
      ),
    );
  }
}

class SignalsPage extends StatelessWidget {
  const SignalsPage({super.key});
  @override
  Widget build(BuildContext context) {
    final bridge = ApexScope.of(context);
    return PageFrame(
      eyebrow: 'Request intelligence',
      title: 'Signals & privacy',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SignalPath(),
          const SizedBox(height: 22),
          const SectionTitle('Runtime configuration'),
          const SizedBox(height: 12),
          ConfigRow(
            icon: Icons.android_rounded,
            label: 'Native platform',
            value: '${bridge.info['platform'] ?? 'Android'}',
          ),
          ConfigRow(
            icon: Icons.memory_rounded,
            label: 'SDK version',
            value: '${bridge.info['sdkVersion'] ?? '1.0.0-SNAPSHOT'}',
          ),
          ConfigRow(
            icon: Icons.dns_outlined,
            label: 'Debug auction',
            value: '${bridge.info['server'] ?? '10.0.2.2:8080'}',
          ),
          const ConfigRow(
            icon: Icons.science_outlined,
            label: 'Fake fill',
            value: 'Off',
            valueColor: _mint,
          ),
          const SizedBox(height: 22),
          const SectionTitle('Privacy posture'),
          const SizedBox(height: 12),
          const PolicyCard(
            icon: Icons.chat_bubble_outline_rounded,
            title: 'No conversation content',
            body: 'Assistant ads receive a coarse taxonomy and journey stage—not prompts, messages, or free-form text.',
          ),
          const PolicyCard(
            icon: Icons.data_object_rounded,
            title: 'Declarative cohorts only',
            body: 'Audience rules remain data. The client ships no remote code or embedded JavaScript engine.',
          ),
          const PolicyCard(
            icon: Icons.phonelink_lock_outlined,
            title: 'Consent-gated identity',
            body: 'TCF, US Privacy, Limit Ad Tracking, and COPPA signals can remove identity before bidding.',
          ),
        ],
      ),
    );
  }
}

class ConsolePage extends StatelessWidget {
  const ConsolePage({super.key});
  @override
  Widget build(BuildContext context) {
    final bridge = ApexScope.of(context);
    return PageFrame(
      eyebrow: 'Live callbacks',
      title: 'Event console',
      action: IconButton.filledTonal(
        tooltip: 'Clear events',
        onPressed: bridge.logs.isEmpty ? null : bridge.clearLogs,
        icon: const Icon(Icons.delete_sweep_outlined),
      ),
      child: bridge.logs.isEmpty
          ? const PlaceholderCanvas(
              icon: Icons.terminal_rounded,
              text: 'SDK callbacks will appear here.',
            )
          : Container(
              decoration: BoxDecoration(
                color: const Color(0xFF100E17),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _stroke),
              ),
              child: Column(
                children: [
                  for (var i = 0; i < bridge.logs.length; i++) ...[
                    LogRow(event: bridge.logs[i]),
                    if (i != bridge.logs.length - 1)
                      const Divider(height: 1, color: _stroke),
                  ],
                ],
              ),
            ),
    );
  }
}

class SignalPath extends StatelessWidget {
  const SignalPath({super.key});
  @override
  Widget build(BuildContext context) {
    const steps = [
      (Icons.phone_android_rounded, 'Flutter UI'),
      (Icons.compare_arrows_rounded, 'Native bridge'),
      (Icons.hub_rounded, 'Apex SDK'),
      (Icons.cloud_outlined, 'OpenRTB auction'),
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _stroke),
      ),
      child: Column(
        children: [
          for (var i = 0; i < steps.length; i++) ...[
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: i == 2
                        ? _violet.withValues(alpha: .14)
                        : _panelRaised,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(steps[i].$1, color: i == 2 ? _violet : _muted),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Text(
                    steps[i].$2,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                if (i == 2) const TinyTag('thin client'),
              ],
            ),
            if (i != steps.length - 1)
              Container(
                margin: const EdgeInsets.only(left: 20),
                alignment: Alignment.centerLeft,
                height: 18,
                child: Container(width: 2, height: 18, color: _stroke),
              ),
          ],
        ],
      ),
    );
  }
}

class MetricCard extends StatelessWidget {
  const MetricCard({
    required this.value,
    required this.label,
    required this.icon,
    super.key,
  });
  final String value;
  final String label;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: _panel,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: _stroke),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 19, color: _violet),
        const SizedBox(height: 14),
        Text(
          value,
          style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
        ),
        Text(label, style: const TextStyle(color: _muted, fontSize: 11)),
      ],
    ),
  );
}

class ProofRow extends StatelessWidget {
  const ProofRow({
    required this.icon,
    required this.title,
    required this.body,
    super.key,
  });
  final IconData icon;
  final String title;
  final String body;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: _panelRaised,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: _mint, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text(
                body,
                style: const TextStyle(
                  color: _muted,
                  height: 1.35,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class ConfigRow extends StatelessWidget {
  const ConfigRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
    super.key,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: _panel,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _stroke),
    ),
    child: Row(
      children: [
        Icon(icon, color: _muted, size: 20),
        const SizedBox(width: 12),
        Expanded(child: Text(label)),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: valueColor ?? _violet,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

class PolicyCard extends StatelessWidget {
  const PolicyCard({
    required this.icon,
    required this.title,
    required this.body,
    super.key,
  });
  final IconData icon;
  final String title;
  final String body;
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: _mint),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 5),
                Text(
                  body,
                  style: const TextStyle(
                    color: _muted,
                    height: 1.4,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class EventNotice extends StatelessWidget {
  const EventNotice({required this.event, super.key}) : emptyState = false;
  const EventNotice.empty({super.key}) : event = null, emptyState = true;
  final SdkEvent? event;
  final bool emptyState;
  @override
  Widget build(BuildContext context) {
    final color = emptyState ? _muted : statusColor(event!.event);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: .25)),
      ),
      child: Row(
        children: [
          Icon(
            emptyState
                ? Icons.radio_button_unchecked
                : statusIcon(event!.event),
            color: color,
            size: 20,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              emptyState ? 'Ready for your first request.' : event!.message,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PreviewFrame extends StatelessWidget {
  const PreviewFrame({required this.label, required this.child, super.key});
  final String label;
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: _panel,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: _stroke),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: _muted,
            fontSize: 10,
            letterSpacing: 1.15,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 14),
        child,
      ],
    ),
  );
}

class PlaceholderCanvas extends StatelessWidget {
  const PlaceholderCanvas({
    required this.icon,
    required this.text,
    this.compact = false,
    super.key,
  });
  final IconData icon;
  final String text;
  final bool compact;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: EdgeInsets.symmetric(horizontal: 24, vertical: compact ? 20 : 42),
    decoration: BoxDecoration(
      color: _panel,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: _stroke),
    ),
    child: Column(
      children: [
        Icon(icon, size: compact ? 30 : 42, color: _violet),
        const SizedBox(height: 12),
        Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: _muted, height: 1.4),
        ),
      ],
    ),
  );
}

class ContractCard extends StatelessWidget {
  const ContractCard({required this.spec, super.key});
  final FormatSpec spec;
  @override
  Widget build(BuildContext context) {
    final rows = switch (spec.id) {
      'banner' => [
        ('Placement', 'demo-banner-placement'),
        ('Render', 'Android PlatformView'),
        ('Viewability', 'MRC threshold'),
      ],
      'interstitial' => [
        ('Placement', 'demo-interstitial-placement'),
        ('Render', 'Native Activity'),
        ('Markup', 'HTML / MRAID 3.0'),
      ],
      'native' => [
        ('Placement', 'demo-native-placement'),
        ('Payload', 'OpenRTB Native 1.2'),
        ('Render', 'Flutter publisher UI'),
      ],
      'conversation' => [
        ('Placement', 'demo-assistant-inline'),
        ('Surface', 'assistant'),
        ('Privacy', 'Structured intent only'),
      ],
      'video' => [
        ('Placement', 'demo-video-placement'),
        ('Protocol', 'VAST 4.0'),
        ('Player', 'Android Media3'),
      ],
      'appopen' => [
        ('Placement', 'demo-appopen-placement'),
        ('Trigger', 'Process foreground'),
        ('Expiry', '30 minutes'),
      ],
      'bidding' => [
        ('Placement', 'demo-inappbidding-placement'),
        ('Format', 'Interstitial'),
        ('TTL', '30 seconds'),
      ],
      _ => [
        ('Placement', 'demo-wallet-interstitial'),
        ('Capability', 'Google Wallet'),
        ('Fallback', 'Standard click-through'),
      ],
    };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _stroke),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    rows[i].$1,
                    style: const TextStyle(color: _muted, fontSize: 13),
                  ),
                ),
                Text(
                  rows[i].$2,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            if (i != rows.length - 1) const Divider(height: 22, color: _stroke),
          ],
        ],
      ),
    );
  }
}

class DisclosureBar extends StatelessWidget {
  const DisclosureBar({
    required this.disclosure,
    required this.advertiser,
    super.key,
  });
  final String disclosure;
  final String advertiser;
  @override
  Widget build(BuildContext context) => Container(
    color: _violet.withValues(alpha: .08),
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
    child: Row(
      children: [
        Expanded(
          child: Text(
            '$disclosure · $advertiser',
            style: const TextStyle(
              color: _violet,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const Text(
          'Why this ad?',
          style: TextStyle(color: _violet, fontSize: 10),
        ),
      ],
    ),
  );
}

class CreativeFallback extends StatelessWidget {
  const CreativeFallback({super.key});
  @override
  Widget build(BuildContext context) => Container(
    color: _panelRaised,
    child: const Center(
      child: Icon(Icons.image_not_supported_outlined, color: _muted, size: 34),
    ),
  );
}

class ChatBubble extends StatelessWidget {
  const ChatBubble({required this.text, required this.mine, super.key});
  final String text;
  final bool mine;
  @override
  Widget build(BuildContext context) => Align(
    alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
    child: Container(
      constraints: const BoxConstraints(maxWidth: 275),
      margin: const EdgeInsets.symmetric(vertical: 5),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: BoxDecoration(
        color: mine ? _violet : _panelRaised,
        borderRadius: BorderRadius.circular(16).copyWith(
          bottomRight: mine ? const Radius.circular(4) : null,
          bottomLeft: mine ? null : const Radius.circular(4),
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: mine ? _ink : Colors.white,
          fontSize: 13,
          height: 1.35,
        ),
      ),
    ),
  );
}

class LogRow extends StatelessWidget {
  const LogRow({required this.event, super.key});
  final SdkEvent event;
  @override
  Widget build(BuildContext context) {
    final time =
        '${event.timestamp.hour.toString().padLeft(2, '0')}:${event.timestamp.minute.toString().padLeft(2, '0')}:${event.timestamp.second.toString().padLeft(2, '0')}';
    final color = statusColor(event.event);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            time,
            style: const TextStyle(
              color: Color(0xFF6F687B),
              fontFamily: 'monospace',
              fontSize: 11,
            ),
          ),
          const SizedBox(width: 10),
          Container(
            width: 7,
            height: 7,
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  height: 1.45,
                ),
                children: [
                  TextSpan(
                    text: '${event.format.padRight(13)} ',
                    style: TextStyle(color: color, fontWeight: FontWeight.w700),
                  ),
                  TextSpan(
                    text: event.message,
                    style: const TextStyle(color: Color(0xFFC9C3D3)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
  );
}

class TinyTag extends StatelessWidget {
  const TinyTag(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .055),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: _stroke),
    ),
    child: Text(
      text,
      style: const TextStyle(
        color: _muted,
        fontSize: 10,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class LiveDot extends StatelessWidget {
  const LiveDot({required this.active, super.key});
  final bool active;
  @override
  Widget build(BuildContext context) => Container(
    width: 9,
    height: 9,
    decoration: BoxDecoration(
      color: active ? _mint : _muted,
      shape: BoxShape.circle,
      boxShadow: active
          ? [BoxShadow(color: _mint.withValues(alpha: .65), blurRadius: 8)]
          : null,
    ),
  );
}

class StatusDot extends StatelessWidget {
  const StatusDot({required this.status, super.key});
  final String status;
  @override
  Widget build(BuildContext context) => Container(
    width: 8,
    height: 8,
    decoration: BoxDecoration(
      color: statusColor(status),
      shape: BoxShape.circle,
    ),
  );
}

class StatusPill extends StatelessWidget {
  const StatusPill({required this.status, super.key});
  final String status;
  @override
  Widget build(BuildContext context) {
    final color = statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 10,
          letterSpacing: .8,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

Color statusColor(String status) => switch (status) {
  'loaded' || 'shown' || 'completed' || 'reward' || 'auction' => _mint,
  'loading' || 'waiting' => const Color(0xFFFFD96D),
  'error' => const Color(0xFFFF7D8A),
  _ => _muted,
};

IconData statusIcon(String status) => switch (status) {
  'loaded' ||
  'shown' ||
  'completed' ||
  'reward' ||
  'auction' => Icons.check_circle_outline_rounded,
  'loading' || 'waiting' => Icons.hourglass_top_rounded,
  'error' => Icons.error_outline_rounded,
  _ => Icons.info_outline_rounded,
};
