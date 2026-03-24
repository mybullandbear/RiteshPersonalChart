import 'dart:async';
import 'dart:math';
import 'dart:js' as js;
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'models/option_data.dart';
import 'services/api_service.dart';

void playAlertSound() {
  try {
    js.context.callMethod('eval', [
      """
      (function() {
        var ctx = new (window.AudioContext || window.webkitAudioContext)();
        var osc = ctx.createOscillator();
        var gain = ctx.createGain();
        osc.connect(gain);
        gain.connect(ctx.destination);
        osc.frequency.value = 880;
        osc.start();
        gain.gain.setValueAtTime(1, ctx.currentTime);
        gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + 0.4);
        osc.stop(ctx.currentTime + 0.4);
      })()
      """
    ]);
  } catch(e) {}
}

const _mono = TextStyle(fontFamily: 'monospace');

void main() => runApp(const NseApp());

class NseApp extends StatelessWidget {
  const NseApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'NSE Option Chain Pro',
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark().copyWith(
      scaffoldBackgroundColor: kBg,
    ),
    home: const TradingDashboard(),
  );
}

// ─── Cyber-Onyx Design System ───────────────────────────────
const kBg          = Color(0xFF020408); // Ultimate depth dark
const kAccent      = Color(0xFF00E5FF); // Electric Cyan
const kAccent2     = Color(0xFFD500F9); // Cyber Magenta
const kSurface     = Color(0xFF0D1117); 
const kSurface2    = Color(0xFF161B22);
const kGlass       = Color(0x1AFFFFFF); 
const kGlassHighlight = Color(0x33FFFFFF);
const kBorder      = Color(0xFF1F2937);
const kNifty       = Color(0xFF2196F3);
const kBank        = Color(0xFFFFB300);
const kGreen       = Color(0xFF00F59B); // High-viz neon green
const kRed         = Color(0xFFFF3D71); // Sharp vivid red
const kOrange      = Color(0xFFFFAB00);
const kGrey        = Color(0xFF8B949E);

final kGlassDecoration = BoxDecoration(
  color: kSurface.withOpacity(0.7),
  borderRadius: BorderRadius.circular(20),
  border: Border.all(color: Colors.white.withOpacity(0.1), width: 1.5),
  boxShadow: [
    BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 40, spreadRadius: -5),
  ],
);

// institutional typography defaults
const kHeaderStyle = TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.5, color: Colors.white);
const kSubStyle    = TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: kGrey, letterSpacing: 1.2);
const kMono        = TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold);

// ─── Dashboard ─────────────────────────────────────────────────
class TradingDashboard extends StatefulWidget {
  const TradingDashboard({super.key});
  @override
  State<TradingDashboard> createState() => _TradingDashboardState();
}

class _TradingDashboardState extends State<TradingDashboard> {
  final _api = ApiService();
  Timer? _timer;

  String? _selectedDate;
  List<String> _dates = [];

  // Phase-1: quick summary (loads in <1s)
  Map<String, QuickSummary> _summary = {};

  // Phase-2: OI chart data (loads in background)
  Map<String, List<OiStat>> _oiStats = {};
  Map<String, bool> _oiLoading = {'NIFTY': true, 'BANKNIFTY': true};

  String? _error;
  bool _initialLoading = true;
  bool _refreshing = false;
  DateTime _lastUpdated = DateTime.now();
  Timer? _streamTimer;
  bool _isAuthenticated = false;
  int _activeTabIndex = 0; // 0 = Market Pulse, 1 = Index Analytics
  bool _phase1Loading = false;
  Map<String, dynamic>? _mtfTrend;
  Future<Map<String, dynamic>>? _tradingStateFuture;
  Map<String, dynamic> _marketExtras = {};
  Map<String, List<dynamic>> _oiHistograms = {};
  Map<String, bool> _oiHistLoading = {};
  int _playbackMinutes = 930; // 930 = 15:30 (Live). 555 = 09:15.

  @override
  void initState() {
    super.initState();
    _tradingStateFuture = ApiService().getTradingState();
    
    // 🔒 Persistent Login Check
    try {
      final saved = html.window.localStorage['dashboard_auth'];
      if (saved == 'AUTHORIZED_OK') {
         _isAuthenticated = true;
         _boot();
      }
    } catch(e) {}
    // _boot() will run after login success
    // Real-Time Livestream (Auto-updating in background)
    _streamTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!_initialLoading && _selectedDate != null) {
        _phase1(); // Silently updates signals, PCR, and Spot Price
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _streamTimer?.cancel();
    super.dispose();
  }

  // ── Boot: get date list then fire phase 1 ──────────────────
  Future<void> _boot() async {
    try {
      final dates = await _api.getDates();
      if (dates.isEmpty) {
        setState(() { _initialLoading = false; _error = 'No data in database.'; });
        return;
      }
      setState(() { _dates = dates; _selectedDate = dates.first; });
      await _phase1();
      _phase2and3(); // fire in background without await
      _timer = Timer.periodic(const Duration(seconds: 60), (_) {
        _phase1();
        _phase2and3();
      });
    } catch (e) {
      setState(() {
        _initialLoading = false;
        _error = 'Cannot connect to backend at http://127.0.0.1:5000\n\nError: $e';
      });
    }
  }

  // ── Phase 1: Quick summary (< 1 s) ───────────────────────
  Future<void> _phase1() async {
    if (_phase1Loading) return;
    _phase1Loading = true;
    try {
      final String? timeStr = _playbackMinutes < 930 ? "${_playbackMinutes ~/ 60}:${(_playbackMinutes % 60).toString().padLeft(2, '0')}" : null;
      final s = await _api.getQuickSummary(_selectedDate, timeStr);
      try {
         final extras = await _api.getMarketExtras();
         _marketExtras = extras;
      } catch(_) {}
      
      for (final sym in s.keys) {
         final newSig = s[sym]?.signal ?? '';
         final oldSig = _summary[sym]?.signal ?? '';
         final notifyNewExit = s[sym]?.exitAlert != null && _summary[sym]?.exitAlert == null;
         
         if ((newSig != oldSig && (newSig.contains('BUY') || newSig.contains('SELL'))) || notifyNewExit) {
             playAlertSound();
         }
      }

      bool changed = _summary.isEmpty;
      if (!changed) {
         for (final sym in s.keys) {
            if (_summary[sym]?.spot != s[sym]?.spot || _summary[sym]?.signal != s[sym]?.signal) {
                changed = true;
                break;
            }
         }
      }

      if (changed) {
        setState(() {
          _summary = s;
          _initialLoading = false;
          _refreshing = false;
          _error = null; 
          _lastUpdated = DateTime.now();
        });
      } else {
         // Silently update timestamp without heavy layout rebuilds
         setState(() {
           _lastUpdated = DateTime.now();
         });
      }
    } catch (e) {
      if (mounted) {
        // 🤫 Silent fail for periodic updates so it doesn't break the UI with error screens
        if (_summary.isEmpty) {
          setState(() { _initialLoading = false; _error = 'Error: $e'; });
        } else {
          print("Stream Update Error (ignoring on loaded UI): $e");
        }
      }
    } finally {
      _phase1Loading = false;
    }
  }

  double _getCompositeScore(String sym) {
    final s = _summary[sym];
    if (s == null) return 50.0;
    
    // 1. Near-ATM PCR Sentiment Component (50%)
    double pcr = s.nearPcr ?? s.pcr;
    double pcrScore = (((pcr - 0.5) / 1.0) * 100.0).clamp(0.0, 100.0);
    
    // 2. Confluence Components & Signals (50%)
    double confScore = s.confluence.toDouble(); // 0 to 100
    final String sig = s.signal.toUpperCase();
    if (sig.contains('SELL')) {
      confScore = 100.0 - confScore; // Bearish, invert to map on low scale
    } else if (!sig.contains('BUY')) {
      confScore = 50.0; // Neutral 
    }
    
    return (pcrScore * 0.5) + (confScore * 0.5);
  }

  void _phase2and3() {
    final date = _selectedDate;
    if (date == null) return;

    _api.getMtfTrend().then((val) {
      if (mounted) setState(() => _mtfTrend = val);
    }).catchError((_) {});

    for (final sym in ['NIFTY', 'BANKNIFTY', 'FINNIFTY']) {
      setState(() { _oiLoading[sym] = true; _oiHistLoading[sym] = true; });

      final String? timeStr = _playbackMinutes < 930 ? "${_playbackMinutes ~/ 60}:${(_playbackMinutes % 60).toString().padLeft(2, '0')}" : null;

      // OI charts (we compute Max Pain now since you want visuals!)
      _api.getOiStats(sym, date, skipMaxPain: false, time: timeStr).then((oi) {
        if (mounted) setState(() { _oiStats[sym] = oi; _oiLoading[sym] = false; });
      }).catchError((_) {
        if (mounted) setState(() => _oiLoading[sym] = false);
      });
      
      _api.getOiHistograms(sym, date, timeStr).then((hist) {
        if (mounted) setState(() { _oiHistograms[sym] = hist; _oiHistLoading[sym] = false; });
      }).catchError((_) {
        if (mounted) setState(() => _oiHistLoading[sym] = false);
      });
    }
  }

  void _onDateChanged(String d) {
    setState(() {
      _selectedDate = d;
      _summary = {};
      _oiStats = {};
      _initialLoading = true;
    });
    _phase1().then((_) => _phase2and3());
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAuthenticated) {
       return _LoginScreen(onSuccess: () {
           setState(() { _isAuthenticated = true; });
           _boot();
       });
    }
    return Scaffold(
      backgroundColor: kBg,
      body: Stack(
        children: [
          // Background visual anchor (Atmospheric glow)
          Positioned(
            top: -200, right: -200,
            child: Container(
              width: 500, height: 500,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: kAccent.withOpacity(0.05),
              ),
            ),
          ),
          
          Column(children: [
            _Header(
              dates: _dates, selectedDate: _selectedDate,
              lastUpdated: _lastUpdated, refreshing: _refreshing,
              activeTabIndex: _activeTabIndex,
              playbackMinutes: _playbackMinutes,
              onPlaybackChanged: (v) => setState(() => _playbackMinutes = v),
              onPlaybackEnd: (v) { _refreshing = true; _phase1(); _phase2and3(); },
              onTabChanged: (i) => setState(() => _activeTabIndex = i),
              onDateChanged: _onDateChanged, onRefresh: () { _refreshing = true; _phase1(); _phase2and3(); },
            ),
            if (!_initialLoading && _error == null)
              _GlobalSignalsBar(summary: _summary),
            Expanded(child: _buildBody()),
            if (!_initialLoading && _error == null)
              _LogsPanel(api: _api),
          ]),
        ],
      ),
    );
  }

  Future<void> _exportToCSV() async {
    try {
       final history = await _api.getTradeHistory();
       if (history.isEmpty) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No trade history available to export.')));
          return;
       }
       
       String csv = 'Symbol,Type,Strike,Qty,Entry Price,Exit Price,Profit,Peak Profit,Entry Time,Exit Time,Reason,Snapshot Time\n';
       for (var row in history) {
          csv += '${row['symbol']},${row['type']},${row['strike']},${row['quantity']},${row['entry_price']},${row['exit_price']},${row['profit']},${row['highest_profit']},${row['entry_time']},${row['exit_time']},"${row['exit_reason']}","${row['snapshot_timestamp']}"\n';
       }
       
       final bytes = csv.codeUnits;
       final blob = html.Blob([bytes]);
       final url = html.Url.createObjectUrlFromBlob(blob);
       final anchor = html.AnchorElement(href: url)
         ..setAttribute("download", "trade_history_${DateTime.now().millisecondsSinceEpoch}.csv")
         ..click();
       html.Url.revokeObjectUrl(url);
    } catch (e) {
       if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export Failed: $e')));
    }
  }

  Widget _buildCommandHubTier() {
    return FutureBuilder<Map<String, dynamic>>(
      future: _tradingStateFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
           return const SizedBox(height: 300, child: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasError) {
           return SizedBox(height: 300, child: Center(child: Text('Error loading trading state:\n${snapshot.error}', style: const TextStyle(color: kRed))));
        }

        final state = snapshot.data!;
        final bool isPaper = state['paper_trading'] ?? true;
        final bool isAuto = state['trading_enabled'] ?? false;
        final Map<String, dynamic> positions = state['positions'] ?? {};

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('⚡ COMMAND CENTER', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white)),
              const SizedBox(height: 24),
              
              // Auto Trading Toggles
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(16)),
                child: Column(
                  children: [
                    SwitchListTile(
                      title: const Text('PAPER TRADING MODE', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber)),
                      subtitle: const Text('Simulate trades using local data instead of Zerodha', style: TextStyle(color: Colors.white54)),
                      value: isPaper,
                      activeColor: Colors.amber,
                      onChanged: (val) async {
                         await _api.toggleTradingConfig(paperTrading: val);
                         setState(() { _tradingStateFuture = _api.getTradingState(); });
                      }
                    ),
                    const Divider(color: Colors.white10),
                    SwitchListTile(
                      title: const Text('AUTO TRADING ALGORITHM', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent)),
                      subtitle: const Text('Automatically execute entry signals when triggered', style: TextStyle(color: Colors.white54)),
                      value: isAuto,
                      activeColor: Colors.blueAccent,
                      onChanged: (val) async {
                         await _api.toggleTradingConfig(tradingEnabled: val);
                         setState(() { _tradingStateFuture = _api.getTradingState(); });
                      }
                    ),
                  ]
                )
              ),
              
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.blueAccent, width: 1.5),
                          padding: const EdgeInsets.all(16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () { _showTradeHistory(context); },
                        icon: const Icon(Icons.history, color: Colors.blueAccent),
                        label: const Text('VIEW HISTORY', style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.withOpacity(0.1),
                          side: const BorderSide(color: Colors.greenAccent, width: 1.0),
                          padding: const EdgeInsets.all(16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: _exportToCSV,
                        icon: const Icon(Icons.download, color: Colors.greenAccent),
                        label: const Text('EXPORT CSV', style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const Text('ACTIVE POSITIONS', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white54, letterSpacing: 1.5)),
              const SizedBox(height: 12),
              
              ...positions.entries.map((e) {
                final String symbol = e.key;
                final pos = e.value;
                if (pos == null) {
                   return Card(
                     color: kSurface,
                     child: ListTile(
                       title: Text(symbol, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                       trailing: const Text('NO ACTIVE POSITION', style: TextStyle(color: Colors.white30, fontWeight: FontWeight.bold)),
                     )
                   );
                }
                
                // Render Active Position
                final isPaperPos = pos['trading_symbol']?.startsWith('PAPER') ?? false;
                
                return Card(
                     color: kSurface,
                     margin: const EdgeInsets.only(bottom: 12),
                     shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: isPaperPos ? Colors.amber.withOpacity(0.5) : Colors.blue.withOpacity(0.5))),
                     child: Padding(
                       padding: const EdgeInsets.all(16),
                       child: Column(
                         crossAxisAlignment: CrossAxisAlignment.start,
                         children: [
                           Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(symbol, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(color: isPaperPos ? Colors.amber.withOpacity(0.2) : Colors.blue.withOpacity(0.2), borderRadius: BorderRadius.circular(4)),
                                      child: Text(isPaperPos ? 'PAPER TRADE' : 'LIVE TRADE', style: TextStyle(color: isPaperPos ? Colors.amber : Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 10))
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      icon: const Icon(Icons.cancel, color: Colors.white54, size: 20),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      onPressed: () async {
                                         await _api.closePosition(symbol);
                                         setState((){});
                                      }
                                    )
                                  ]
                                )
                              ]
                           ),
                           const SizedBox(height: 8),
                           Text('SELL ${pos['strike']} ${pos['type']} • Qty: ${pos['quantity']}', style: TextStyle(color: pos['type'] == 'CE' ? kRed : kGreen, fontWeight: FontWeight.bold, fontSize: 16)),
                           const SizedBox(height: 12),
                           Row(
                             mainAxisAlignment: MainAxisAlignment.spaceBetween,
                             children: [
                               Column(
                                 crossAxisAlignment: CrossAxisAlignment.start,
                                 children: [
                                    const Text('ENTRY PRICE', style: TextStyle(color: Colors.white54, fontSize: 10)),
                                    Text('₹${pos['entry_price']}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))
                                 ]
                               ),
                               Column(
                                 crossAxisAlignment: CrossAxisAlignment.end,
                                 children: [
                                    const Text('ENTRY TIME', style: TextStyle(color: Colors.white54, fontSize: 10)),
                                    Text('${pos['timestamp']}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))
                                 ]
                               )
                             ]
                           ),
                           if (pos['current_profit'] != null) ...[
                             const SizedBox(height: 12),
                             const Divider(color: Colors.white10),
                             Row(
                               mainAxisAlignment: MainAxisAlignment.spaceBetween,
                               children: [
                                 const Text('CURRENT P&L', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                                 Text(
                                   (pos['current_profit'] as num) >= 0 ? '+₹${(pos['current_profit'] as num).toStringAsFixed(2)}' : '-₹${(pos['current_profit'] as num).abs().toStringAsFixed(2)}',
                                   style: TextStyle(
                                     color: (pos['current_profit'] as num) >= 0 ? kGreen : kRed,
                                     fontWeight: FontWeight.w900, fontSize: 24,
                                     shadows: [Shadow(color: (pos['current_profit'] as num) >= 0 ? kGreen : kRed, blurRadius: 10)]
                                   )
                                 )
                               ]
                             )
                           ]
                         ]
                       )
                     )
                   );
              }),
            ]
          )
        );
      }
    );
  }

  void _showTradeHistory(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: kBg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return FutureBuilder<List<dynamic>>(
          future: _api.getTradeHistory(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(height: 400, child: Center(child: CircularProgressIndicator()));
            }
            if (snapshot.hasError) {
              return SizedBox(height: 300, child: Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: kRed))));
            }
            final list = snapshot.data ?? [];
            if (list.isEmpty) {
              return const SizedBox(height: 300, child: Center(child: Text('No trades logged today', style: TextStyle(color: Colors.white54, fontSize: 16))));
            }
            
            return Container(
              height: MediaQuery.of(context).size.height * 0.8,
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    const Text('TRADE HISTORY LEDGER', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white)),
                    IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context))
                  ]),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (context, idx) {
                        final t = list[list.length - 1 - idx]; // Reverse order
                        final double profit = (t['profit'] ?? 0).toDouble();
                        final String time = t['exit_time']?.split(' ')?.last ?? '';
                        final String symbol = t['symbol'] ?? '';
                        
                        return Card(
                          color: kSurface,
                          margin: const EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: profit >= 0 ? kGreen.withOpacity(0.3) : kRed.withOpacity(0.3))),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                                Text('${symbol.replaceAll('PAPER_', '')}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                                Text(profit >= 0 ? '+₹${profit.toStringAsFixed(2)}' : '-₹${profit.abs().toStringAsFixed(2)}', style: TextStyle(color: profit >= 0 ? kGreen : kRed, fontWeight: FontWeight.w900, fontSize: 18))
                              ]),
                              const SizedBox(height: 8),
                              Text('${t['type']} ${t['strike']} • Qty ${t['quantity']}', style: const TextStyle(color: Colors.white70)),
                              const SizedBox(height: 6),
                              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                                Text('Entry ₹${t['entry_price']} → Exit ₹${t['exit_price']}', style: const TextStyle(fontSize: 12, color: Colors.white54)),
                                Text('Time: $time', style: const TextStyle(fontSize: 12, color: Colors.white38))
                              ]),
                              const Divider(color: Colors.white10),
                              Text('💡 Reason: ${t['exit_reason'] ?? 'Manual'}', style: TextStyle(color: profit >= 0 ? kGreen.withOpacity(0.8) : kAccent, fontSize: 12, fontStyle: FontStyle.italic))
                            ])
                          )
                        );
                      }
                    )
                  )
                ]
              )
            );
          }
        );
      }
    );
  }

  Widget _buildBody() {
    if (_initialLoading) return const Center(child: _Spinner(label: 'Connecting to backend…'));
    if (_error != null) return _ErrorView(message: _error!, onRetry: _boot);
    
    if (_activeTabIndex == 0) return _buildPulseTier();
    if (_activeTabIndex == 1) return _buildAnalyticsTier();
    return _buildCommandHubTier();
  }

  Widget _buildMarketExtrasBar() {
    final double vix = _marketExtras['vix']?.toDouble() ?? 0.0;
    final double vixChg = _marketExtras['vix_change']?.toDouble() ?? 0.0;
    final List<dynamic> heavy = _marketExtras['heavyweights'] ?? [];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: kSurface.withOpacity(0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(children: [
                const Icon(Icons.analytics_outlined, color: Colors.purpleAccent, size: 20),
                const SizedBox(width: 8),
                const Text('INDIA VIX', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
                const SizedBox(width: 12),
                Text('$vix', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)),
                const SizedBox(width: 6),
                Text(vixChg >= 0 ? '+$vixChg%' : '$vixChg%', style: TextStyle(color: vixChg >= 0 ? kRed : kGreen, fontSize: 12, fontWeight: FontWeight.bold)), 
              ]),
              const Text('HEAVYWEIGHTS DRIVERS ⚖️', style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold)),
            ],
          ),
          if (heavy.isNotEmpty) ...[
             const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider(color: Colors.white10, height: 1)),
             SingleChildScrollView(
               scrollDirection: Axis.horizontal,
               physics: const BouncingScrollPhysics(),
               child: Row(
                 children: heavy.map<Widget>((h) {
                    final double chg = h['change']?.toDouble() ?? 0.0;
                    final String sym = h['symbol'] ?? '';
                    final double wt = h['weight']?.toDouble() ?? 0.0;
                    return Container(
                       margin: const EdgeInsets.only(right: 12),
                       padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                       decoration: BoxDecoration(color: Colors.white.withOpacity(0.03), borderRadius: BorderRadius.circular(8)),
                       child: Row(children: [
                          Text(sym, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12)),
                          const SizedBox(width: 6),
                          Text(chg >= 0 ? '+$chg%' : '$chg%', style: TextStyle(color: chg >= 0 ? kGreen : kRed, fontWeight: FontWeight.w800, fontSize: 12)),
                          const SizedBox(width: 4),
                          Text('(${wt}%)', style: const TextStyle(color: Colors.white24, fontSize: 10)),
                       ]),
                    );
                 }).toList(),
               ),
             )
          ],
          
          // 🔔 Volume Spike Alerts 
          () {
            final List<String> allAlerts = [];
            for (final sym in _summary.keys) {
               final al = _summary[sym]?.alerts ?? [];
               for (final a in al) { allAlerts.add('[$sym] $a'); }
            }
            if (allAlerts.isEmpty) return const SizedBox.shrink();
            
            return Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.red.withOpacity(0.08), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.redAccent.withOpacity(0.3))),
              child: Row(
                children: [
                   const Icon(Icons.notifications_active, color: Colors.redAccent, size: 16),
                   const SizedBox(width: 8),
                   Expanded(
                     child: SingleChildScrollView(
                       scrollDirection: Axis.horizontal,
                       physics: const BouncingScrollPhysics(),
                       child: Row(
                         children: allAlerts.map<Widget>((a) => Container(
                           margin: const EdgeInsets.only(right: 16),
                           child: Text(a, style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                         )).toList(),
                       ),
                     )
                   )
                ],
              )
            );
          }()

        ],
      )
    );
  }

  Widget _buildPulseTier() {
    double nScore = _getCompositeScore('NIFTY');
    double bScore = _getCompositeScore('BANKNIFTY');
    double fScore = _getCompositeScore('FINNIFTY');
    double avgScore = (nScore + bScore + fScore) / 3.0;

    double nPcr = _summary['NIFTY']?.pcr ?? 1.0;
    double bPcr = _summary['BANKNIFTY']?.pcr ?? 1.0;
    double fPcr = _summary['FINNIFTY']?.pcr ?? 1.0;
    double avgPcr = (nPcr + bPcr + fPcr) / 3.0;

    Color glowColor = Colors.blueGrey;
    if (avgScore > 65) glowColor = kGreen;
    else if (avgScore < 35) glowColor = kRed;

    String strategyText = "STRATEGY: NEUTRAL (Range)";
    Color strategyColor = Colors.amber;
    if (avgScore > 65) { strategyText = "STRATEGY: SELL PUT / BUY CE"; strategyColor = kGreen; }
    else if (avgScore < 35) { strategyText = "STRATEGY: SELL CALL / BUY PE"; strategyColor = kRed; }

    final double width = MediaQuery.of(context).size.width;
    final bool isSmall = width < 900;

    return _LiveScenarioBackground(
      color: glowColor,
      score: avgScore,
      child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // ⚡ Triple Index Confluence Alignment
          _TripleIndexConfluence(summary: _summary),
          
          const SizedBox(height: 16),
          
          // 📊 India VIX & Heavyweight contribution
          _buildMarketExtrasBar(),
          
          const SizedBox(height: 24),

          Container(
            padding: const EdgeInsets.all(24),
            width: double.infinity,
            decoration: BoxDecoration(
              color: kSurface.withOpacity(0.4),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.04)),
            ),
            child: Column(
              children: [
                const Text('📊 AGGREGATED MARKET SENTIMENT', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                const SizedBox(height: 35),
                Wrap(
                  spacing: 40,
                  runSpacing: 40,
                  alignment: WrapAlignment.center,
                  children: [
                    _SpeedometerGauge(score: avgScore, label: 'AVG Composite: ${avgPcr.toStringAsFixed(2)}'),
                    _SpeedometerGauge(score: nScore, label: 'NIFTY (${nPcr.toStringAsFixed(2)})'),
                    _SpeedometerGauge(score: bScore, label: 'BANKNIFTY (${bPcr.toStringAsFixed(2)})'),
                    _SpeedometerGauge(score: fScore, label: 'FINNIFTY (${fPcr.toStringAsFixed(2)})'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          
          // 🎫 Strategy Banner Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: strategyColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: strategyColor.withOpacity(0.4), width: 1.5)
            ),
            child: Center(
              child: Text(
                strategyText,
                style: TextStyle(color: strategyColor, fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // 🥊 ATM Battleground (Responsively grid stacked)
          isSmall 
          ? Column(
              children: [
                _AtmBattleground(summary: _summary['NIFTY'], symbol: 'NIFTY'),
                const SizedBox(height: 16),
                _AtmBattleground(summary: _summary['BANKNIFTY'], symbol: 'BANKNIFTY'),
              ],
            )
          : Row(
              children: [
                Expanded(child: _AtmBattleground(summary: _summary['NIFTY'], symbol: 'NIFTY')),
                const SizedBox(width: 16),
                Expanded(child: _AtmBattleground(summary: _summary['BANKNIFTY'], symbol: 'BANKNIFTY')),
              ],
            ),
          const SizedBox(height: 24),

          if (_mtfTrend != null) _MTF_Matrix(mtfTrend: _mtfTrend!),
          const SizedBox(height: 24),
          _OIBuildUpHeatmap(
             symbol: 'NIFTY',
             summary: _summary['NIFTY'],
             date: _selectedDate,
             oiStats: _oiStats['NIFTY'] ?? []
          ),
          const SizedBox(height: 24),
          _buildBarriersSection(context),
        ],
      ),
    ),);
  }

  Widget _buildBarriersSection(BuildContext context) {
    final bool isSmall = MediaQuery.of(context).size.width < 900;
    final widgets = <Widget>[];

    for (final sym in ['NIFTY', 'BANKNIFTY', 'FINNIFTY']) {
      final list = _oiStats[sym] ?? [];
      double spot = _summary[sym]?.spot ?? 0;
      double res = 0.0; double sup = 0.0;
      int maxC = 0; int maxP = 0;

      for (final oi in list) {
        if (oi.ceOi > maxC) { maxC = oi.ceOi; res = oi.strikePrice; }
        if (oi.peOi > maxP) { maxP = oi.peOi; sup = oi.strikePrice; }
      }

      final summaryForSym = _summary[sym];
      if (res == 0.0 && summaryForSym != null && summaryForSym.highCeStrike != null && summaryForSym.highCeStrike! > 0) {
         res = summaryForSym.highCeStrike!;
      }
      if (sup == 0.0 && summaryForSym != null && summaryForSym.highPeStrike != null && summaryForSym.highPeStrike! > 0) {
         sup = summaryForSym.highPeStrike!;
      }

      if (res == 0.0) res = spot + 100.0;
      if (sup == 0.0) sup = spot - 100.0;

      if (spot > 0) {
        widgets.add(
          _BarrierSlider(
            symbol: sym, spot: spot, support: sup, resistance: res,
            accent: sym == 'NIFTY' ? kNifty : (sym == 'BANKNIFTY' ? kBank : Colors.purpleAccent),
          )
        );
      }
    }

    if (widgets.isEmpty) {
      return const Center(child: Text("🧱 Loading Barrier Support/Resistance Data...", style: TextStyle(color: Colors.white24, fontSize: 12)));
    }

    if (isSmall) {
      return Column(children: widgets.map((w) => Padding(padding: const EdgeInsets.only(bottom: 12), child: w)).toList());
    }

    return Row(children: widgets.map((w) => Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: w))).toList());
  }

  Widget _buildAnalyticsTier() {
    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth < 900) {
        // Mobile / Tablet Stacked View
        return ListView(
          padding: EdgeInsets.zero,
          children: [
            _Panel(symbol: 'NIFTY', date: _selectedDate!, accent: kNifty, summary: _summary['NIFTY'],
              oiStats: _oiStats['NIFTY'] ?? [], oiLoading: _oiLoading['NIFTY'] ?? false,
              oiHistograms: _oiHistograms['NIFTY'] ?? [], oiHistLoading: _oiHistLoading['NIFTY'] ?? false,
              border: false, isMobile: true),
            const Divider(color: kBorder, height: 1, thickness: 1.5),
            _Panel(symbol: 'BANKNIFTY', date: _selectedDate!, accent: kBank,  summary: _summary['BANKNIFTY'],
              oiStats: _oiStats['BANKNIFTY'] ?? [], oiLoading: _oiLoading['BANKNIFTY'] ?? false,
              oiHistograms: _oiHistograms['BANKNIFTY'] ?? [], oiHistLoading: _oiHistLoading['BANKNIFTY'] ?? false,
              border: false, isMobile: true),
            const Divider(color: kBorder, height: 1, thickness: 1.5),
            _Panel(symbol: 'FINNIFTY', date: _selectedDate!, accent: Colors.purple,  summary: _summary['FINNIFTY'],
              oiStats: _oiStats['FINNIFTY'] ?? [], oiLoading: _oiLoading['FINNIFTY'] ?? false,
              oiHistograms: _oiHistograms['FINNIFTY'] ?? [], oiHistLoading: _oiHistLoading['FINNIFTY'] ?? false,
              border: false, isMobile: true),
          ],
        );
      } else {
        // Desktop Side-by-Side View
        return Row(children: [
          Expanded(
            child: _Panel(symbol: 'NIFTY', date: _selectedDate!, accent: kNifty, summary: _summary['NIFTY'],
              oiStats: _oiStats['NIFTY'] ?? [], oiLoading: _oiLoading['NIFTY'] ?? false,
              oiHistograms: _oiHistograms['NIFTY'] ?? [], oiHistLoading: _oiHistLoading['NIFTY'] ?? false,
              border: true, isMobile: false),
          ),
          Expanded(
            child: _Panel(symbol: 'BANKNIFTY', date: _selectedDate!, accent: kBank,  summary: _summary['BANKNIFTY'],
              oiStats: _oiStats['BANKNIFTY'] ?? [], oiLoading: _oiLoading['BANKNIFTY'] ?? false,
              oiHistograms: _oiHistograms['BANKNIFTY'] ?? [], oiHistLoading: _oiHistLoading['BANKNIFTY'] ?? false,
              border: true, isMobile: false),
          ),
          Expanded(
            child: _Panel(symbol: 'FINNIFTY', date: _selectedDate!, accent: Colors.purple,  summary: _summary['FINNIFTY'],
              oiStats: _oiStats['FINNIFTY'] ?? [], oiLoading: _oiLoading['FINNIFTY'] ?? false,
              oiHistograms: _oiHistograms['FINNIFTY'] ?? [], oiHistLoading: _oiHistLoading['FINNIFTY'] ?? false,
              border: false, isMobile: false),
          ),
        ]);
      }
    });
  }
}

// ─── Global Pinned Signals Bar ─────────────────────────────────
class _GlobalSignalsBar extends StatelessWidget {
  final Map<String, QuickSummary> summary;
  const _GlobalSignalsBar({required this.summary});

  @override
  Widget build(BuildContext context) {
    final String nSig = summary['NIFTY']?.signal ?? '';
    final String bSig = summary['BANKNIFTY']?.signal ?? '';
    final String fSig = summary['FINNIFTY']?.signal ?? '';
    
    bool bullish = nSig.contains('BUY') && bSig.contains('BUY') && fSig.contains('BUY');
    bool bearish = nSig.contains('SELL') && bSig.contains('SELL') && fSig.contains('SELL');
    
    String conf = "NEUTRAL 🟡";
    Color confColor = Colors.amber;
    if (bullish) { conf = "BULLISH CONFLUENCE 🟢"; confColor = kGreen; }
    else if (bearish) { conf = "BEARISH CONFLUENCE 🔴"; confColor = kRed; }

    final double width = MediaQuery.of(context).size.width;
    final bool isSmall = width < 600;

    if (isSmall) {
      return Container(
        padding: const EdgeInsets.all(8),
        decoration: const BoxDecoration(
          color: Colors.transparent, 
          border: Border(bottom: BorderSide(color: Colors.white10, width: 0.5)),
        ),
        child: Column(
          children: [
            Row(children: [
              Expanded(child: _SignalCard(symbol: 'NIFTY', accent: kNifty, summary: summary['NIFTY'])),
              const SizedBox(width: 8),
              Expanded(child: _SignalCard(symbol: 'BANKNIFTY', accent: kBank, summary: summary['BANKNIFTY'])),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: _SignalCard(symbol: 'FINNIFTY', accent: Colors.purple, summary: summary['FINNIFTY'])),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  height: 30,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: confColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: confColor.withOpacity(0.3), width: 1.0)
                  ),
                  child: Center(
                    child: FittedBox(
                      child: Text(conf, style: TextStyle(color: confColor, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.5))
                    )
                  ),
                )
              ),
            ])
          ],
        ),
      );
    }

    return Container(
      height: 40,
      decoration: const BoxDecoration(
        color: Colors.transparent, 
        border: Border(bottom: BorderSide(color: Colors.white10, width: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Expanded(child: _SignalCard(symbol: 'NIFTY', accent: kNifty, summary: summary['NIFTY'])),
            Expanded(child: _SignalCard(symbol: 'BANKNIFTY', accent: kBank, summary: summary['BANKNIFTY'])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: confColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: confColor.withOpacity(0.3), width: 1.0)
              ),
              child: Text(conf, style: TextStyle(color: confColor, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
            ),
            Expanded(child: _SignalCard(symbol: 'FINNIFTY', accent: Colors.purple, summary: summary['FINNIFTY'])),
          ],
        ),
      ),
    );
  }
}

// ─── Panel ─────────────────────────────────────────────────────
class _Panel extends StatelessWidget {
  final String symbol;
  final String date;
  final Color accent;
  final QuickSummary? summary;
  final List<OiStat> oiStats;
  final bool oiLoading;
  final bool border;
  final bool isMobile;

  final List<dynamic> oiHistograms;
  final bool oiHistLoading;

  const _Panel({
    required this.symbol, required this.date, required this.accent, required this.summary,
    required this.oiStats, required this.oiLoading, required this.border, required this.isMobile,
    required this.oiHistograms, required this.oiHistLoading,
  });

  @override
  Widget build(BuildContext context) {
    Widget content = Container(
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: border ? kBorder : Colors.transparent))),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // ② OI stat chips (instant after phase1)
          if (summary != null) _StatRow(summary: summary!, accent: accent),
          const SizedBox(height: 10),

          // 🆕 Multi-Timeframe Histogram
          oiHistLoading
            ? _PlaceholderCard(label: 'Loading Histograms…', accent: accent, height: 180)
            : (oiHistograms.isEmpty
                ? _PlaceholderCard(label: 'No Histogram data', accent: accent, height: 180, error: true)
                : _OiHistogramChart(histograms: oiHistograms, accent: accent)),
          const SizedBox(height: 10),

          // ③ OI Line chart
          oiLoading
            ? _PlaceholderCard(label: 'Loading OI chart…', accent: accent, height: 160)
            : (oiStats.isEmpty
                ? _PlaceholderCard(label: 'No chart data', accent: accent, height: 160, error: true)
                : _OiLineChart(oiStats: oiStats, accent: accent)),
          const SizedBox(height: 10),

          // ④ Change in OI chart
          oiLoading
            ? _PlaceholderCard(label: 'Loading Change in OI…', accent: accent, height: 160)
            : (oiStats.isEmpty
                ? _PlaceholderCard(label: 'No chart data', accent: accent, height: 160, error: true)
                : _ChangeOiLineChart(oiStats: oiStats, accent: accent)),
          const SizedBox(height: 10),

          // ⑤ PCR chart
          oiLoading
            ? _PlaceholderCard(label: 'Loading PCR chart…', accent: accent, height: 140)
            : (oiStats.isEmpty
                ? _PlaceholderCard(label: 'No PCR data', accent: accent, height: 140, error: true)
                : _PcrChart(oiStats: oiStats, accent: accent)),
          const SizedBox(height: 10),

          // ⑥ Call / Put Difference chart
          oiLoading
            ? _PlaceholderCard(label: 'Loading Call-Put Diff…', accent: accent, height: 140)
            : (oiStats.isEmpty
                ? _PlaceholderCard(label: 'No chart data', accent: accent, height: 140, error: true)
                : _DiffChart(oiStats: oiStats, accent: accent)),
          const SizedBox(height: 10),

          // ⑦ Max Pain vs Spot chart
          oiLoading
            ? _PlaceholderCard(label: 'Loading Max Pain…', accent: accent, height: 140)
            : (oiStats.isEmpty
                ? _PlaceholderCard(label: 'No chart data', accent: accent, height: 140, error: true)
                : _MaxPainChart(oiStats: oiStats, accent: accent)),
          const SizedBox(height: 10),

          // ⑧ Option chain (On-demand Phase 3)
          _ExpandableOptionChain(
            symbol: symbol, date: date, accent: accent, spotPrice: summary?.spot),
        ]),
      ),
    );
    return isMobile ? content : Expanded(child: content);
  }
}

// ─── Pulsing Signal Card ───────────────────────────────────────
class _SignalCard extends StatefulWidget {
  final String symbol;
  final Color accent;
  final QuickSummary? summary;
  const _SignalCard({required this.symbol, required this.accent, required this.summary});

  @override
  State<_SignalCard> createState() => _SignalCardState();
}

class _SignalCardState extends State<_SignalCard> with SingleTickerProviderStateMixin {
  late AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  Color _sColor(String? c) {
    switch (c) { 
      case 'green': return kGreen; 
      case 'red': return kRed;
      case 'orange': return kOrange; 
      default: return kGrey; 
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.summary == null) {
      return Container(
        height: 120,
        decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(16)),
        child: const Center(child: _Spinner(size: 24)),
      );
    }

    final sc = _sColor(widget.summary?.color);
    final String sig = widget.summary!.signal.toUpperCase();
    final bool isStrongSignal = sig.contains(RegExp(r'BUY|SELL|STRONG'));
    
    String mainWord = sig;
    if (sig.contains('(')) {
       mainWord = sig.split('(')[0].trim();
    }

    return AnimatedBuilder(
      animation: _anim,
      builder: (context, child) {
        return Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: kSurface.withOpacity(0.4),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: sc.withOpacity(0.15)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 4, height: 16,
                          decoration: BoxDecoration(color: sc, borderRadius: BorderRadius.circular(2)),
                        ),
                        const SizedBox(width: 8),
                        Text(widget.symbol == 'BANKNIFTY' ? 'BNF' : 'NFT', style: TextStyle(color: widget.accent, fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                        const SizedBox(width: 8),
                        Text(mainWord, style: TextStyle(color: sc, fontSize: 13, fontWeight: FontWeight.w900)),
                      ],
                    ),
                    if (isStrongSignal) ...[
                      Material(
                        color: sc,
                        borderRadius: BorderRadius.circular(6),
                        child: InkWell(
                          onTap: widget.summary!.atm == null ? null : () async {
                             playAlertSound();
                             await ApiService().executeTrade(widget.symbol, sig, widget.summary!.atm!);
                          },
                          child: const Padding(padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4), child: Text('EXE', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900))),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    if (widget.summary!.suggestedStrike != null) ...[
                      Text('🎯 ${widget.summary!.suggestedStrike!.toStringAsFixed(0)}', style: const TextStyle(color: Colors.amberAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 12),
                    ],
                    if (widget.summary!.maxPain != null && widget.summary!.maxPain! > 0) ...[
                       Text('🧲 Max Pain: ${widget.summary!.maxPain!.toStringAsFixed(0)}', style: const TextStyle(color: Colors.purpleAccent, fontSize: 11, fontWeight: FontWeight.w900)),
                       const SizedBox(width: 12),
                    ],
                    Text('Spot: ${NumberFormat("#,##0").format(widget.summary!.spot)}', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                    const SizedBox(width: 12),
                    Text('PCR: ${widget.summary!.pcr.toStringAsFixed(2)}', style: TextStyle(color: widget.summary!.pcr > 1.0 ? kGreen : kRed, fontSize: 11, fontWeight: FontWeight.w900)),
                  ],
                )
              ],
            ),
          ),
        );
      },
    );
  }

}

// ─── Stat row ──────────────────────────────────────────────────
class _StatRow extends StatelessWidget {
  final QuickSummary summary;
  final Color accent;
  const _StatRow({required this.summary, required this.accent});

  @override
  Widget build(BuildContext context) => Row(children: [
    _chip('CE OI', NumberFormat.compact().format(summary.ceOi), kGreen),
    const SizedBox(width: 8),
    _chip('PE OI', NumberFormat.compact().format(summary.peOi), kRed),
    const SizedBox(width: 8),
    _chip('PCR', summary.pcr.toStringAsFixed(2), summary.pcr >= 1 ? kGreen : kRed),
  ]);

  Widget _chip(String label, String val, Color color) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [kSurface, kSurface2.withOpacity(0.5)],
          begin: Alignment.topLeft, end: Alignment.bottomRight
        ),
        borderRadius: BorderRadius.circular(16), 
        border: Border.all(color: color.withOpacity(0.2), width: 1),
        boxShadow: [
          BoxShadow(color: color.withOpacity(0.04), blurRadius: 12, spreadRadius: 0, offset: const Offset(0, 4)),
        ]
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: kSubStyle.copyWith(fontSize: 8, color: Colors.white38)),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(val, style: kMono.copyWith(color: color, fontWeight: FontWeight.w900, fontSize: 16))),
      ]),
    ),
  );
}

// ─── Oi Histogram Bar Chart ──────────────────────────────────────
class _OiHistogramChart extends StatelessWidget {
  final List<dynamic> histograms;
  final Color accent;
  const _OiHistogramChart({required this.histograms, required this.accent});

  @override
  Widget build(BuildContext context) {
    if (histograms.isEmpty) return const SizedBox();

    double maxY = 0;
    double minY = 0;
    for (var h in histograms) {
       final ce = (h['ce_change'] ?? 0).toDouble();
       final pe = (h['pe_change'] ?? 0).toDouble();
       if (ce > maxY) maxY = ce;
       if (pe > maxY) maxY = pe;
       if (ce < minY) minY = ce;
       if (pe < minY) minY = pe;
    }
    if (maxY == 0 && minY == 0) maxY = 1000;
    
    final barGroups = <BarChartGroupData>[];
    for (int i=0; i<histograms.length; i++) {
        final h = histograms[i];
        final ce = (h['ce_change'] ?? 0).toDouble();
        final pe = (h['pe_change'] ?? 0).toDouble();
        
        barGroups.add(BarChartGroupData(
           x: i,
           barRods: [
              BarChartRodData(toY: ce, color: kGreen, width: 14, borderRadius: BorderRadius.circular(2)),
              BarChartRodData(toY: pe, color: kRed, width: 14, borderRadius: BorderRadius.circular(2)),
           ],
           barsSpace: 4,
        ));
    }

    return _ChartCard(
      title: 'HISTORIC OI DELTAS  🟢 CE  🔴 PE',
      icon: Icons.bar_chart_rounded, height: 180,
      child: BarChart(
        swapAnimationDuration: Duration.zero,
        BarChartData(
          maxY: maxY + (maxY - minY)*0.1,
          minY: minY < 0 ? minY - (maxY - minY)*0.1 : 0,
          gridData: FlGridData(
            drawVerticalLine: false,
            getDrawingHorizontalLine: (v) => FlLine(color: v == 0 ? Colors.white54 : kBorder, strokeWidth: v == 0 ? 1 : 0.5)
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(sideTitles: SideTitles(
              showTitles: true, reservedSize: 32,
              getTitlesWidget: (v, _) => Text(NumberFormat.compact().format(v), style: const TextStyle(color: Colors.white24, fontSize: 8)),
            )),
            bottomTitles: AxisTitles(sideTitles: SideTitles(
              showTitles: true, reservedSize: 22,
              getTitlesWidget: (v, _) {
                 if (v.toInt() >= 0 && v.toInt() < histograms.length) {
                    return Padding(padding: const EdgeInsets.only(top: 8), child: Text(histograms[v.toInt()]['interval'], style: const TextStyle(color: Colors.white60, fontSize: 10, fontWeight: FontWeight.bold)));
                 }
                 return const SizedBox();
              }
            )),
          ),
          barGroups: barGroups,
          barTouchData: BarTouchData(
             touchTooltipData: BarTouchTooltipData(
                getTooltipItem: (group, groupIndex, rod, rodIndex) {
                   final val = NumberFormat.compact().format(rod.toY);
                   final side = rodIndex == 0 ? 'CE' : 'PE';
                   return BarTooltipItem('$side: $val', TextStyle(color: rod.color, fontWeight: FontWeight.bold, fontSize: 11));
                }
             )
          )
        )
      )
    );
  }
}

// ─── OI Line Chart ─────────────────────────────────────────────
class _OiLineChart extends StatelessWidget {
  final List<OiStat> oiStats;
  final Color accent;
  const _OiLineChart({required this.oiStats, required this.accent});

  @override
  Widget build(BuildContext context) {
    if (oiStats.length < 2) return const SizedBox();
    final step = (oiStats.length / 40).ceil().clamp(1, 9999);
    final samples = <OiStat>[];
    for (int i = 0; i < oiStats.length; i += step) samples.add(oiStats[i]);
    if (samples.isNotEmpty && samples.last != oiStats.last) samples.add(oiStats.last);

    double maxOi = samples.map((s) => s.ceOi > s.peOi ? s.ceOi : s.peOi).reduce((a, b) => a > b ? a : b).toDouble();
    double minOi = samples.map((s) => s.ceOi < s.peOi ? s.ceOi : s.peOi).reduce((a, b) => a < b ? a : b).toDouble();
    if (maxOi == minOi) maxOi += 1;

    double maxSpot = samples.map((s) => s.spot).reduce((a, b) => a > b ? a : b);
    double minSpot = samples.map((s) => s.spot).reduce((a, b) => a < b ? a : b);
    if (maxSpot == minSpot) maxSpot += 1;

    // Scale spot price to fit in OI chart range [minOi, maxOi] dynamically
    double scaleSpot(double spot) => minOi + ((spot - minSpot) / (maxSpot - minSpot)) * (maxOi - minOi);

    final ceSpots = <FlSpot>[];
    final peSpots = <FlSpot>[];
    final spotSpots = <FlSpot>[];

    for (int i = 0; i < samples.length; i++) {
        ceSpots.add(FlSpot(i.toDouble(), samples[i].ceOi.toDouble()));
        peSpots.add(FlSpot(i.toDouble(), samples[i].peOi.toDouble()));
        spotSpots.add(FlSpot(i.toDouble(), scaleSpot(samples[i].spot)));
    }

    return _ChartCard(
      title: 'TOTAL OPEN INTEREST & SPOT PRICE  🟢 CE  🔴 PE  ⚪ Spot',
      icon: Icons.show_chart_rounded, height: 160,
      child: LineChart(
        duration: Duration.zero,
        LineChartData(
          minY: minOi - (maxOi-minOi)*0.05,
          maxY: maxOi + (maxOi-minOi)*0.05,
          gridData: FlGridData(
            drawVerticalLine: false, 
            getDrawingHorizontalLine: (_) => const FlLine(color: kBorder, strokeWidth: 0.5)
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(sideTitles: SideTitles(
              showTitles: true, reservedSize: 14, 
              interval: (samples.length / 4).clamp(1, 9999).toDouble(),
              getTitlesWidget: (v, _) => Text(samples[v.toInt().clamp(0, samples.length - 1)].timestamp, 
                style: const TextStyle(color: Colors.white24, fontSize: 8)),
            )),
            leftTitles: AxisTitles(sideTitles: SideTitles(
              showTitles: true, reservedSize: 32,
              getTitlesWidget: (v, _) => Text(NumberFormat.compact().format(v), 
                style: const TextStyle(color: Colors.white24, fontSize: 8)),
            )),
          ),
          lineBarsData: [
            LineChartBarData(spots: ceSpots, isCurved: true, color: kGreen, barWidth: 2.5, dotData: const FlDotData(show: false), belowBarData: BarAreaData(show: true, gradient: LinearGradient(colors: [kGreen.withOpacity(0.12), Colors.transparent], begin: Alignment.topCenter, end: Alignment.bottomCenter))),
            LineChartBarData(spots: peSpots, isCurved: true, color: kRed, barWidth: 2.5, dotData: const FlDotData(show: false), belowBarData: BarAreaData(show: true, gradient: LinearGradient(colors: [kRed.withOpacity(0.12), Colors.transparent], begin: Alignment.topCenter, end: Alignment.bottomCenter))),
            LineChartBarData(spots: spotSpots, isCurved: true, color: Colors.white70, dashArray: [4, 4], barWidth: 1.5, dotData: const FlDotData(show: false)),
          ],
          lineTouchData: LineTouchData(touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (ts) {
              if (ts.isEmpty) return [];
              final i = ts.first.x.toInt().clamp(0, samples.length - 1);
              final s = samples[i];
              return [
                LineTooltipItem('${s.timestamp}\nCE: ${NumberFormat.compact().format(s.ceOi)}\nPE: ${NumberFormat.compact().format(s.peOi)}\nSpot: ${s.spot.toStringAsFixed(1)}', const TextStyle(color: Colors.white, fontSize: 10)),
                ...List.generate(ts.length - 1, (_) => LineTooltipItem('', const TextStyle())), // hide duplicate tooltips
              ];
            }
          )),
        ),
      ),
    );
  }
}

// ─── PCR Line Chart ────────────────────────────────────────────
class _PcrChart extends StatelessWidget {
  final List<OiStat> oiStats;
  final Color accent;
  const _PcrChart({required this.oiStats, required this.accent});

  @override
  Widget build(BuildContext context) {
    final step = (oiStats.length / 30).ceil().clamp(1, 9999);
    final spots = <FlSpot>[];
    for (int i = 0; i < oiStats.length; i += step) {
      spots.add(FlSpot(i.toDouble(), oiStats[i].pcr));
    }
    if (spots.length < 2) return const SizedBox();

    final minY = (spots.map((s) => s.y).reduce((a, b) => a < b ? a : b) - 0.1).clamp(0.0, 99.0);
    final maxY =  spots.map((s) => s.y).reduce((a, b) => a > b ? a : b) + 0.1;

    return _ChartCard(
      title: 'PUT / CALL RATIO (PCR)  — — neutral at 1.0',
      icon: Icons.show_chart_rounded, height: 140,
      child: LineChart(
        duration: Duration.zero,
        LineChartData(
          minY: minY, maxY: maxY,
          gridData: FlGridData(drawVerticalLine: false,
            horizontalInterval: ((maxY - minY) / 3).clamp(0.01, 99),
            getDrawingHorizontalLine: (_) => const FlLine(color: kBorder, strokeWidth: 0.5)),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(sideTitles: SideTitles(
              showTitles: true, reservedSize: 28,
              getTitlesWidget: (v, _) => Text(v.toStringAsFixed(2),
                style: const TextStyle(color: Colors.white24, fontSize: 8)),
            )),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots, isCurved: true, color: accent, barWidth: 2,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(show: true, gradient: LinearGradient(
                colors: [accent.withOpacity(0.25), accent.withOpacity(0)],
                begin: Alignment.topCenter, end: Alignment.bottomCenter)),
            ),
            LineChartBarData(
              spots: [FlSpot(0, 1), FlSpot(spots.length.toDouble(), 1)],
              color: Colors.white24, barWidth: 1, dashArray: [4, 4],
              dotData: const FlDotData(show: false)),
          ],
          lineTouchData: LineTouchData(touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (ts) => ts.map((t) => LineTooltipItem(
              'PCR: ${t.y.toStringAsFixed(2)}',
              const TextStyle(color: Colors.white, fontSize: 10))).toList())),
        ),
      ),
    );
  }
}

// ─── Change in OI Line Chart ───────────────────────────────────
class _ChangeOiLineChart extends StatelessWidget {
  final List<OiStat> oiStats;
  final Color accent;
  const _ChangeOiLineChart({required this.oiStats, required this.accent});

  @override
  Widget build(BuildContext context) {
    if (oiStats.length < 2) return const SizedBox();
    final step = (oiStats.length / 40).ceil().clamp(1, 9999);
    final samples = <OiStat>[];
    for (int i = 0; i < oiStats.length; i += step) samples.add(oiStats[i]);
    if (samples.isNotEmpty && samples.last != oiStats.last) samples.add(oiStats.last);

    double maxY = 0;
    double minY = 0;
    for (var s in samples) {
      if (s.ceChangeOi > maxY) maxY = s.ceChangeOi.toDouble();
      if (s.peChangeOi > maxY) maxY = s.peChangeOi.toDouble();
      if (s.ceChangeOi < minY) minY = s.ceChangeOi.toDouble();
      if (s.peChangeOi < minY) minY = s.peChangeOi.toDouble();
    }
    if (maxY == 0 && minY == 0) maxY = 1000;

    double maxSpot = samples.map((s) => s.spot).reduce((a, b) => a > b ? a : b);
    double minSpot = samples.map((s) => s.spot).reduce((a, b) => a < b ? a : b);
    if (maxSpot == minSpot) maxSpot += 1;

    // Scale Spot Price to fit in chart range
    double scaleSpot(double spot) => minY + ((spot - minSpot) / (maxSpot - minSpot)) * (maxY - minY);

    final ceSpots = <FlSpot>[];
    final peSpots = <FlSpot>[];
    final spotSpots = <FlSpot>[];

    for (int i = 0; i < samples.length; i++) {
        ceSpots.add(FlSpot(i.toDouble(), samples[i].ceChangeOi.toDouble()));
        peSpots.add(FlSpot(i.toDouble(), samples[i].peChangeOi.toDouble()));
        spotSpots.add(FlSpot(i.toDouble(), scaleSpot(samples[i].spot)));
    }

    return _ChartCard(
      title: 'CHANGE IN OI & SPOT PRICE  🟢 CE  🔴 PE  ⚪ Spot',
      icon: Icons.show_chart_rounded, height: 160,
      child: LineChart(
        duration: Duration.zero,
        LineChartData(
          maxY: maxY + (maxY - minY) * 0.05,
          minY: minY - (maxY - minY) * 0.05,
          gridData: FlGridData(
            drawVerticalLine: false,
            getDrawingHorizontalLine: (v) => FlLine(color: v == 0 ? Colors.white54 : kBorder, strokeWidth: v == 0 ? 1 : 0.5)
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(sideTitles: SideTitles(
              showTitles: true, reservedSize: 14, 
              interval: (samples.length / 4).clamp(1, 9999).toDouble(),
              getTitlesWidget: (v, _) => Text(samples[v.toInt().clamp(0, samples.length - 1)].timestamp, 
                style: const TextStyle(color: Colors.white24, fontSize: 8)),
            )),
            leftTitles: AxisTitles(sideTitles: SideTitles(
              showTitles: true, reservedSize: 32,
              getTitlesWidget: (v, _) => Text(NumberFormat.compact().format(v), 
                style: const TextStyle(color: Colors.white24, fontSize: 8)),
            )),
          ),
          lineBarsData: [
            LineChartBarData(spots: ceSpots, isCurved: true, color: kGreen, barWidth: 2.5, dotData: const FlDotData(show: false), belowBarData: BarAreaData(show: true, gradient: LinearGradient(colors: [kGreen.withOpacity(0.12), Colors.transparent], begin: Alignment.topCenter, end: Alignment.bottomCenter))),
            LineChartBarData(spots: peSpots, isCurved: true, color: kRed, barWidth: 2.5, dotData: const FlDotData(show: false), belowBarData: BarAreaData(show: true, gradient: LinearGradient(colors: [kRed.withOpacity(0.12), Colors.transparent], begin: Alignment.topCenter, end: Alignment.bottomCenter))),
            LineChartBarData(spots: spotSpots, isCurved: true, color: Colors.white70, dashArray: [4, 4], barWidth: 1.5, dotData: const FlDotData(show: false)),
          ],
          lineTouchData: LineTouchData(touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (ts) {
              if (ts.isEmpty) return [];
              final i = ts.first.x.toInt().clamp(0, samples.length - 1);
              final s = samples[i];
              return [
                LineTooltipItem('${s.timestamp}\nCE Chg: ${NumberFormat.compact().format(s.ceChangeOi)}\nPE Chg: ${NumberFormat.compact().format(s.peChangeOi)}\nSpot: ${s.spot.toStringAsFixed(1)}', const TextStyle(color: Colors.white, fontSize: 10)),
                ...List.generate(ts.length - 1, (_) => LineTooltipItem('', const TextStyle())), // hide duplicate tooltips
              ];
            }
          )),
        ),
      ),
    );
  }
}

// ─── Call Put Difference Chart ─────────────────────────────────
class _DiffChart extends StatelessWidget {
  final List<OiStat> oiStats;
  final Color accent;
  const _DiffChart({required this.oiStats, required this.accent});

  @override
  Widget build(BuildContext context) {
    final step = (oiStats.length / 30).ceil().clamp(1, 9999);
    final spots = <FlSpot>[];
    for (int i = 0; i < oiStats.length; i += step) {
      double diff = (oiStats[i].ceOi - oiStats[i].peOi).toDouble();
      spots.add(FlSpot(i.toDouble(), diff));
    }
    if (spots.length < 2) return const SizedBox();

    double maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    double minY = spots.map((s) => s.y).reduce((a, b) => a < b ? a : b);
    if (maxY == minY) maxY += 1;

    return _ChartCard(
      title: 'OI DIFFERENCE (CE - PE)  — > 0 is Bearish / < 0 is Bullish',
      icon: Icons.difference_outlined, height: 140,
      child: LineChart(
        duration: Duration.zero,
        LineChartData(
          minY: minY < 0 ? minY * 1.1 : 0, 
          maxY: maxY > 0 ? maxY * 1.1 : 0,
          gridData: FlGridData(drawVerticalLine: false,
            getDrawingHorizontalLine: (v) => FlLine(
              color: v == 0 ? Colors.white54 : kBorder, strokeWidth: v == 0 ? 1 : 0.5)),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(sideTitles: SideTitles(
              showTitles: true, reservedSize: 32,
              getTitlesWidget: (v, _) => Text(NumberFormat.compact().format(v),
                style: const TextStyle(color: Colors.white24, fontSize: 8)),
            )),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots, isCurved: true, color: Colors.blueAccent, barWidth: 2.5,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(show: true, gradient: LinearGradient(colors: [Colors.blueAccent.withOpacity(0.15), Colors.transparent], begin: Alignment.topCenter, end: Alignment.bottomCenter))
            ),
          ],
          lineTouchData: LineTouchData(touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (ts) => ts.map((t) => LineTooltipItem(
              'Diff: ${NumberFormat.compact().format(t.y)}\n(>0 Bearish, <0 Bullish)',
              const TextStyle(color: Colors.white, fontSize: 10))).toList())),
        ),
      ),
    );
  }
}

// ─── Max Pain vs Spot Chart ────────────────────────────────────
class _MaxPainChart extends StatelessWidget {
  final List<OiStat> oiStats;
  final Color accent;
  const _MaxPainChart({required this.oiStats, required this.accent});

  @override
  Widget build(BuildContext context) {
    // Only use stats where maxPain is > 0 (available)
    final validStats = oiStats.where((s) => s.maxPain > 0).toList();
    if (validStats.length < 2) {
      return const Center(child: Text("Waiting for sufficient Max Pain data...", style: TextStyle(color: Colors.white24, fontSize: 10)));
    }

    final step = (validStats.length / 30).ceil().clamp(1, 9999);
    final spotSpots = <FlSpot>[];
    final mpSpots = <FlSpot>[];
    
    for (int i = 0; i < validStats.length; i += step) {
      spotSpots.add(FlSpot(i.toDouble(), validStats[i].spot));
      mpSpots.add(FlSpot(i.toDouble(), validStats[i].maxPain));
    }

    double maxSpot = spotSpots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    double minSpot = spotSpots.map((s) => s.y).reduce((a, b) => a < b ? a : b);
    double maxMp = mpSpots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    double minMp = mpSpots.map((s) => s.y).reduce((a, b) => a < b ? a : b);

    double maxY = maxSpot > maxMp ? maxSpot : maxMp;
    double minY = minSpot < minMp ? minSpot : minMp;

    double padding = (maxY - minY) * 0.1;
    if (padding == 0) padding = 10;

    return _ChartCard(
      title: 'MAX PAIN vs SPOT  ⚪ Spot  🟣 Max Pain',
      icon: Icons.timeline_rounded, height: 140,
      child: LineChart(
        duration: Duration.zero,
        LineChartData(
          minY: minY - padding,
          maxY: maxY + padding,
          gridData: FlGridData(drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => const FlLine(color: kBorder, strokeWidth: 0.5)),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(sideTitles: SideTitles(
              showTitles: true, reservedSize: 32,
              getTitlesWidget: (v, _) => Text(v.toStringAsFixed(0),
                style: const TextStyle(color: Colors.white24, fontSize: 8)),
            )),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spotSpots, isCurved: true, color: Colors.white60, barWidth: 1.5,
              dashArray: [4, 4], dotData: const FlDotData(show: false),
            ),
            LineChartBarData(
              spots: mpSpots, isCurved: true, color: Colors.deepPurpleAccent, barWidth: 2.5,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(show: true, gradient: LinearGradient(colors: [Colors.deepPurpleAccent.withOpacity(0.15), Colors.transparent], begin: Alignment.topCenter, end: Alignment.bottomCenter))
            ),
          ],
          lineTouchData: LineTouchData(touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (ts) {
              if (ts.length < 2) return [];
              final sort = ts.toList()..sort((a,b) => a.barIndex.compareTo(b.barIndex));
              final spotVal = sort[0].y;
              final mpVal = sort[1].y;
              return [
                LineTooltipItem('Spot: ${spotVal.toStringAsFixed(1)}\nMP: ${mpVal.toStringAsFixed(1)}', 
                  const TextStyle(color: Colors.white, fontSize: 10)),
                LineTooltipItem('', const TextStyle()), // hide the second tooltip
              ];
            }
          )),
        ),
      ),
    );
  }
}

// ─── Institutional Chart Card Wrapper ──────────────────────────
class _ChartCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final double height;
  final Widget child;
  const _ChartCard({required this.title, required this.icon,
    required this.height, required this.child});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: kSurface,
      borderRadius: BorderRadius.circular(20), 
      border: Border.all(color: Colors.white.withOpacity(0.05)),
      boxShadow: [
        BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 5)),
      ]
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(icon, size: 12, color: kAccent.withOpacity(0.5)),
        const SizedBox(width: 8),
        Expanded(child: Text(title.toUpperCase(),
          style: kSubStyle.copyWith(fontSize: 9, color: Colors.white38))),
      ]),
      const SizedBox(height: 18),
      SizedBox(height: height, child: child),
    ]),
  );
}

// ─── Placeholder ───────────────────────────────────────────────
class _PlaceholderCard extends StatelessWidget {
  final String label;
  final Color accent;
  final double height;
  final bool error;
  const _PlaceholderCard({required this.label, required this.accent,
    required this.height, this.error = false});
  @override
  Widget build(BuildContext context) => Container(
    height: height,
    decoration: BoxDecoration(color: kSurface,
      borderRadius: BorderRadius.circular(14), border: Border.all(color: kBorder)),
    child: Center(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      if (!error) SizedBox(width: 14, height: 14,
        child: CircularProgressIndicator(strokeWidth: 1.5, color: accent))
      else const Icon(Icons.info_outline, size: 14, color: Colors.white24),
      const SizedBox(width: 10),
      Text(label, style: const TextStyle(color: Colors.white30, fontSize: 12)),
    ])),
  );
}

// ─── Institutional Option Chain Table ──────────────────────────
class _OptionChainTable extends StatelessWidget {
  final List<OptionData> optionData;
  final double? spotPrice;
  final Color accent;
  const _OptionChainTable({required this.optionData,
    required this.spotPrice, required this.accent});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: kSurface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.white.withOpacity(0.03)),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _hdr(),
        const Divider(color: Colors.white12, height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: optionData.length,
            itemBuilder: (context, i) {
              final r = optionData[i];
              return _OcRow(data: r,
                  isAtm: spotPrice != null && (r.strikePrice - spotPrice!).abs() < 51,
                  accent: accent);
            },
          ),
        ),
      ]),
  );

  Widget _hdr() {
    final s = kSubStyle.copyWith(fontSize: 9, color: Colors.white24);
    return Container(
      color: kSurface2,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(children: [
        Expanded(child: Text('OI', style: s, textAlign: TextAlign.right)),
        Expanded(child: Text('Δ OI', style: s, textAlign: TextAlign.right)),
        Expanded(child: Text('Δ/Γ', style: s, textAlign: TextAlign.right)),
        Expanded(child: Text('LTP', style: s, textAlign: TextAlign.right)),
        const Expanded(flex: 2,
          child: Text('STRIKE', style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1), textAlign: TextAlign.center)),
        Expanded(child: Text('LTP', style: s)),
        Expanded(child: Text('Δ/Γ', style: s)),
        Expanded(child: Text('Δ OI', style: s)),
        Expanded(child: Text('OI', style: s)),
      ]));
  }
}

class _OcRow extends StatelessWidget {
  final OptionData data;
  final bool isAtm;
  final Color accent;
  const _OcRow({required this.data, required this.isAtm, required this.accent});

  Color _c(num? v) => (v == null || v == 0) ? Colors.white54 : v > 0 ? kGreen : kRed;

  @override
  Widget build(BuildContext context) {
    final c  = NumberFormat.compact();
    final lf = NumberFormat('#,##0.00');
    return Container(
      decoration: BoxDecoration(
        color: isAtm ? accent.withOpacity(0.07) : Colors.transparent,
        border: isAtm ? Border(
          left: BorderSide(color: accent, width: 2),
          right: BorderSide(color: accent, width: 2)) : null),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: Row(children: [
        Expanded(child: Text(c.format(data.ce.oi ?? 0),
          style: const TextStyle(color: Colors.white60, fontSize: 10),
          textAlign: TextAlign.right)),
        Expanded(child: Text(c.format(data.ce.changeOi ?? 0),
          style: TextStyle(color: _c(data.ce.changeOi), fontSize: 10),
          textAlign: TextAlign.right)),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text((data.ce.delta ?? 0).toStringAsFixed(2), style: const TextStyle(color: Colors.white70, fontSize: 10)),
          Text(data.ce.gamma != null && data.ce.gamma! > 0 ? data.ce.gamma!.toStringAsFixed(4) : '-', style: const TextStyle(color: Colors.deepPurpleAccent, fontSize: 8)),
        ])),
        Expanded(child: Text(lf.format(data.ce.lastPrice ?? 0),
          style: TextStyle(color: _c(data.ce.change), fontSize: 10),
          textAlign: TextAlign.right)),
        Expanded(flex: 2, child: Text(
          NumberFormat('#,###').format(data.strikePrice),
          textAlign: TextAlign.center,
          style: TextStyle(color: isAtm ? accent : Colors.white,
            fontWeight: isAtm ? FontWeight.bold : FontWeight.w500, fontSize: 11))),
        Expanded(child: Text(lf.format(data.pe.lastPrice ?? 0),
          style: TextStyle(color: _c(data.pe.change), fontSize: 10))),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text((data.pe.delta ?? 0).toStringAsFixed(2), style: const TextStyle(color: Colors.white70, fontSize: 10)),
          Text(data.pe.gamma != null && data.pe.gamma! > 0 ? data.pe.gamma!.toStringAsFixed(4) : '-', style: const TextStyle(color: Colors.deepPurpleAccent, fontSize: 8)),
        ])),
        Expanded(child: Text(c.format(data.pe.changeOi ?? 0),
          style: TextStyle(color: _c(data.pe.changeOi), fontSize: 10))),
        Expanded(child: Text(c.format(data.pe.oi ?? 0),
          style: const TextStyle(color: Colors.white60, fontSize: 10))),
      ]),
    );
  }
}

// ─── Institutional Header ──────────────────────────────────────
class _Header extends StatefulWidget {
  final List<String> dates;
  final String? selectedDate;
  final DateTime lastUpdated;
  final bool refreshing;
  final int activeTabIndex;
  final int playbackMinutes;
  final ValueChanged<int> onTabChanged;
  final ValueChanged<int> onPlaybackChanged;
  final ValueChanged<int> onPlaybackEnd;
  final ValueChanged<String> onDateChanged;
  final VoidCallback onRefresh;

  const _Header({
    required this.dates, required this.selectedDate,
    required this.lastUpdated, required this.refreshing,
    required this.activeTabIndex, required this.onTabChanged,
    required this.playbackMinutes, required this.onPlaybackChanged, required this.onPlaybackEnd,
    required this.onDateChanged, required this.onRefresh
  });

  @override
  State<_Header> createState() => _HeaderState();
}

class _TabButton extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _TabButton({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: active ? kAccent : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.black : Colors.white,
            fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.8
          )
        ),
      ),
    );
  }
}

class _HeaderState extends State<_Header> {
  late Timer _t;
  DateTime _now = DateTime.now();
  @override
  void initState() { super.initState(); _t = Timer.periodic(const Duration(seconds: 1), (_) => setState(() => _now = DateTime.now())); }
  @override
  void dispose() { _t.cancel(); super.dispose(); }

  Widget _buildTabSwitcher() {
    return Container(
      height: 38, padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: kSurface2, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.04)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _TabButton(label: '🌐 MARKET PULSE', active: widget.activeTabIndex == 0, onTap: () => widget.onTabChanged(0)),
          _TabButton(label: '📊 ANALYTICS', active: widget.activeTabIndex == 1, onTap: () => widget.onTabChanged(1)),
          _TabButton(label: '⚡ COMMAND HUB', active: widget.activeTabIndex == 2, onTap: () => widget.onTabChanged(2)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSmall = MediaQuery.of(context).size.width < 700;
    
    if (isSmall) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: kSurface.withOpacity(0.85),
          border: const Border(bottom: BorderSide(color: Colors.white10, width: 0.5)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildTabSwitcher(),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Container(width: 8, height: 8, decoration: const BoxDecoration(color: kAccent, shape: BoxShape.circle)),
                      const SizedBox(width: 8),
                      Text('QUANT TERMINAL', style: kSubStyle.copyWith(color: kAccent.withOpacity(0.8), letterSpacing: 1, fontSize: 8)),
                    ]),
                    const Text('NSE OPTION CHAIN', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.white)),
                  ],
                ),
                _RefreshButton(onPressed: widget.onRefresh, refreshing: widget.refreshing),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (widget.dates.isNotEmpty)
                  Container(
                    height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: kSurface2, borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white.withOpacity(0.05)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: widget.selectedDate, dropdownColor: kSurface,
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                        items: widget.dates.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
                        onChanged: (v) { if (v != null) widget.onDateChanged(v); })),
                  ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(DateFormat('HH:mm').format(_now), style: kMono.copyWith(fontSize: 14, color: Colors.white)),
                    const Text('SYSTEM LIVE', style: TextStyle(fontSize: 8, color: kGreen, fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Container(
      height: 70,
      decoration: BoxDecoration(
        color: kSurface.withOpacity(0.85),
        border: const Border(bottom: BorderSide(color: Colors.white10, width: 0.5)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(children: [
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(width: 8, height: 8, decoration: const BoxDecoration(color: kAccent, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Text('QUANT TERMINAL V1', style: kSubStyle.copyWith(color: kAccent.withOpacity(0.8), letterSpacing: 2)),
              ],
            ),
            const Text('NSE OPTION CHAIN', style: kHeaderStyle),
          ],
        ),
        const SizedBox(width: 40),
        _buildTabSwitcher(),
        const Spacer(),
        if (widget.dates.isNotEmpty)
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: kSurface2,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.05)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: widget.selectedDate, dropdownColor: kSurface,
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 1),
                icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: kGrey),
                items: widget.dates.map((d) =>
                  DropdownMenuItem(value: d, child: Text(d))).toList(),
                onChanged: (v) { if (v != null) widget.onDateChanged(v); })),
          ),
        const SizedBox(width: 20),
        
        // 🕰️ PLAYBACK SCRUBBER
        Container(
           padding: const EdgeInsets.symmetric(horizontal: 12),
           height: 40,
           decoration: BoxDecoration(color: Colors.white.withOpacity(0.02), borderRadius: BorderRadius.circular(12)),
           child: Row(
              children: [
                 Icon(Icons.history, color: widget.playbackMinutes >= 930 ? Colors.white30 : Colors.amberAccent, size: 16),
                 const SizedBox(width: 8),
                 SizedBox(
                    width: 140,
                    child: SliderTheme(
                       data: SliderTheme.of(context).copyWith(trackHeight: 2, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6), overlayShape: const RoundSliderOverlayShape(overlayRadius: 12)),
                       child: Slider(
                         value: widget.playbackMinutes.toDouble(),
                         min: 555, max: 930, divisions: 930 - 555,
                         activeColor: widget.playbackMinutes >= 930 ? kGreen : Colors.amberAccent,
                         inactiveColor: Colors.white12,
                         onChanged: (v) => widget.onPlaybackChanged(v.toInt()),
                         onChangeEnd: (v) => widget.onPlaybackEnd(v.toInt()),
                       )
                    )
                 ),
                 SizedBox(
                   width: 36,
                   child: Text(
                     widget.playbackMinutes >= 930 ? 'LIVE' : '${widget.playbackMinutes ~/ 60}:${(widget.playbackMinutes % 60).toString().padLeft(2, '0')}', 
                     style: TextStyle(color: widget.playbackMinutes >= 930 ? kGreen : Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 11)
                   )
                 )
              ]
           )
        ),
        const SizedBox(width: 25),
        // Clock & Sync Status
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(DateFormat('HH:mm:ss').format(_now),
                 style: kMono.copyWith(fontSize: 18, color: Colors.white, letterSpacing: 1)),
            Row(
              children: [
                const Text('SYSTEM LIVE', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: kGreen, letterSpacing: 1)),
                const SizedBox(width: 6),
                Container(
                  width: 6, height: 6, 
                  decoration: BoxDecoration(
                    color: kGreen, shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: kGreen.withOpacity(0.5), blurRadius: 4, spreadRadius: 1)]
                  )
                ),
              ],
            ),
          ],
        ),
        const SizedBox(width: 25),
        _RefreshButton(onPressed: widget.onRefresh, refreshing: widget.refreshing),
      ]),
    );
  }
}

class _RefreshButton extends StatelessWidget {
  final VoidCallback onPressed;
  final bool refreshing;
  const _RefreshButton({required this.onPressed, required this.refreshing});
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onPressed,
    borderRadius: BorderRadius.circular(12),
    child: Container(
      width: 40, height: 40,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Center(
        child: refreshing 
          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: kAccent))
          : const Icon(Icons.sync_rounded, color: kGrey, size: 22),
      ),
    ),
  );
}

// ─── Error view ────────────────────────────────────────────────
class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(child: Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      const Icon(Icons.error_outline_rounded, color: kRed, size: 48),
      const SizedBox(height: 16),
      Text(message, textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white54, fontSize: 13, height: 1.8)),
      const SizedBox(height: 20),
      ElevatedButton.icon(onPressed: onRetry,
        icon: const Icon(Icons.refresh_rounded, size: 16),
        label: const Text('Retry'),
        style: ElevatedButton.styleFrom(backgroundColor: kNifty)),
    ]));
}

// ─── Spinner ───────────────────────────────────────────────────
class _Spinner extends StatelessWidget {
  final double size;
  final String? label;
  const _Spinner({this.size = 32, this.label});
  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
    SizedBox(width: size, height: size,
      child: const CircularProgressIndicator(strokeWidth: 2,
        valueColor: AlwaysStoppedAnimation(kNifty))),
    if (label != null) ...[
      const SizedBox(height: 14),
      Text(label!, style: const TextStyle(color: Colors.white38, fontSize: 13)),
      const SizedBox(height: 6),
      Text('http://127.0.0.1:5000',
        style: _mono.copyWith(color: Colors.white24, fontSize: 10)),
    ],
  ]);
}

// ─── Expandable Option Chain ───────────────────────────────────
class _ExpandableOptionChain extends StatefulWidget {
  final String symbol;
  final String date;
  final double? spotPrice;
  final Color accent;
  const _ExpandableOptionChain({
    required this.symbol, required this.date,
    required this.spotPrice, required this.accent});

  @override
  State<_ExpandableOptionChain> createState() => _ExpandableOptionChainState();
}

class _ExpandableOptionChainState extends State<_ExpandableOptionChain> {
  final _api = ApiService();
  bool _expanded = false;
  bool _loading = false;
  List<OptionData> _data = [];
  String? _error;

  void _loadTask() async {
    setState(() { _loading = true; _error = null; });
    try {
      final ts = await _api.getTimestamps(widget.symbol, widget.date);
      if (ts.isEmpty) throw Exception('No timestamps');
      final od = await _api.getData(widget.symbol, ts.last, widget.date);
      if (mounted) setState(() { _data = od; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = 'Option chain error: $e'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: kSurface,
        borderRadius: BorderRadius.circular(14), border: Border.all(color: kBorder)),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          collapsedIconColor: Colors.white30,
          iconColor: widget.accent,
          title: Row(children: [
            Icon(Icons.table_rows_rounded, size: 14, color: _expanded ? widget.accent : Colors.white30),
            const SizedBox(width: 8),
            Text('VIEW OPTION CHAIN',
              style: TextStyle(color: _expanded ? widget.accent : Colors.white30, 
                fontSize: 10, letterSpacing: 1, fontWeight: FontWeight.bold)),
            if (_expanded && !_loading && _data.isNotEmpty) ...[
              const Spacer(),
              Text('${_data.length} strikes', style: const TextStyle(color: Colors.white24, fontSize: 9)),
            ]
          ]),
          onExpansionChanged: (exp) {
            setState(() => _expanded = exp);
            if (exp && _data.isEmpty && !_loading) _loadTask();
          },
          children: [
            const Divider(color: kBorder, height: 1),
            if (_loading)
               Padding(padding: const EdgeInsets.all(30), 
                 child: _Spinner(size: 20, label: 'Loading all strikes...')),
            if (!_loading && _error != null)
               Padding(padding: const EdgeInsets.all(20), 
                 child: Text(_error!, style: const TextStyle(color: kRed))),
            if (!_loading && _error == null && _data.isNotEmpty)
               ConstrainedBox(
                 constraints: const BoxConstraints(maxHeight: 450),
                 child: LayoutBuilder(builder: (context, constraints) {
                   if (MediaQuery.of(context).size.width < 600) {
                     return _OptionChainMobileList(optionData: _data, spotPrice: widget.spotPrice, accent: widget.accent);
                   }
                   return _OptionChainTable(optionData: _data, spotPrice: widget.spotPrice, accent: widget.accent);
                 }),
               ),
          ],
        ),
      ),
    );
  }
}

// ─── Option Chain Mobile Card-style List ──────────────────────────
class _OptionChainMobileList extends StatelessWidget {
  final List<OptionData> optionData;
  final double? spotPrice;
  final Color accent;

  const _OptionChainMobileList({
    required this.optionData,
    required this.spotPrice,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: optionData.length,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemBuilder: (context, i) {
        final r = optionData[i];
        final bool isAtm = spotPrice != null && (r.strikePrice - spotPrice!).abs() < 51;
        return _OcMobileCard(data: r, isAtm: isAtm, accent: accent);
      },
    );
  }
}

class _OcMobileCard extends StatelessWidget {
  final OptionData data;
  final bool isAtm;
  final Color accent;

  const _OcMobileCard({required this.data, required this.isAtm, required this.accent});

  Color _c(num? v) => (v == null || v == 0) ? Colors.white54 : v > 0 ? kGreen : kRed;

  @override
  Widget build(BuildContext context) {
    final c = NumberFormat.compact();
    final lf = NumberFormat('#,##0.00');

    return Card(
      color: isAtm ? accent.withOpacity(0.08) : kSurface2.withOpacity(0.6),
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: isAtm ? accent.withOpacity(0.4) : Colors.white.withOpacity(0.05)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            // Center Strike Label
            Text(
              NumberFormat('#,###').format(data.strikePrice),
              style: TextStyle(
                color: isAtm ? accent : Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
            const Divider(color: Colors.white10),
            
            // Calls & Puts Columns
            Row(
              children: [
                // Call Stats (Left)
                Expanded(
                  child: Column(
                    children: [
                      const Text('CALLS (CE)', style: TextStyle(color: kGreen, fontSize: 9, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      _row('LTP', lf.format(data.ce.lastPrice ?? 0), _c(data.ce.change)),
                      _row('OI', c.format(data.ce.oi ?? 0), Colors.white60),
                      _row('Δ OI', c.format(data.ce.changeOi ?? 0), _c(data.ce.changeOi)),
                      _row('Δ / Γ', '${(data.ce.delta ?? 0).toStringAsFixed(2)} / ${(data.ce.gamma ?? 0).toStringAsFixed(4)}', Colors.white30),
                    ],
                  ),
                ),
                Container(width: 1, height: 50, color: Colors.white10),
                
                // Put Stats (Right)
                Expanded(
                  child: Column(
                    children: [
                      const Text('PUTS (PE)', style: TextStyle(color: kRed, fontSize: 9, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      _row('LTP', lf.format(data.pe.lastPrice ?? 0), _c(data.pe.change)),
                      _row('OI', c.format(data.pe.oi ?? 0), Colors.white60),
                      _row('Δ OI', c.format(data.pe.changeOi ?? 0), _c(data.pe.changeOi)),
                      _row('Δ / Γ', '${(data.pe.delta ?? 0).toStringAsFixed(2)} / ${(data.pe.gamma ?? 0).toStringAsFixed(4)}', Colors.white30),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String val, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white24, fontSize: 9)),
          Text(val, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
        ],
      ),
    );
  }
}

class _LoginScreen extends StatefulWidget {
  final VoidCallback onSuccess;
  const _LoginScreen({required this.onSuccess});

  @override
  State<_LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<_LoginScreen> {
  final _passController = TextEditingController();
  bool _loading = false;
  String? _error;

  void _submit() async {
    if (_passController.text.isEmpty) return;
    setState(() { _loading = true; _error = null; });
    try {
      final success = await ApiService().login(_passController.text);
      if (success) {
         try {
           html.window.localStorage['dashboard_auth'] = 'AUTHORIZED_OK';
         } catch(e) {}
         widget.onSuccess();
      } else {
         setState(() { _error = "Incorrect Password"; _loading = false; });
      }
    } catch (e) {
      setState(() { _error = "Connection Error"; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
     return Scaffold(
       backgroundColor: kBg,
       body: Center(
         child: Container(
            width: 360,
            padding: const EdgeInsets.all(32),
            decoration: kGlassDecoration,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
               const Icon(Icons.lock_outline, color: kAccent, size: 48),
               const SizedBox(height: 16),
               const Text('NSE OPTION CHAIN', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white)),
               const SizedBox(height: 4),
               const Text('ENTER PASSWORD TO ACCESS', style: TextStyle(fontSize: 11, color: kGrey, letterSpacing: 1)),
               const SizedBox(height: 32),
               TextField(
                  controller: _passController,
                  obscureText: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                     hintText: 'Password',
                     hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
                     filled: true,
                     fillColor: kSurface,
                     contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                     border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                  onSubmitted: (_) => _submit(),
               ),
               if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: kRed, fontSize: 13))
               ],
               const SizedBox(height: 24),
               SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                     style: ElevatedButton.styleFrom(
                        backgroundColor: kAccent,
                        foregroundColor: kBg,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.all(16)
                     ),
                     onPressed: _loading ? null : _submit,
                     child: _loading 
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: kBg)) 
                        : const Text('UNLOCK DASHBOARD', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                  )
               )
            ])
         )
       )
     );
  }
}
class _LogsPanel extends StatefulWidget {
  final ApiService api;
  const _LogsPanel({required this.api});

  @override
  State<_LogsPanel> createState() => _LogsPanelState();
}

class _LogsPanelState extends State<_LogsPanel> {
  bool _expanded = false;
  List<String> _logs = [];
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _fetch();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) => _fetch());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _fetch() async {
    try {
      final l = await widget.api.getLogs();
      if (mounted) setState(() { _logs = l; });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      height: _expanded ? 200 : 40,
      decoration: const BoxDecoration(
        color: kSurface,
        border: Border(top: BorderSide(color: Colors.white10, width: 0.5)),
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              color: kSurface2,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(children: [
                    const Icon(Icons.code, color: kAccent, size: 16),
                    const SizedBox(width: 8),
                    const Text('LIVE SYSTEM LOGS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1, color: Colors.white70)),
                  ]),
                  Icon(_expanded ? Icons.expand_more : Icons.expand_less, color: Colors.white54, size: 18)
                ],
              ),
            ),
          ),
          
          if (_expanded)
            Expanded(
              child: _logs.isEmpty 
                ? const Center(child: Text('Connecting to Log Stream...', style: TextStyle(color: Colors.white24, fontSize: 11)))
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _logs.length,
                    itemBuilder: (context, i) {
                       final l = _logs[i];
                       Color color = Colors.white70;
                       if (l.contains('🚀')) color = kAccent;
                       else if (l.contains('🛑')) color = kRed;
                       else if (l.contains('📊')) color = kGreen;

                       return Padding(
                         padding: const EdgeInsets.only(bottom: 4),
                         child: Text(l, style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: color)),
                       );
                    }
                  )
            )
        ],
      ),
    );
  }
}

class _SpeedometerGauge extends StatelessWidget {
  final double score; // 0 to 100
  final String label;
  const _SpeedometerGauge({required this.score, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: 180, height: 100,
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: score),
            duration: const Duration(milliseconds: 1200),
            curve: Curves.easeOutBack,
            builder: (context, animValue, child) {
              return CustomPaint(
                painter: _GaugePainter(score: animValue),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white10),
          ),
          child: Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 0.8),
          ),
        ),
      ],
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double score;
  _GaugePainter({required this.score});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height);
    final radius = size.width / 2 - 8.0;
    
    final Paint bgPaint = Paint()
      ..color = Colors.white.withOpacity(0.05)
      ..strokeWidth = 12.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final Paint fillPaint = Paint()
      ..shader = const LinearGradient(
        colors: [kRed, Colors.amber, kGreen],
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..strokeWidth = 14.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Draw background track
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), pi, pi, false, bgPaint);

    // Draw active track
    double sweepAngle = (score / 100.0) * pi;
    if (sweepAngle > 0) {
      canvas.drawArc(Rect.fromCircle(center: center, radius: radius), pi, sweepAngle, false, fillPaint);
    }

    // Draw needle
    final needlePaint = Paint()..color = Colors.white..strokeWidth = 3.5..strokeCap = StrokeCap.round;
    double needleAngle = pi + sweepAngle;
    double needleLen = radius - 4.0;
    Offset endOffset = Offset(center.dx + needleLen * cos(needleAngle), center.dy + needleLen * sin(needleAngle));
    
    canvas.drawLine(center, endOffset, needlePaint);
    canvas.drawCircle(center, 7.0, Paint()..color = kAccent);
    canvas.drawCircle(center, 4.0, Paint()..color = Colors.black);
  }

  @override
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// ─── TRIPLE INDEX CONFLUENCE ALIGNMENT ───────────────────────────
class _TripleIndexConfluence extends StatelessWidget {
  final Map<String, QuickSummary> summary;
  const _TripleIndexConfluence({required this.summary});

  @override
  Widget build(BuildContext context) {
    double nPcr = summary['NIFTY']?.pcr ?? 1.0;
    double bPcr = summary['BANKNIFTY']?.pcr ?? 1.0;
    double fPcr = summary['FINNIFTY']?.pcr ?? 1.0;

    bool nBull = nPcr > 1.0;
    bool bBull = bPcr > 1.0;
    bool fBull = fPcr > 1.0;

    double avgScore = 0;
    int count = 0;
    for (var k in ['NIFTY', 'BANKNIFTY', 'FINNIFTY']) {
       if (summary[k] != null) {
          double pcr = summary[k]!.pcr;
          double pcrScore = (((pcr - 0.5) / 1.0) * 100).clamp(0, 100);
          double conf = summary[k]!.confluence.toDouble();
          
          // Weighted: 40% Absolute PCR + 60% Confluence momentum (including Change in OI checks from backend)
          avgScore += (pcrScore * 0.4) + (conf * 0.6);
          count++;
       }
    }
    if (count > 0) avgScore /= count;

    String biasText = avgScore > 50 ? 'BULLISH BIAS' : 'BEARISH BIAS';
    Color biasColor = avgScore > 50 ? kGreen : kRed;

    Widget buildBubble(String label, bool isBull) {
      Color c = isBull ? kGreen : kRed;
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(shape: BoxShape.circle, color: c.withOpacity(0.15), border: Border.all(color: c.withOpacity(0.4), width: 1.5)),
        child: Text(label, style: TextStyle(color: c, fontSize: 10, fontWeight: FontWeight.w900)),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kSurface.withOpacity(0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.04))
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                   Icon(Icons.flash_on, color: Colors.amberAccent, size: 14),
                   SizedBox(width: 4),
                   Text('TRIPLE-INDEX ALIGNMENT', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  buildBubble('NF', nBull),
                  const SizedBox(width: 8),
                  buildBubble('BN', bBull),
                  const SizedBox(width: 8),
                  buildBubble('FN', fBull),
                ],
              )
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(biasText, style: TextStyle(color: biasColor, fontSize: 14, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text('Score: ${avgScore.toStringAsFixed(0)}%', style: const TextStyle(color: Colors.white54, fontSize: 11)),
            ],
          )
        ],
      )
    );
  }
}

class _Particle {
  Offset position;
  double speed;
  double radius;
  double opacity;
  _Particle({required this.position, required this.speed, required this.radius, required this.opacity});
}

// ─── LIVE SCENARIO BACKGROUND: BOKEH PARTICLES ──────────────────
class _LiveScenarioBackground extends StatefulWidget {
  final Widget child;
  final Color color;
  final double score; 
  const _LiveScenarioBackground({required this.child, required this.color, required this.score});

  @override
  State<_LiveScenarioBackground> createState() => _LiveScenarioBackgroundState();
}

class _LiveScenarioBackgroundState extends State<_LiveScenarioBackground> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  final List<_Particle> _particles = [];
  final Random _rnd = Random();

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat();
    for (int i = 0; i < 25; i++) {
        _particles.add(_Particle(
          position: Offset(_rnd.nextDouble() * 400, _rnd.nextDouble() * 800),
          speed: 0.15 + _rnd.nextDouble() * 0.3,
          radius: 3.0 + _rnd.nextDouble() * 4.0,
          opacity: 0.04 + _rnd.nextDouble() * 0.08,
        ));
    }
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    double dy = widget.score > 55 ? -1.0 : 1.0; 

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        final size = MediaQuery.of(context).size;
        for (var p in _particles) {
           double newY = p.position.dy + (dy * p.speed);
           if (newY < 0) newY = size.height;
           if (newY > size.height) newY = 0;
           p.position = Offset(p.position.dx, newY);
        }

        return CustomPaint(
          painter: _ParticlePainter(particles: _particles, color: widget.color),
          child: widget.child,
        );
      }
    );
  }
}

class _ParticlePainter extends CustomPainter {
  final List<_Particle> particles;
  final Color color;
  _ParticlePainter({required this.particles, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..shader = RadialGradient(
       colors: [color.withOpacity(0.08), Colors.transparent],
       center: Alignment.topCenter, radius: 1.3
    ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, bgPaint);

    for (var p in particles) {
       final Paint pPaint = Paint()..color = color.withOpacity(p.opacity)..style = PaintingStyle.fill;
       canvas.drawCircle(p.position, p.radius, pPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// ─── ATM BATTLEGROUND: STRADDLE FIGHTS ──────────────────────────
class _AtmBattleground extends StatelessWidget {
  final QuickSummary? summary;
  final String symbol;
  const _AtmBattleground({required this.summary, required this.symbol});

  @override
  Widget build(BuildContext context) {
    if (summary == null || summary!.atm == null) return const SizedBox();

    double ceOi = (summary!.atmCeOi ?? 0) / 1000.0; 
    double peOi = (summary!.atmPeOi ?? 0) / 1000.0; 
    
    double total = ceOi + peOi;
    double fillRatio = total > 0 ? ceOi / total : 0.5;

    bool bearsLeading = ceOi > peOi;
    double diff = (ceOi - peOi).abs();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kSurface.withOpacity(0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.04))
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
               const Text('ATM BATTLEGROUND', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
               Container(
                 padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                 decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                 child: Text('${summary!.atm!.toStringAsFixed(0)} STRADDLE', style: const TextStyle(color: Colors.blueAccent, fontSize: 10, fontWeight: FontWeight.bold)),
               ),
            ]
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                 const Text('CALL WRITERS (Resistance)', style: TextStyle(color: kRed, fontSize: 10)),
                 Text('${ceOi.toStringAsFixed(1)}k', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
              ]),
              Container(padding: const EdgeInsets.all(6), decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white10), child: const Text('VS', style: TextStyle(color: Colors.white60, fontSize: 10, fontWeight: FontWeight.bold))),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                 const Text('PUT WRITERS (Support)', style: TextStyle(color: kGreen, fontSize: 10)),
                 Text('${peOi.toStringAsFixed(1)}k', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
              ]),
            ],
          ),
          const SizedBox(height: 12),
          // Split Progress Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              height: 8,
              child: Row(
                children: [
                  Expanded(flex: (fillRatio * 100).round() == 0 ? 1 : (fillRatio * 100).round(), child: Container(color: kRed)),
                  Expanded(flex: ((1 - fillRatio) * 100).round() == 0 ? 1 : ((1 - fillRatio) * 100).round(), child: Container(color: kGreen)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            bearsLeading ? 'BEARS LEADING by ${diff.toStringAsFixed(1)}k contracts' : 'BULLS LEADING by ${diff.toStringAsFixed(1)}k contracts',
            style: TextStyle(color: bearsLeading ? kRed : kGreen, fontSize: 11, fontWeight: FontWeight.bold),
          )
        ],
      )
    );
  }
}

// ─── BREATHING BACKDROP ANIMATION ──────────────────────────────
class _BreathingBackdrop extends StatefulWidget {
  final Widget child;
  final Color color;
  const _BreathingBackdrop({required this.child, required this.color});

  @override
  State<_BreathingBackdrop> createState() => _BreathingBackdropState();
}

class _BreathingBackdropState extends State<_BreathingBackdrop> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _glow;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat(reverse: true);
    _glow = Tween<double>(begin: 0.02, end: 0.08).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _glow,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              colors: [widget.color.withOpacity(_glow.value), Colors.transparent],
              center: Alignment.topCenter, radius: 1.3
            )
          ),
          child: widget.child,
        );
      }
    );
  }
}

class _BarrierSlider extends StatelessWidget {
  final String symbol;
  final double spot;
  final double support;
  final double resistance;
  final Color accent;

  const _BarrierSlider({
    required this.symbol, required this.spot,
    required this.support, required this.resistance,
    required this.accent
  });

  @override
  Widget build(BuildContext context) {
    double progress = 0.5;
    if (resistance > support) {
      progress = ((spot - support) / (resistance - support)).clamp(0.0, 1.0);
    }

    return Container(
       padding: const EdgeInsets.all(16),
       decoration: BoxDecoration(
          color: kSurface.withOpacity(0.4),
          borderRadius: BorderRadius.circular(12.0),
          border: Border.all(color: Colors.white.withOpacity(0.03)),
       ),
       child: Column(
          children: [
             Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                 Text(symbol, style: TextStyle(color: accent, fontWeight: FontWeight.bold, fontSize: 13)),
                 Text('Spot: ${spot.toStringAsFixed(1)}', style: const TextStyle(color: Colors.white70, fontSize: 11)),
             ]),
             const SizedBox(height: 14),
             Stack(
               children: [
                  Container(height: 8.0, decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(4.0))),
                  FractionallySizedBox(
                     widthFactor: progress,
                     child: Container(height: 8.0, decoration: BoxDecoration(color: accent.withOpacity(0.4), borderRadius: BorderRadius.circular(4.0))),
                  ),
               ]
             ),
             const SizedBox(height: 10),
             Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                 Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('SUPPORT', style: TextStyle(color: Colors.white38, fontSize: 8, letterSpacing: 0.5)),
                    Text(support.toInt().toString(), style: const TextStyle(color: kGreen, fontSize: 12, fontWeight: FontWeight.w900)),
                 ]),
                 Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    const Text('RESISTANCE', style: TextStyle(color: Colors.white38, fontSize: 8, letterSpacing: 0.5)),
                    Text(resistance.toInt().toString(), style: const TextStyle(color: kRed, fontSize: 12, fontWeight: FontWeight.w900)),
                 ]),
             ]),
          ]
       )
    );
  }
}

// ── ADVANCED VISUALS: OI BUILDUP HEATMAP ──────────────────────────────────
class _OIBuildUpHeatmap extends StatefulWidget {
  final String symbol;
  final QuickSummary? summary;
  final String? date;
  final List<OiStat> oiStats;

  const _OIBuildUpHeatmap({required this.symbol, required this.summary, required this.date, required this.oiStats});

  @override
  _OIBuildUpHeatmapState createState() => _OIBuildUpHeatmapState();
}

class _OIBuildUpHeatmapState extends State<_OIBuildUpHeatmap> {
  List<OptionData>? _chain;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _fetchChain();
  }

  @override
  void didUpdateWidget(covariant _OIBuildUpHeatmap oldWidget) {
    if (oldWidget.summary?.timestamp != widget.summary?.timestamp) {
      _fetchChain();
    }
    super.didUpdateWidget(oldWidget);
  }

  Future<void> _fetchChain() async {
    if (widget.date == null || widget.summary == null) return;
    setState(() => _loading = true);
    try {
      final chain = await ApiService().getData(widget.symbol, widget.summary!.timestamp, widget.date!);
      if (mounted) setState(() => _chain = chain);
    } catch (e) {
      // Ignore silence
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _chain == null || _chain!.isEmpty || widget.summary?.atm == null) {
      return const SizedBox.shrink(); // Hide while loading or unavailable
    }

    final atm = widget.summary!.atm!;
    final List<OptionData> relevant = [];
    
    // Find closest to ATM
    int atmIndex = -1;
    double minDiff = double.infinity;
    for (int i = 0; i < _chain!.length; i++) {
      final diff = (_chain![i].strikePrice - atm).abs();
      if (diff < minDiff) { minDiff = diff; atmIndex = i; }
    }

    if (atmIndex != -1) {
      final start = (atmIndex - 4).clamp(0, _chain!.length);
      final end = (atmIndex + 5).clamp(0, _chain!.length);
      relevant.addAll(_chain!.sublist(start, end));
    } else {
      return const SizedBox.shrink();
    }

    Widget buildBlock(double strike, OptionSide side, String type) {
      // Determine Buildup logic
      Color bgColor = kSurface;
      String label = '-';
      
      double chg = side.change ?? 0.0;
      int chgOi = side.changeOi ?? 0;
      
      if (chg > 0 && chgOi > 0) {
        label = 'Long Buildup'; bgColor = kGreen.withOpacity(0.3);
      } else if (chg > 0 && chgOi < 0) {
        label = 'Short Covering'; bgColor = kGreen.withOpacity(0.1);
      } else if (chg < 0 && chgOi > 0) {
        label = 'Short Buildup'; bgColor = kRed.withOpacity(0.3);
      } else if (chg < 0 && chgOi < 0) {
        label = 'Long Unwinding'; bgColor = kRed.withOpacity(0.1);
      }

      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 2.0, vertical: 4.0),
        width: 100,
        height: 60,
        decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white12)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(type, style: const TextStyle(fontSize: 10, color: Colors.white70, fontWeight: FontWeight.bold)),
            Text(label, style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.w900), textAlign: TextAlign.center),
          ]
        )
      );
    }

    return Container(
      padding: const EdgeInsets.all(24),
      width: double.infinity,
      decoration: BoxDecoration(color: kSurface.withOpacity(0.4), borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${widget.symbol} OI BUILDUP HEATMAP', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
              const Row(
                 children: [
                    Icon(Icons.square, color: kGreen, size: 10), SizedBox(width: 4), Text('Long Buildup', style: TextStyle(fontSize: 10, color: Colors.white54)),
                    SizedBox(width: 12),
                    Icon(Icons.square, color: Colors.redAccent, size: 10), SizedBox(width: 4), Text('Short Buildup', style: TextStyle(fontSize: 10, color: Colors.white54)),
                 ]
              )
            ]
          ),
          const SizedBox(height: 24),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: relevant.map((d) {
                return Column(
                  children: [
                    buildBlock(d.strikePrice, d.ce, 'CALL'),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Text(d.strikePrice.toStringAsFixed(0), style: TextStyle(fontWeight: FontWeight.bold, color: d.strikePrice == atm ? Colors.amber : Colors.white)),
                    ),
                    buildBlock(d.strikePrice, d.pe, 'PUT'),
                  ]
                );
              }).toList()
            )
          )
        ]
      )
    );
  }
}

// ── ADVANCED VISUALS: MULTI-TIMEFRAME MATRIX ──────────────────────────────────
class _MTF_Matrix extends StatelessWidget {
  final Map<String, dynamic> mtfTrend;

  const _MTF_Matrix({required this.mtfTrend});

  @override
  Widget build(BuildContext context) {
    if (mtfTrend.isEmpty) return const SizedBox.shrink();

    Widget buildMatrixGrid(String symbol, Map<String, dynamic> trends) {
       return Container(
         width: 150,
         margin: const EdgeInsets.only(right: 16),
         padding: const EdgeInsets.all(12),
         decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white12)),
         child: Column(
           crossAxisAlignment: CrossAxisAlignment.start,
           children: [
             Text(symbol, style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 13)),
             const SizedBox(height: 12),
             Wrap(
               spacing: 8, runSpacing: 8,
               children: ['5m', '15m', '1H', 'Daily'].map((tf) {
                  final String state = trends[tf] ?? 'Neutral';
                  Color c = state == 'Bullish' ? kGreen : (state == 'Bearish' ? kRed : Colors.grey);
                  return Container(
                    width: 58, height: 40,
                    decoration: BoxDecoration(
                      color: c.withOpacity(0.2), borderRadius: BorderRadius.circular(6), border: Border.all(color: c.withOpacity(0.8))
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                           Text(tf, style: const TextStyle(fontSize: 9, color: Colors.white54, fontWeight: FontWeight.bold)),
                           Text(state, style: TextStyle(fontSize: 10, color: c, fontWeight: FontWeight.w900)),
                        ]
                      )
                    )
                  );
               }).toList()
             )
           ]
         )
       );
    }

    return Container(
      padding: const EdgeInsets.all(24),
      width: double.infinity,
      decoration: BoxDecoration(color: kSurface.withOpacity(0.4), borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('⏱️ MULTI-TIMEFRAME (MTF) TREND MATRIX', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
          const SizedBox(height: 24),
          SingleChildScrollView(
             scrollDirection: Axis.horizontal,
             child: Row(
               children: [
                  if (mtfTrend.containsKey('NIFTY')) buildMatrixGrid('NIFTY', mtfTrend['NIFTY']),
                  if (mtfTrend.containsKey('BANKNIFTY')) buildMatrixGrid('BANKNIFTY', mtfTrend['BANKNIFTY']),
                  if (mtfTrend.containsKey('FINNIFTY')) buildMatrixGrid('FINNIFTY', mtfTrend['FINNIFTY']),
               ]
             )
          )
        ]
      )
    );
  }
}
