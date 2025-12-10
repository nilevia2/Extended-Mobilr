part of extended_app;

class ExtendedApp extends StatefulWidget {
  const ExtendedApp({super.key});

  @override
  State<ExtendedApp> createState() => _ExtendedAppState();
}

class _ExtendedAppState extends State<ExtendedApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    debugPrint('[APP] Lifecycle changed: $state');
    // Keep app alive when returning from wallet
    if (state == AppLifecycleState.resumed) {
      debugPrint('[APP] App resumed from background - WalletConnect should handle response');
      // Give WalletConnect time to process any pending responses
      // Use a safe delayed callback that checks if widget is still mounted
      Future.delayed(const Duration(milliseconds: 1000), () {
        if (mounted) {
          debugPrint('[APP] Resumed delay complete - widget still mounted');
        } else {
          debugPrint('[APP] Resumed delay complete - widget disposed');
        }
      }).catchError((e) {
        debugPrint('[APP] Error in resumed delay: $e');
      });
    } else if (state == AppLifecycleState.paused) {
      debugPrint('[APP] App paused - going to background (likely opening wallet)');
    } else if (state == AppLifecycleState.inactive) {
      debugPrint('[APP] App inactive - transitioning');
    } else if (state == AppLifecycleState.hidden) {
      debugPrint('[APP] App hidden');
    } else if (state == AppLifecycleState.detached) {
      debugPrint('[APP] App detached');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.dark(
      primary: _colorGreenPrimary,
      secondary: _colorGreenPrimary,
      background: _colorBg,
      surface: _colorBg,
      onBackground: _colorTextMain,
      onSurface: _colorTextMain,
      error: _colorLoss,
    );

    return MaterialApp(
      title: 'Extended',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: _colorBg,
        appBarTheme: const AppBarTheme(
          backgroundColor: _colorBg,
          foregroundColor: _colorTextMain,
          elevation: 0,
        ),
        dividerColor: _colorBg,
        textTheme: const TextTheme(
          bodyMedium: TextStyle(color: _colorTextMain),
          bodySmall: TextStyle(color: _colorTextSecondary),
          labelSmall: TextStyle(color: _colorTextSecondary, letterSpacing: 0.2),
        ),
      ),
      home: const MainScaffold(),
    );
  }
}

// Global key for portfolio body to access logout from app bar
final GlobalKey<_PortfolioBodyState> _portfolioBodyKey = GlobalKey<_PortfolioBodyState>();

class MainScaffold extends ConsumerStatefulWidget {
  const MainScaffold({super.key});

  @override
  ConsumerState<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends ConsumerState<MainScaffold> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      const HomePage(),
      _PortfolioBody(key: _portfolioBodyKey),
      const TradePage(),
    ];

    final titles = <String>['Home', 'Portfolio', 'Trade'];
    
    // Get wallet address and API key state for app bar
    final portfolioState = ref.watch(_portfolioStateProvider);
    final displayAddress = portfolioState['walletAddress'] != null && portfolioState['walletAddress'].length > 8
        ? '${portfolioState['walletAddress'].substring(0, 4)}...${portfolioState['walletAddress'].substring(portfolioState['walletAddress'].length - 4)}'
        : portfolioState['walletAddress'] ?? '';
    final hasApiKey = portfolioState['hasApiKey'] == true;

    return Scaffold(
      appBar: AppBar(
        title: Text(titles[_index]),
        actions: [
          // Wallet address (if available)
          if (displayAddress.isNotEmpty) ...[
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _colorTextSecondary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  displayAddress,
                  style: const TextStyle(
                    color: _colorTextSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 16),
              ],
            ),
          ],
          // Menu button with logout/login
          _AppBarMenu(
            hasApiKey: hasApiKey,
            onLogout: () {
              // Trigger logout in portfolio page
              if (_portfolioBodyKey.currentState != null) {
                _portfolioBodyKey.currentState!.logout();
              }
            },
            onLogin: () {
              // Trigger login (wallet connect) in portfolio page
              if (_portfolioBodyKey.currentState != null) {
                _portfolioBodyKey.currentState!.connectWallet();
              }
            },
          ),
        ],
      ),
      body: pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.account_balance_wallet_outlined), selectedIcon: Icon(Icons.account_balance_wallet), label: 'Portfolio'),
          NavigationDestination(icon: Icon(Icons.show_chart_outlined), selectedIcon: Icon(Icons.show_chart), label: 'Trade'),
        ],
      ),
    );
  }
}

// Provider to share portfolio state with app bar
final _portfolioStateProvider = StateNotifierProvider<_PortfolioStateNotifier, Map<String, dynamic>>((ref) {
  return _PortfolioStateNotifier();
});

class _PortfolioStateNotifier extends StateNotifier<Map<String, dynamic>> {
  _PortfolioStateNotifier() : super({'walletAddress': null, 'hasApiKey': false});
  
  void updateState(String? walletAddress, bool hasApiKey) {
    state = {
      'walletAddress': walletAddress,
      'hasApiKey': hasApiKey,
    };
  }
}

// App bar menu component
class _AppBarMenu extends ConsumerWidget {
  final bool hasApiKey;
  final VoidCallback? onLogout;
  final VoidCallback? onLogin;
  
  const _AppBarMenu({
    required this.hasApiKey,
    this.onLogout,
    this.onLogin,
  });
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.menu, color: _colorTextMain, size: 24),
      color: _colorBgElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      onSelected: (value) async {
        if (value == 'logout' && onLogout != null) {
          onLogout!();
        } else if (value == 'login' && onLogin != null) {
          onLogin!();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: hasApiKey ? 'logout' : 'login',
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              hasApiKey ? 'Logout' : 'Login',
              style: const TextStyle(color: _colorTextMain, fontSize: 14),
            ),
          ),
        ),
      ],
    );
  }
}
