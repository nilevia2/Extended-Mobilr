import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: 'assets/env');
  runApp(const ProviderScope(child: ExtendedApp()));
}

class ExtendedApp extends StatelessWidget {
  const ExtendedApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Extended',
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
      ),
      home: const MainScaffold(),
    );
  }
}

class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      const HomePage(),
      const PortfolioPage(),
      const TradePage(),
    ];

    final titles = <String>['Home', 'Portfolio', 'Trade'];

    return Scaffold(
      appBar: AppBar(title: Text(titles[_index])),
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

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(text: 'Search'),
              Tab(text: 'Watchlist'),
              Tab(text: 'Custom'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                const _SearchTab(),
                const _WatchlistTab(),
                const _CustomTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchTab extends StatelessWidget {
  const _SearchTab();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const TextField(
            decoration: InputDecoration(
              labelText: 'Search markets',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Center(
              child: Text(
                'Type to search markets...',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.black54),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WatchlistTab extends StatelessWidget {
  const _WatchlistTab();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'No items in watchlist',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.black54),
      ),
    );
  }
}

class _CustomTab extends StatelessWidget {
  const _CustomTab();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'Custom tab (to be added later)',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.black54),
      ),
    );
  }
}

class PortfolioPage extends StatelessWidget {
  const PortfolioPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FilledButton(
        onPressed: () {},
        child: const Text('Connect Wallet'),
      ),
    );
  }
}

class TradePage extends StatelessWidget {
  const TradePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('Trade screen (empty for now)'),
    );
  }
}


