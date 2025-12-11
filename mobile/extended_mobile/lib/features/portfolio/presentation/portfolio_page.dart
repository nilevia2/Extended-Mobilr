import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/di/service_locator.dart';
import '../../../core/backend_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/wallet_connect.dart';
import '../data/portfolio_repository.dart';
import 'portfolio_bloc.dart';
import 'portfolio_event.dart';
import 'portfolio_state.dart';

class PortfolioPage extends StatelessWidget {
  const PortfolioPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => PortfolioBloc(
        repository: getIt<PortfolioRepository>(),
        walletService: getIt<WalletService>(),
        backendClient: getIt<BackendClient>(),
      )..add(const PortfolioEvent.started()),
      child: const _PortfolioView(),
    );
  }
}

class _PortfolioView extends StatelessWidget {
  const _PortfolioView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: BlocBuilder<PortfolioBloc, PortfolioState>(
          builder: (context, state) {
            final addr = state.walletAddress;
            final display =
                addr != null && addr.length > 8 ? '${addr.substring(0, 4)}...${addr.substring(addr.length - 4)}' : (addr ?? '');
            return Row(
              children: [
                const Text('Portfolio'),
                if (display.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(
                    display,
                    style: const TextStyle(fontSize: 12, color: AppTheme.colorTextSecondary),
                  ),
                ],
              ],
            );
          },
        ),
        actions: [
          BlocBuilder<PortfolioBloc, PortfolioState>(
            builder: (context, state) {
              final bloc = context.read<PortfolioBloc>();
              final hasApiKey = state.hasApiKey;
              return PopupMenuButton<String>(
                icon: const Icon(Icons.menu, color: AppTheme.colorTextMain),
                color: AppTheme.colorBgElevated,
                onSelected: (v) {
                  if (v == 'logout') {
                    bloc.add(const PortfolioEvent.logout());
                  } else if (v == 'login') {
                    bloc.add(const PortfolioEvent.connectWallet());
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: hasApiKey ? 'logout' : 'login',
                    child: Text(hasApiKey ? 'Logout' : 'Login'),
                  ),
                ],
              );
            },
          ),
        ],
      ),
      body: BlocBuilder<PortfolioBloc, PortfolioState>(
        builder: (context, state) {
          final bloc = context.read<PortfolioBloc>();
          return RefreshIndicator(
            onRefresh: () async {
              bloc.add(const PortfolioEvent.refreshBalances());
              bloc.add(const PortfolioEvent.refreshPositions());
              bloc.add(const PortfolioEvent.refreshOrders());
            },
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _EquitySection(
                  equityText: _parseEquity(state.balancesText),
                  onDeposit: () => ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('Deposit coming soon'))),
                  onWithdraw: () => ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('Withdraw coming soon'))),
                ),
                const SizedBox(height: 12),
                _Tabs(
                  selected: state.selectedTab,
                  onChanged: (i) => bloc.add(PortfolioEvent.selectTab(i)),
                ),
                const SizedBox(height: 12),
                if (state.selectedTab == 0) ...[
                  if (state.hasApiKey)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Text('Update mode:'),
                              const SizedBox(width: 8),
                              DropdownButton<String>(
                                value: state.positionUpdateMode,
                                selectedItemBuilder: (ctx) => [
                                  const Text('Normal'),
                                  const Text('Fast'),
                                ],
                                items: const [
                                  DropdownMenuItem(
                                    value: 'websocket',
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Normal'),
                                        SizedBox(height: 2),
                                        Text(
                                          'Lighter; might miss very fast ticks',
                                          style: TextStyle(color: AppTheme.colorTextSecondary, fontSize: 12),
                                        ),
                                      ],
                                    ),
                                  ),
                                  DropdownMenuItem(
                                    value: 'polling',
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Fast'),
                                        SizedBox(height: 2),
                                        Text(
                                          'More updates; higher data usage',
                                          style: TextStyle(color: AppTheme.colorTextSecondary, fontSize: 12),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                onChanged: (v) {
                                  if (v != null) bloc.add(PortfolioEvent.setUpdateMode(v));
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Text('PNL price:'),
                              const SizedBox(width: 8),
                              DropdownButton<String>(
                                value: _pnlDropdownValue(state.pnlPriceType),
                                selectedItemBuilder: (ctx) => const [
                                  Text('Mark'),
                                  Text('Mid'),
                                ],
                                items: const [
                                  DropdownMenuItem(
                                    value: 'MARK',
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Mark'),
                                        SizedBox(height: 2),
                                        Text(
                                          'Use mark price for PnL/ROE',
                                          style: TextStyle(color: AppTheme.colorTextSecondary, fontSize: 12),
                                        ),
                                      ],
                                    ),
                                  ),
                                  DropdownMenuItem(
                                    value: 'MID',
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Mid'),
                                        SizedBox(height: 2),
                                        Text(
                                          'Use mid price for PnL/ROE',
                                          style: TextStyle(color: AppTheme.colorTextSecondary, fontSize: 12),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                onChanged: (v) {
                                  if (v != null) bloc.add(PortfolioEvent.setPnlPriceType(v));
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  _PositionsListLegacyUI(positions: state.positions),
                ]
                else if (state.selectedTab == 1)
                  _OrdersList(orders: state.orders)
                else
                  _ClosedList(items: state.closedPositions),
                if (state.error != null) ...[
                  const SizedBox(height: 12),
                  Text(state.error!, style: const TextStyle(color: AppTheme.colorLoss)),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.state, required this.onConnect});

  final PortfolioState state;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final addr = state.walletAddress;
    final display = addr != null && addr.length > 8 ? '${addr.substring(0, 4)}...${addr.substring(addr.length - 4)}' : (addr ?? '');
    return Row(
      children: [
        const Text(
          'Portfolio',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: AppTheme.colorTextMain,
          ),
        ),
        const SizedBox(width: 8),
        if (display.isNotEmpty)
          Text(
            display,
            style: const TextStyle(
              color: AppTheme.colorTextSecondary,
              fontSize: 12,
            ),
          ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppTheme.colorBgElevated,
        foregroundColor: AppTheme.colorTextMain,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      onPressed: onTap,
      icon: Icon(icon),
      label: Text(label),
    );
  }
}

class _EquitySection extends StatelessWidget {
  const _EquitySection({required this.equityText, required this.onDeposit, required this.onWithdraw});

  final String equityText;
  final VoidCallback onDeposit;
  final VoidCallback onWithdraw;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Text(
          'Equity',
          style: TextStyle(color: AppTheme.colorTextSecondary, fontSize: 13, fontWeight: FontWeight.w400),
        ),
        const SizedBox(height: 6),
        Text(
          equityText,
          style: const TextStyle(color: AppTheme.colorTextMain, fontSize: 28, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _ActionButton(icon: Icons.arrow_downward, label: 'Deposit', onTap: onDeposit),
            const SizedBox(width: 16),
            _ActionButton(icon: Icons.arrow_upward, label: 'Withdraw', onTap: onWithdraw),
          ],
        ),
      ],
    );
  }
}

class _BalancesDetailsCard extends StatelessWidget {
  const _BalancesDetailsCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(text.isEmpty ? 'Balance: 0\nEquity: 0\nAvailable: 0' : text),
      ),
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs({required this.selected, required this.onChanged});

  final int selected;
  final void Function(int) onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _tab('Positions', 0),
        _tab('Orders', 1),
        _tab('Closed', 2),
      ],
    );
  }

  Widget _tab(String label, int idx) {
    final isSelected = selected == idx;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(idx),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.colorBgElevated : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(child: Text(label)),
        ),
      ),
    );
  }
}

class _PositionsList extends StatelessWidget {
  const _PositionsList({required this.positions});

  final List<Map<String, dynamic>> positions;

  @override
  Widget build(BuildContext context) {
    if (positions.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Text('No positions'),
        ),
      );
    }
    return Card(
      child: Column(
        children: positions
            .map(
              (p) {
                final market = p['market']?.toString() ?? '';
                final sizeVal = p['size'];
                final sideVal = p['side']?.toString().toUpperCase() ??
                    (sizeVal is num
                        ? (sizeVal >= 0 ? 'LONG' : 'SHORT')
                        : 'LONG');
                final absSize = sizeVal is num ? sizeVal.abs().toDouble() : 0.0;
                final pnl = p['pnl'] ?? p['pnl_usd'] ?? '';
                final entryPrice = _tryParseNum(p['entryPrice'] ?? p['entry_price']);
                final markPrice = _tryParseNum(p['markPrice'] ?? p['mark_price'] ?? p['mark'])?.toDouble();
                return Column(
                  children: [
                    ListTile(
                      title: Text(market),
                      subtitle: Text('Size: $absSize ($sideVal)   PnL: $pnl'),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                _showTpSlDialog(
                                  context,
                                  market,
                                  absSize,
                                  sideVal,
                                  markPrice: markPrice,
                                  entryPrice: entryPrice,
                                );
                              },
                              child: const Text('Add TP/SL'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton(
                              onPressed: () {
                                context.read<PortfolioBloc>().add(
                                      PortfolioEvent.closePositionAdvanced(
                                        market: market,
                                        qty: absSize,
                                        side: sideVal,
                                      ),
                                    );
                              },
                              child: const Text('Close'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                  ],
                );
              },
            )
            .toList(),
      ),
    );
  }

  void _showTpSlDialog(BuildContext context, String market, double size, String side,
      {double? markPrice, double? entryPrice}) {
    final qtyController = TextEditingController(text: size.toString());
    final tpTriggerController = TextEditingController();
    final tpTargetController = TextEditingController();
    final tpPriceController = TextEditingController();
    final tpTriggerType = ValueNotifier<String>('INDEX'); // legacy default
    final tpPriceType = ValueNotifier<String>('LIMIT');
    final tpTargetMode = ValueNotifier<String>('ROI'); // ROI or PnL

    final slTriggerController = TextEditingController();
    final slTargetController = TextEditingController(text: '-');
    final slPriceController = TextEditingController();
    final slTriggerType = ValueNotifier<String>('INDEX'); // legacy default
    final slPriceType = ValueNotifier<String>('LIMIT');
    final slTargetMode = ValueNotifier<String>('PnL'); // PnL or Price
    final partialPercent = ValueNotifier<double>(100.0);

    final oppositeSide = side == 'LONG' ? 'SELL' : 'BUY';
    final isLong = side == 'LONG';
    final notional = entryPrice != null ? entryPrice * size : null;

    double? tpTriggerPriceValue;
    double? tpPnlValue;
    double? tpRoiValue;
    double? slTriggerPriceValue;
    double? slPnlValue;
    bool tpSideError = false;
    bool tpError = false;
    bool slSideError = false;
    bool slError = false;

    double markNum() => markPrice ?? 0;
    double? pnlFromPrice(double? trigger) {
      if (entryPrice == null || trigger == null) return null;
      return isLong ? (trigger - entryPrice) * size : (entryPrice - trigger) * size;
    }

    double? priceFromPnl(double pnl) {
      if (entryPrice == null || size == 0) return null;
      return isLong ? entryPrice + (pnl / size) : entryPrice - (pnl / size);
    }

    void updateTpFromPrice(String value, void Function(void Function()) setState) {
      setState(() {
        if (value.isEmpty) {
          tpTriggerPriceValue = null;
          tpPnlValue = null;
          tpRoiValue = null;
          tpTargetController.text = '';
          tpSideError = false;
          tpError = false;
          return;
        }
        final price = double.tryParse(value);
        tpTriggerPriceValue = price;
        tpPnlValue = pnlFromPrice(price);
        tpRoiValue = (tpPnlValue != null && notional != null && notional > 0) ? (tpPnlValue! / notional) * 100 : null;
        tpError = price != null && price <= 0;
        if (price != null && markPrice != null) {
          tpSideError = isLong ? price <= markNum() : price >= markNum();
        } else {
          tpSideError = false;
        }
        if (tpTargetMode.value == 'ROI' && tpRoiValue != null) {
          tpTargetController.text = tpRoiValue!.toStringAsFixed(2);
        } else if (tpTargetMode.value == 'PnL' && tpPnlValue != null) {
          tpTargetController.text = tpPnlValue!.toStringAsFixed(2);
        } else {
          tpTargetController.text = '';
        }
      });
    }

    void updateTpFromTarget(String value, void Function(void Function()) setState) {
      setState(() {
        if (value.isEmpty) {
          tpTriggerPriceValue = null;
          tpPnlValue = null;
          tpRoiValue = null;
          tpTriggerController.text = '';
          return;
        }
        final input = double.tryParse(value);
        if (input == null) return;
        if (tpTargetMode.value == 'ROI') {
          tpRoiValue = input;
          if (notional != null) {
            tpPnlValue = notional * input / 100;
            tpTriggerPriceValue = priceFromPnl(tpPnlValue!);
          }
        } else {
          tpPnlValue = input;
          tpRoiValue = (notional != null && notional > 0) ? (input / notional) * 100 : null;
          tpTriggerPriceValue = priceFromPnl(input);
        }
        if (tpTriggerPriceValue != null) {
          tpTriggerController.text = tpTriggerPriceValue!.toStringAsFixed(4);
        }
        tpError = tpTriggerPriceValue != null && tpTriggerPriceValue! <= 0;
        if (tpTriggerPriceValue != null && markPrice != null) {
          tpSideError = isLong ? tpTriggerPriceValue! <= markNum() : tpTriggerPriceValue! >= markNum();
        } else {
          tpSideError = false;
        }
      });
    }

    void updateSlFromPrice(String value, void Function(void Function()) setState) {
      setState(() {
        if (value.isEmpty) {
          slTriggerPriceValue = null;
          slPnlValue = null;
          slTargetController.text = '';
          slSideError = false;
          slError = false;
          return;
        }
        final price = double.tryParse(value);
        slTriggerPriceValue = price;
        slPnlValue = pnlFromPrice(price);
        slError = price != null && price <= 0;
        if (price != null && markPrice != null) {
          slSideError = isLong ? price >= markNum() : price <= markNum();
        } else {
          slSideError = false;
        }
        if (slTargetMode.value == 'PnL' && slPnlValue != null) {
          slTargetController.text = slPnlValue!.toStringAsFixed(2);
        } else if (slTargetMode.value == 'Price' && price != null) {
          slTargetController.text = price.toStringAsFixed(4);
        } else {
          slTargetController.text = '';
        }
      });
    }

    void updateSlFromTarget(String value, void Function(void Function()) setState) {
      setState(() {
        if (value.isEmpty) {
          slTriggerPriceValue = null;
          slPnlValue = null;
          slPriceController.text = '';
          return;
        }
        final input = double.tryParse(value);
        if (input == null) return;
        if (slTargetMode.value == 'PnL') {
          slPnlValue = input;
          slTriggerPriceValue = priceFromPnl(input);
        } else {
          slTriggerPriceValue = input;
          slPnlValue = pnlFromPrice(input);
        }
        if (slTriggerPriceValue != null) {
          slPriceController.text = slTriggerPriceValue!.toStringAsFixed(4);
        }
        slError = slTriggerPriceValue != null && slTriggerPriceValue! <= 0;
        if (slTriggerPriceValue != null && markPrice != null) {
          slSideError = isLong ? slTriggerPriceValue! >= markNum() : slTriggerPriceValue! <= markNum();
        } else {
          slSideError = false;
        }
      });
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.colorBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          bool hasTp = (tpTriggerPriceValue != null && tpTriggerPriceValue! > 0) || (tpPnlValue != null);
          bool hasSl = (slTriggerPriceValue != null && slTriggerPriceValue! > 0) || (slPnlValue != null);
          bool slPositive = (slPnlValue ?? 0) > 0;
          return Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Add TP/SL - $market', style: const TextStyle(color: AppTheme.colorTextMain, fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: qtyController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Quantity'),
                  ),
                  const SizedBox(height: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Partial (%)', style: TextStyle(color: AppTheme.colorTextSecondary)),
                      ValueListenableBuilder<double>(
                        valueListenable: partialPercent,
                        builder: (context, pct, _) {
                          return Slider(
                            value: pct,
                            min: 0,
                            max: 100,
                            divisions: 20,
                            label: '${pct.toStringAsFixed(0)}%',
                            onChanged: (v) {
                              partialPercent.value = v;
                              final qty = size * (v / 100.0);
                              qtyController.text = qty.toStringAsFixed(6);
                            },
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text('Take Profit', style: TextStyle(color: AppTheme.colorTextMain, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: tpTriggerController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'TP Trigger Price'),
                          onChanged: (v) => updateTpFromPrice(v, setState),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _dropdown('Trigger', tpTriggerType, ['LAST', 'MARK', 'INDEX']),
                    ],
                  ),
                  if (tpSideError)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text('TP trigger would fill immediately; adjust price',
                          style: TextStyle(color: AppTheme.colorLoss)),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: tpTargetController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(labelText: tpTargetMode.value == 'ROI' ? 'ROI (%)' : 'PnL (USD)'),
                          onChanged: (v) => updateTpFromTarget(v, setState),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _dropdown('Target', tpTargetMode, ['ROI', 'PnL']),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: tpPriceController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'TP Execution Price'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _dropdown('Exec', tpPriceType, ['LIMIT', 'MARKET']),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text('Stop Loss', style: TextStyle(color: AppTheme.colorTextMain, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: slTriggerController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'SL Trigger Price'),
                          onChanged: (v) => updateSlFromPrice(v, setState),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _dropdown('Trigger', slTriggerType, ['LAST', 'MARK', 'INDEX']),
                    ],
                  ),
                  if (slSideError)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text('SL trigger would fill immediately; adjust price',
                          style: TextStyle(color: AppTheme.colorLoss)),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: slTargetController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(labelText: slTargetMode.value == 'PnL' ? 'PnL (USD)' : 'Price'),
                          onChanged: (v) => updateSlFromTarget(v, setState),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _dropdown('Mode', slTargetMode, ['PnL', 'Price']),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: slPriceController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'SL Execution Price'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _dropdown('Exec', slPriceType, ['LIMIT', 'MARKET']),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (entryPrice != null)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (tpPnlValue != null) Text('TP est. PnL: ${tpPnlValue!.toStringAsFixed(2)}', style: const TextStyle(color: AppTheme.colorTextMain)),
                        if (tpRoiValue != null) Text('TP est. ROI: ${tpRoiValue!.toStringAsFixed(2)}%', style: const TextStyle(color: AppTheme.colorTextSecondary)),
                        if (slPnlValue != null)
                          Text(
                            'SL est. PnL: ${slPnlValue!.toStringAsFixed(2)}${slPositive ? ' (positive)' : ''}',
                            style: TextStyle(color: slPositive ? AppTheme.colorLoss : AppTheme.colorTextMain),
                          ),
                        if (markPrice != null) Text('Mark: ${markPrice.toStringAsFixed(4)}', style: const TextStyle(color: AppTheme.colorTextSecondary)),
                      ],
                    ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () {
                        final qty = double.tryParse(qtyController.text) ?? size;
                        final tpTrigger = tpTriggerPriceValue ?? double.tryParse(tpTriggerController.text);
                        final tpPrice = double.tryParse(tpPriceController.text);
                        final slTrigger = slTriggerPriceValue ?? double.tryParse(slTriggerController.text);
                        final slPrice = double.tryParse(slPriceController.text);

                        final hasTp2 = tpTrigger != null || tpPrice != null;
                        final hasSl2 = slTrigger != null || slPrice != null;
                        if (!hasTp2 && !hasSl2) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Enter TP or SL values')),
                          );
                          return;
                        }
                        if (qty <= 0) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Invalid quantity')),
                          );
                          return;
                        }
                        if (tpSideError) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('TP would fill immediately; adjust price/side')),
                          );
                          return;
                        }
                        if (slSideError) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('SL would fill immediately; adjust price/side')),
                          );
                          return;
                        }
                        if (slPositive) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('SL yields positive PnL; adjust trigger')),
                          );
                          return;
                        }
                    if (markPrice != null) {
                          if (tpTrigger != null) {
                            final badTp = isLong ? tpTrigger <= markPrice : tpTrigger >= markPrice;
                            if (badTp) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('TP trigger would fill immediately; adjust price')),
                              );
                              return;
                            }
                          }
                          if (slTrigger != null) {
                            final badSl = isLong ? slTrigger >= markPrice : slTrigger <= markPrice;
                            if (badSl) {
                              ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('SL trigger would fill immediately; adjust price')),
                              );
                              return;
                            }
                          }
                        }

                        context.read<PortfolioBloc>().add(PortfolioEvent.addTpSl(
                              market: market,
                              qty: qty,
                              side: oppositeSide,
                              tpTrigger: tpTrigger,
                              tpTriggerType: tpTriggerType.value,
                              tpPrice: tpPrice,
                              tpPriceType: tpPriceType.value,
                              slTrigger: slTrigger,
                              slTriggerType: slTriggerType.value,
                              slPrice: slPrice,
                              slPriceType: slPriceType.value,
                            ));
                        Navigator.pop(ctx);
                      },
                      child: const Text('Submit TP/SL'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _dropdown(String label, ValueNotifier<String> controller, List<String> options) {
    return ValueListenableBuilder<String>(
      valueListenable: controller,
      builder: (context, value, _) {
        return PopupMenuButton<String>(
          onSelected: (v) => controller.value = v,
          itemBuilder: (_) => options
              .map((o) => PopupMenuItem<String>(
                    value: o,
                    child: Text(o),
                  ))
              .toList(),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.colorBgElevated,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('$label: $value', style: const TextStyle(color: AppTheme.colorTextMain)),
                const Icon(Icons.arrow_drop_down, color: AppTheme.colorTextSecondary),
              ],
            ),
          ),
        );
      },
    );
  }

  double? _tryParseNum(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }
}

String _parseEquity(String balancesText) {
  if (balancesText.isEmpty) return '\$0.00';
  try {
    final match = RegExp(r'Equity:\s*([\d.,]+)').firstMatch(balancesText);
    if (match != null) {
      final value = double.tryParse(match.group(1)!.replaceAll(',', '')) ?? 0.0;
      return '\$${value.toStringAsFixed(2)}';
    }
  } catch (_) {}
  return '\$0.00';
}

String _pnlDropdownValue(String value) {
  final upper = value.toUpperCase();
  if (upper == 'MARK' || upper == 'MARKPRICE') return 'MARK';
  if (upper == 'MID' || upper == 'MIDPRICE') return 'MID';
  return 'MARK';
}

class _PositionsListLegacyUI extends StatelessWidget {
  const _PositionsListLegacyUI({required this.positions});

  final List<Map<String, dynamic>> positions;

  @override
  Widget build(BuildContext context) {
    if (positions.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Text('No positions'),
        ),
      );
    }

    return Column(
      children: positions.map((p) {
        final market = p['market']?.toString() ?? '';
        final sizeVal = p['size'];
        final sideVal =
            p['side']?.toString().toUpperCase() ?? (sizeVal is num ? (sizeVal >= 0 ? 'LONG' : 'SHORT') : 'LONG');
        final absSize = sizeVal is num ? sizeVal.abs().toDouble() : 0.0;
        final entryPrice = _tryParseNum(p['entryPrice'] ?? p['entry_price'])?.toDouble();
        final markPrice = _tryParseNum(p['markPrice'] ?? p['mark_price'] ?? p['mark'])?.toDouble();
        final liqPrice = _tryParseNum(p['liquidationPrice'] ?? p['liquidation_price'])?.toDouble();
        final pnl = _tryParseNum(p['pnl'] ?? p['pnl_usd'] ?? p['unrealisedPnl'] ?? p['unrealisedPnlUsd']);
        final pnlPct = _tryParseNum(p['pnlPct'] ?? p['pnl_pct'] ?? p['unrealisedRoePnlPct'] ?? p['roe']);
        final leverage = p['leverage']?.toString();
        final notional = _tryParseNum(p['notional'] ?? p['notionalUsd'] ?? p['positionValue']);
        final unrealised = _tryParseNum(p['unrealisedPnl'] ?? p['unrealisedPnlUsd']);

        Color pnlColor(double? v) {
          if (v == null) return AppTheme.colorTextSecondary;
          if (v > 0) return AppTheme.colorGreenPrimary;
          if (v < 0) return AppTheme.colorLoss;
          return AppTheme.colorTextSecondary;
        }

        String fmtNum(num? v, {int decimals = 4}) {
          if (v == null) return '-';
          return v.toStringAsFixed(decimals);
        }

        return Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.colorBgElevated,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    market,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.colorTextMain,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: sideVal == 'LONG'
                          ? AppTheme.colorGreenPrimary.withOpacity(0.12)
                          : AppTheme.colorLoss.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      sideVal,
                      style: TextStyle(
                        color: sideVal == 'LONG' ? AppTheme.colorGreenPrimary : AppTheme.colorLoss,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (leverage != null && leverage.isNotEmpty)
                    Text(
                      '${leverage}x',
                      style: const TextStyle(color: AppTheme.colorTextSecondary),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _metric('Size', absSize.toStringAsFixed(4)),
                  _metric('Entry', fmtNum(entryPrice)),
                  _metric('Mark', fmtNum(markPrice)),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  _metric('Liq.', fmtNum(liqPrice)),
                  _metric('Value', fmtNum(notional)),
                  _metric('Mode', p['marginMode']?.toString() ?? '-'),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('PnL', style: TextStyle(color: AppTheme.colorTextSecondary, fontSize: 12)),
                        Text(
                          '${fmtNum(pnl, decimals: 2)} ${pnlPct != null ? '(${fmtNum(pnlPct, decimals: 2)}%)' : ''}',
                          style: TextStyle(
                            color: pnlColor(pnl),
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (unrealised != null)
                    Text(
                      'Unrealised: ${fmtNum(unrealised, decimals: 2)}',
                      style: const TextStyle(color: AppTheme.colorTextSecondary, fontSize: 12),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        _showTpSlDialog(
                          context,
                          market,
                          absSize,
                          sideVal,
                          markPrice: markPrice,
                          entryPrice: entryPrice,
                        );
                      },
                      child: const Text('Add TP/SL'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        context.read<PortfolioBloc>().add(
                              PortfolioEvent.closePositionAdvanced(
                                market: market,
                                qty: absSize,
                                side: sideVal,
                              ),
                            );
                      },
                      child: const Text('Close'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

Widget _metric(String label, String value) {
  return Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: AppTheme.colorTextSecondary, fontSize: 12)),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(color: AppTheme.colorTextMain, fontWeight: FontWeight.w600),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    ),
  );
}


Widget _dropdown(String label, ValueNotifier<String> controller, List<String> options) {
  return ValueListenableBuilder<String>(
    valueListenable: controller,
    builder: (context, value, _) {
      return PopupMenuButton<String>(
        onSelected: (v) => controller.value = v,
        itemBuilder: (_) => options
            .map((o) => PopupMenuItem<String>(
                  value: o,
                  child: Text(o),
                ))
            .toList(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.colorBgElevated,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('$label: $value', style: const TextStyle(color: AppTheme.colorTextMain)),
              const Icon(Icons.arrow_drop_down, color: AppTheme.colorTextSecondary),
            ],
          ),
        ),
      );
    },
  );
}

double? _tryParseNum(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}


void _showTpSlDialog(
  BuildContext context,
  String market,
  double size,
  String side, {
  double? markPrice,
  double? entryPrice,
}) {
  final qtyController = TextEditingController(text: size.toString());
  final tpTriggerController = TextEditingController();
  final tpTargetController = TextEditingController();
  final tpPriceController = TextEditingController();
  final tpTriggerType = ValueNotifier<String>('INDEX'); // legacy default
  final tpPriceType = ValueNotifier<String>('LIMIT');
  final tpTargetMode = ValueNotifier<String>('ROI'); // ROI or PnL

  final slTriggerController = TextEditingController();
  final slTargetController = TextEditingController(text: '-');
  final slPriceController = TextEditingController();
  final slTriggerType = ValueNotifier<String>('INDEX'); // legacy default
  final slPriceType = ValueNotifier<String>('LIMIT');
  final slTargetMode = ValueNotifier<String>('PnL'); // PnL or Price
  final partialPercent = ValueNotifier<double>(100.0);

  final oppositeSide = side == 'LONG' ? 'SELL' : 'BUY';
  final isLong = side == 'LONG';
  final notional = entryPrice != null ? entryPrice * size : null;

  double? tpTriggerPriceValue;
  double? tpPnlValue;
  double? tpRoiValue;
  double? slTriggerPriceValue;
  double? slPnlValue;
  bool tpSideError = false;
  bool tpError = false;
  bool slSideError = false;
  bool slError = false;

  double markNum() => markPrice ?? 0;
  double? pnlFromPrice(double? trigger) {
    if (entryPrice == null || trigger == null) return null;
    return isLong ? (trigger - entryPrice) * size : (entryPrice - trigger) * size;
  }

  double? priceFromPnl(double pnl) {
    if (entryPrice == null || size == 0) return null;
    return isLong ? entryPrice + (pnl / size) : entryPrice - (pnl / size);
  }

  void updateTpFromPrice(String value, void Function(void Function()) setState) {
    setState(() {
      if (value.isEmpty) {
        tpTriggerPriceValue = null;
        tpPnlValue = null;
        tpRoiValue = null;
        tpTargetController.text = '';
        tpSideError = false;
        tpError = false;
        return;
      }
      final price = double.tryParse(value);
      tpTriggerPriceValue = price;
      tpPnlValue = pnlFromPrice(price);
      tpRoiValue = (tpPnlValue != null && notional != null && notional > 0) ? (tpPnlValue! / notional) * 100 : null;
      tpError = price != null && price <= 0;
      if (price != null && markPrice != null) {
        tpSideError = isLong ? price <= markNum() : price >= markNum();
      } else {
        tpSideError = false;
      }
      if (tpTargetMode.value == 'ROI' && tpRoiValue != null) {
        tpTargetController.text = tpRoiValue!.toStringAsFixed(2);
      } else if (tpTargetMode.value == 'PnL' && tpPnlValue != null) {
        tpTargetController.text = tpPnlValue!.toStringAsFixed(2);
      } else {
        tpTargetController.text = '';
      }
    });
  }

  void updateTpFromTarget(String value, void Function(void Function()) setState) {
    setState(() {
      if (value.isEmpty) {
        tpTriggerPriceValue = null;
        tpPnlValue = null;
        tpRoiValue = null;
        tpTriggerController.text = '';
        return;
      }
      final input = double.tryParse(value);
      if (input == null) return;
      if (tpTargetMode.value == 'ROI') {
        tpRoiValue = input;
        if (notional != null) {
          tpPnlValue = notional * input / 100;
          tpTriggerPriceValue = priceFromPnl(tpPnlValue!);
        }
      } else {
        tpPnlValue = input;
        tpRoiValue = (notional != null && notional > 0) ? (input / notional) * 100 : null;
        tpTriggerPriceValue = priceFromPnl(input);
      }
      if (tpTriggerPriceValue != null) {
        tpTriggerController.text = tpTriggerPriceValue!.toStringAsFixed(4);
      }
      tpError = tpTriggerPriceValue != null && tpTriggerPriceValue! <= 0;
      if (tpTriggerPriceValue != null && markPrice != null) {
        tpSideError = isLong ? tpTriggerPriceValue! <= markNum() : tpTriggerPriceValue! >= markNum();
      } else {
        tpSideError = false;
      }
    });
  }

  void updateSlFromPrice(String value, void Function(void Function()) setState) {
    setState(() {
      if (value.isEmpty) {
        slTriggerPriceValue = null;
        slPnlValue = null;
        slTargetController.text = '';
        slSideError = false;
        slError = false;
        return;
      }
      final price = double.tryParse(value);
      slTriggerPriceValue = price;
      slPnlValue = pnlFromPrice(price);
      slError = price != null && price <= 0;
      if (price != null && markPrice != null) {
        slSideError = isLong ? price >= markNum() : price <= markNum();
      } else {
        slSideError = false;
      }
      if (slTargetMode.value == 'PnL' && slPnlValue != null) {
        slTargetController.text = slPnlValue!.toStringAsFixed(2);
      } else if (slTargetMode.value == 'Price' && price != null) {
        slTargetController.text = price.toStringAsFixed(4);
      } else {
        slTargetController.text = '';
      }
    });
  }

  void updateSlFromTarget(String value, void Function(void Function()) setState) {
    setState(() {
      if (value.isEmpty) {
        slTriggerPriceValue = null;
        slPnlValue = null;
        slPriceController.text = '';
        return;
      }
      final input = double.tryParse(value);
      if (input == null) return;
      if (slTargetMode.value == 'PnL') {
        slPnlValue = input;
        slTriggerPriceValue = priceFromPnl(input);
      } else {
        slTriggerPriceValue = input;
        slPnlValue = pnlFromPrice(input);
      }
      if (slTriggerPriceValue != null) {
        slPriceController.text = slTriggerPriceValue!.toStringAsFixed(4);
      }
      slError = slTriggerPriceValue != null && slTriggerPriceValue! <= 0;
      if (slTriggerPriceValue != null && markPrice != null) {
        slSideError = isLong ? slTriggerPriceValue! >= markNum() : slTriggerPriceValue! <= markNum();
      } else {
        slSideError = false;
      }
    });
  }

  showModalBottomSheet(
    context: context,
    backgroundColor: AppTheme.colorBg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        bool hasTp = (tpTriggerPriceValue != null && tpTriggerPriceValue! > 0) || (tpPnlValue != null);
        bool hasSl = (slTriggerPriceValue != null && slTriggerPriceValue! > 0) || (slPnlValue != null);
        bool slPositive = (slPnlValue ?? 0) > 0;
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Add TP/SL - $market',
                    style: const TextStyle(color: AppTheme.colorTextMain, fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                TextField(
                  controller: qtyController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Quantity'),
                ),
                const SizedBox(height: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Partial (%)', style: TextStyle(color: AppTheme.colorTextSecondary)),
                    ValueListenableBuilder<double>(
                      valueListenable: partialPercent,
                      builder: (context, pct, _) {
                        return Slider(
                          value: pct,
                          min: 0,
                          max: 100,
                          divisions: 20,
                          label: '${pct.toStringAsFixed(0)}%',
                          onChanged: (v) {
                            partialPercent.value = v;
                            final qty = size * (v / 100.0);
                            qtyController.text = qty.toStringAsFixed(6);
                          },
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text('Take Profit', style: TextStyle(color: AppTheme.colorTextMain, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: tpTriggerController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'TP Trigger Price'),
                        onChanged: (v) => updateTpFromPrice(v, setState),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _dropdown('Trigger', tpTriggerType, ['LAST', 'MARK', 'INDEX']),
                  ],
                ),
                if (tpSideError)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text('TP trigger would fill immediately; adjust price',
                        style: TextStyle(color: AppTheme.colorLoss)),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: tpTargetController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration:
                            InputDecoration(labelText: tpTargetMode.value == 'ROI' ? 'ROI (%)' : 'PnL (USD)'),
                        onChanged: (v) => updateTpFromTarget(v, setState),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _dropdown('Target', tpTargetMode, ['ROI', 'PnL']),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: tpPriceController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'TP Execution Price'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _dropdown('Exec', tpPriceType, ['LIMIT', 'MARKET']),
                  ],
                ),
                const SizedBox(height: 12),
                const Text('Stop Loss', style: TextStyle(color: AppTheme.colorTextMain, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: slTriggerController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'SL Trigger Price'),
                        onChanged: (v) => updateSlFromPrice(v, setState),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _dropdown('Trigger', slTriggerType, ['LAST', 'MARK', 'INDEX']),
                  ],
                ),
                if (slSideError)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text('SL trigger would fill immediately; adjust price',
                        style: TextStyle(color: AppTheme.colorLoss)),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: slTargetController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                            labelText: slTargetMode.value == 'PnL' ? 'PnL (USD)' : 'Price'),
                        onChanged: (v) => updateSlFromTarget(v, setState),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _dropdown('Mode', slTargetMode, ['PnL', 'Price']),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: slPriceController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'SL Execution Price'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _dropdown('Exec', slPriceType, ['LIMIT', 'MARKET']),
                  ],
                ),
                const SizedBox(height: 16),
                if (entryPrice != null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (tpPnlValue != null)
                        Text('TP est. PnL: ${tpPnlValue!.toStringAsFixed(2)}',
                            style: const TextStyle(color: AppTheme.colorTextMain)),
                      if (tpRoiValue != null)
                        Text('TP est. ROI: ${tpRoiValue!.toStringAsFixed(2)}%',
                            style: const TextStyle(color: AppTheme.colorTextSecondary)),
                      if (slPnlValue != null)
                        Text(
                          'SL est. PnL: ${slPnlValue!.toStringAsFixed(2)}${(slPnlValue ?? 0) > 0 ? ' (positive)' : ''}',
                          style: TextStyle(
                            color: (slPnlValue ?? 0) > 0 ? AppTheme.colorLoss : AppTheme.colorTextMain,
                          ),
                        ),
                      if (markPrice != null)
                        Text('Mark: ${markPrice.toStringAsFixed(4)}',
                            style: const TextStyle(color: AppTheme.colorTextSecondary)),
                    ],
                  ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      final qty = double.tryParse(qtyController.text) ?? size;
                      final tpTrigger = tpTriggerPriceValue ?? double.tryParse(tpTriggerController.text);
                      final tpPrice = double.tryParse(tpPriceController.text);
                      final slTrigger = slTriggerPriceValue ?? double.tryParse(slTriggerController.text);
                      final slPrice = double.tryParse(slPriceController.text);

                      final hasTp2 = tpTrigger != null || tpPrice != null;
                      final hasSl2 = slTrigger != null || slPrice != null;
                      if (!hasTp2 && !hasSl2) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Enter TP or SL values')),
                        );
                        return;
                      }
                      if (qty <= 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Invalid quantity')),
                        );
                        return;
                      }
                      if (tpSideError) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('TP would fill immediately; adjust price/side')),
                        );
                        return;
                      }
                      if (slSideError) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('SL would fill immediately; adjust price/side')),
                        );
                        return;
                      }
                      if ((slPnlValue ?? 0) > 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('SL yields positive PnL; adjust trigger')),
                        );
                        return;
                      }
                      if (markPrice != null) {
                        if (tpTrigger != null) {
                          final badTp = isLong ? tpTrigger <= markPrice : tpTrigger >= markPrice;
                          if (badTp) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('TP trigger would fill immediately; adjust price')),
                            );
                            return;
                          }
                        }
                        if (slTrigger != null) {
                          final badSl = isLong ? slTrigger >= markPrice : slTrigger <= markPrice;
                          if (badSl) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('SL trigger would fill immediately; adjust price')),
                            );
                            return;
                          }
                        }
                      }

                      double qtyToSend = qty;
                      if (partialPercent.value < 100) {
                        qtyToSend = size * (partialPercent.value / 100.0);
                      }

                      Navigator.of(context).pop();
                      context.read<PortfolioBloc>().add(
                            PortfolioEvent.addTpSl(
                              market: market,
                              qty: qtyToSend,
                              side: oppositeSide,
                              tpTrigger: tpTrigger,
                              tpTriggerType: tpTriggerType.value,
                              tpPrice: tpPrice,
                              tpPriceType: tpPriceType.value,
                              slTrigger: slTrigger,
                              slTriggerType: slTriggerType.value,
                              slPrice: slPrice,
                              slPriceType: slPriceType.value,
                            ),
                          );
                    },
                    child: const Text('Submit'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class _OrdersList extends StatelessWidget {
  const _OrdersList({required this.orders});

  final List<Map<String, dynamic>> orders;

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Text('No orders'),
        ),
      );
    }
    return Card(
      child: Column(
        children: orders
            .map(
              (o) => ListTile(
                title: Text(o['market']?.toString() ?? 'Market'),
                subtitle: Text('Status: ${o['status'] ?? ''}  Size: ${o['size'] ?? ''}'),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _ClosedList extends StatelessWidget {
  const _ClosedList({required this.items});

  final List<Map<String, dynamic>> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Text('No closed positions'),
        ),
      );
    }
    return Card(
      child: Column(
        children: items
            .map(
              (o) => ListTile(
                title: Text(o['market']?.toString() ?? 'Market'),
                subtitle: Text('PNL: ${o['pnl'] ?? ''}'),
              ),
            )
            .toList(),
      ),
    );
  }
}
