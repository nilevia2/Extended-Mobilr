part of extended_app;

// Try to resolve a logo URL for common assets; fallback to null.
String? _logoUrl(String symbol) {
  final s = symbol.trim().toUpperCase();
  // Extended CDN SVGs by asset name, e.g., https://cdn.extended.exchange/crypto/BTC.svg
  return 'https://cdn.extended.exchange/crypto/$s.svg';
}

class _ErrorReload extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;
  const _ErrorReload({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('Reload'),
        ),
      ],
    );
  }
}

class _Pair {
  final String base;
  final String quote;
  _Pair(this.base, this.quote);
}

_Pair _splitPair(String name) {
  // Expected formats: BTC-USD or BTC/USD
  if (name.contains('-')) {
    final parts = name.split('-');
    return _Pair(parts.first, parts.length > 1 ? parts[1] : '');
  }
  if (name.contains('/')) {
    final parts = name.split('/');
    return _Pair(parts.first, parts.length > 1 ? parts[1] : '');
  }
  return _Pair(name, '');
}

class _MarketAvatar extends StatelessWidget {
  final String symbol;
  final String? logoUrl;
  const _MarketAvatar({required this.symbol, required this.logoUrl});

  @override
  Widget build(BuildContext context) {
    final letter = symbol.isNotEmpty ? symbol.substring(0, 1).toUpperCase() : '?';
    final url = logoUrl;
    const size = 40.0;
    if (url == null || url.isEmpty) return CircleAvatar(child: Text(letter));
    final future = _logoBytesFutures.putIfAbsent(url, () async {
      final file = await _logoCache.getSingleFile(url);
      return file.readAsBytes();
    });

    return CircleAvatar(
      backgroundColor: Colors.transparent,
      radius: size / 2,
      child: ClipOval(
        child: FutureBuilder<Uint8List>(
          future: future,
          builder: (context, snap) {
            if (snap.hasData && snap.data != null) {
              return SvgPicture.memory(
                snap.data!,
                width: size,
                height: size,
                fit: BoxFit.cover,
              );
            }
            if (snap.hasError) {
              return Center(child: Text(letter));
            }
            return const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            );
          },
        ),
      ),
    );
  }
}

// Portfolio UI Components
class _ExtendedLogo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _loadLogo(),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return SvgPicture.string(
            snapshot.data!,
            width: 140,
            height: 26,
          );
        }
        // Fallback text logo
        return const Text(
          'extended',
          style: TextStyle(
            color: _colorTextMain,
            fontSize: 28,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.5,
          ),
        );
      },
    );
  }
  
  Future<String> _loadLogo() async {
    try {
      final response = await http.get(Uri.parse('https://app.extended.exchange/assets/logo/extended-long.svg'));
      if (response.statusCode == 200) {
        return response.body;
      }
    } catch (e) {
      debugPrint('[LOGO] Failed to load: $e');
    }
    // Return a simple text fallback in SVG format
    return '''<svg xmlns="http://www.w3.org/2000/svg" width="107" height="19" viewBox="0 0 107 19"><text x="0" y="15" fill="white" font-family="Arial" font-size="16">extended</text></svg>''';
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 100,
        height: 64,
        decoration: BoxDecoration(
          color: const Color(0xFF2A2A2A),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: _colorTextMain, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                color: _colorTextMain,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Delegate for pinned tabs header
class _TabsHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;

  _TabsHeaderDelegate({required this.child});

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: const Color(0xFF1A1A1A), // _colorBgMain
      child: child,
    );
  }

  @override
  double get maxExtent => 48.0;

  @override
  double get minExtent => 48.0;

  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) {
    return true; // Always rebuild to reflect tab selection changes
  }
}

class _PortfolioTabs extends StatelessWidget {
  final int selectedIndex;
  final Function(int) onTabSelected;
  
  const _PortfolioTabs({
    required this.selectedIndex,
    required this.onTabSelected,
  });
  
  @override
  Widget build(BuildContext context) {
    final tabs = ['Position', 'Orders', 'Realize'];
    
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: List.generate(tabs.length, (index) {
          final isSelected = index == selectedIndex;
          return Expanded(
            child: InkWell(
              onTap: () => onTabSelected(index),
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isSelected ? _colorGreenPrimary.withOpacity(0.15) : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  tabs[index],
                  style: TextStyle(
                    color: isSelected ? _colorGreenPrimary : _colorTextSecondary,
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
