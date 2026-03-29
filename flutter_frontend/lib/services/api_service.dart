import 'dart:html' as html;
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/option_data.dart';

class ApiService {
  // ⚡ Use a relative path so nginx can proxy /api → backend:5000
  // This avoids cross-origin (CORS) failures when browser hits port 8080 but API is on 5000
  static const String _base = '/api';
  static String get baseUrl => 'http://${_currentHost()}/api';
  
  static String _currentHost() {
    try {
      return html.window.location.hostname ?? '127.0.0.1';
    } catch(e) { return '127.0.0.1'; }
  }
  
  static const _fast = Duration(seconds: 60);
  static const _slow = Duration(seconds: 120);

  // ── PHASE 1: one fast call for signals+spots+PCR ─────────
  Future<Map<String, QuickSummary>> getQuickSummary(String? date, [String? time]) async {
    String url = '$_base/quick_summary';
    final params = <String>[];
    if (date != null) params.add('date=$date');
    if (time != null) params.add('time=$time');
    if (params.isNotEmpty) url += '?${params.join('&')}';

    final r = await http.get(Uri.parse(url)).timeout(_fast);
    if (r.statusCode == 200) {
      final Map<String, dynamic> data = json.decode(r.body);
      return data.map((k, v) => MapEntry(k, QuickSummary.fromJson(v)));
    }
    throw Exception('quick_summary failed: ${r.statusCode}');
  }

  // ── PHASE 1.5: MTF Trend ─────────
  Future<Map<String, dynamic>> getMtfTrend() async {
    final r = await http.get(Uri.parse('$_base/mtf_trend')).timeout(_fast);
    if (r.statusCode == 200) return json.decode(r.body) as Map<String, dynamic>;
    throw Exception('mtf_trend failed: ${r.statusCode}');
  }

  // ── PHASE 2: OI stats (skip max pain for speed) ──────────
  Future<List<OiStat>> getOiStats(String symbol, String date,
      {bool skipMaxPain = false, String? time}) async {
    String url = '$_base/oi_stats?symbol=$symbol&date=$date';
    if (skipMaxPain) url += '&skip_max_pain=true';
    if (time != null) url += '&time=$time';

    final r = await http.get(Uri.parse(url)).timeout(_slow);
    if (r.statusCode == 200) {
      final List<dynamic> data = json.decode(r.body);
      return data.map((e) => OiStat.fromJson(e)).toList();
    }
    throw Exception('oi_stats failed: ${r.statusCode}');
  }

  // ── PHASE 3: Option chain ─────────────────────────────────
  Future<List<String>> getDates() async {
    final r = await http.get(Uri.parse('$_base/dates')).timeout(_fast);
    if (r.statusCode == 200) return List<String>.from(json.decode(r.body));
    throw Exception('dates failed: ${r.statusCode}');
  }

  Future<List<String>> getTimestamps(String symbol, String date) async {
    final r = await http
        .get(Uri.parse('$_base/timestamps?symbol=$symbol&date=$date'))
        .timeout(_fast);
    if (r.statusCode == 200) return List<String>.from(json.decode(r.body));
    throw Exception('timestamps failed: ${r.statusCode}');
  }

  Future<List<OptionData>> getData(
      String symbol, String timestamp, String date) async {
    final url =
        '$_base/data?symbol=$symbol&timestamp=${Uri.encodeComponent(timestamp)}&date=$date';
    final r = await http.get(Uri.parse(url)).timeout(_fast);
    if (r.statusCode == 200) {
      final List<dynamic> data = json.decode(r.body);
      return data.map((e) => OptionData.fromJson(e)).toList();
    }
    throw Exception('data failed: ${r.statusCode}');
  }

  // ── PHASE 4: Execute Trade ─────────────────────────────────
  Future<bool> executeTrade(String symbol, String action, double atm) async {
    final url = '$_base/execute_trade';
    final r = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'symbol': symbol, 'action': action, 'atm': atm}),
    ).timeout(_fast);
    
    if (r.statusCode == 200) {
      final data = json.decode(r.body);
      return data['success'] == true;
    }
    return false;
  }

  // ── PHASE 5: Trading State & Auto Trade ────────────────────
  Future<Map<String, dynamic>> getTradingState() async {
    final r = await http.get(Uri.parse('$_base/trading_state')).timeout(_fast);
    if (r.statusCode == 200) {
      return json.decode(r.body) as Map<String, dynamic>;
    }
    throw Exception('trading_state failed');
  }

  Future<bool> toggleTradingConfig({bool? paperTrading, bool? tradingEnabled}) async {
    final body = <String, dynamic>{};
    if (paperTrading != null) body['paper_trading'] = paperTrading;
    if (tradingEnabled != null) body['trading_enabled'] = tradingEnabled;

    final r = await http.post(
      Uri.parse('$_base/trading_state/toggle'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(body),
    ).timeout(_fast);
    return r.statusCode == 200;
  }
  
  Future<bool> closePosition(String symbol) async {
    final r = await http.post(
      Uri.parse('$_base/close_position'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'symbol': symbol}),
    ).timeout(_fast);
    return r.statusCode == 200;
  }

  Future<List<dynamic>> getTradeHistory() async {
    final r = await http.get(Uri.parse('$_base/trade_history')).timeout(_fast);
    if (r.statusCode == 200) {
      return json.decode(r.body) as List<dynamic>;
    }
    throw Exception('trade_history failed');
  }

  Future<bool> login(String password) async {
    final r = await http.post(
      Uri.parse('$_base/login'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'password': password}),
    ).timeout(_fast);
    return r.statusCode == 200;
  }

  Future<List<String>> getLogs() async {
    final r = await http.get(Uri.parse('$_base/logs')).timeout(_fast);
    if (r.statusCode == 200) {
      final data = json.decode(r.body);
      return List<String>.from(data['logs'] ?? []);
    }
    throw Exception('logs failed');
  }

  Future<Map<String, dynamic>> getMarketExtras() async {
    final r = await http.get(Uri.parse('$_base/market_extras')).timeout(_fast);
    if (r.statusCode == 200) {
      return json.decode(r.body) as Map<String, dynamic>;
    }
    throw Exception('market_extras failed');
  }

  Future<List<dynamic>> getOiHistograms(String symbol, [String? date, String? time, int? interval]) async {
    String url = '$_base/oi_histograms?symbol=$symbol';
    if (date != null) url += '&date=$date';
    if (time != null) url += '&time=$time';
    if (interval != null) url += '&interval=$interval';
    final r = await http.get(Uri.parse(url)).timeout(_fast);
    if (r.statusCode == 200) {
      return json.decode(r.body) as List<dynamic>;
    }
    throw Exception('oi_histograms failed');
  }
}
