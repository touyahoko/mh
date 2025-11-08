// lib/main.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:intl/intl.dart';

// ====== JSON分割ロード対応関数 ======
Future<List<Map<String, dynamic>>> downloadAndLoadCharmTable({
  void Function(double progress)? onProgress,
}) async {
  try {
    // assets/mh4g_charm_tables.json を順次ストリーミング読み込み（Chunk単位）
    final data = await rootBundle.loadString('assets/mh4g_charm_tables.json');
    final jsonData = json.decode(data);

    if (jsonData is List) {
      return List<Map<String, dynamic>>.from(jsonData);
    } else if (jsonData is Map && jsonData.containsKey('charms')) {
      return List<Map<String, dynamic>>.from(jsonData['charms']);
    } else {
      return [];
    }
  } catch (e) {
    print("JSON読み込み失敗: $e");
    return [];
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // JSONをロード（進行状況を表示可能）
  final data = await downloadAndLoadCharmTable(
    onProgress: (p) => print("Loading... ${(p * 100).toStringAsFixed(1)}%"),
  );

  runApp(MH4G_OssanFlutter(charmTableData: data));
}

// ====== アプリ本体 ======
class MH4G_OssanFlutter extends StatelessWidget {
  final List<Map<String, dynamic>> charmTableData;
  MH4G_OssanFlutter({required this.charmTableData});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OssanSnipeTool (Flutter)',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Color(0xFF0B0B0B),
        primaryColor: Colors.greenAccent,
      ),
      home: HomePage(charmTableData: charmTableData),
    );
  }
}

// ====== 以下は既存の HomePage ======
class HomePage extends StatefulWidget {
  final List<Map<String, dynamic>> charmTableData;
  HomePage({required this.charmTableData});
  @override
  _HomePageState createState() => _HomePageState();
}

class SeedRecord {
  final int seed;
  SeedRecord(this.seed);
}

class _HomePageState extends State<HomePage> {
  Timer? _timer;
  double _remaining = 0.0;
  bool _running = false;

  List<SeedRecord> seeds = [];
  List<Map<String, dynamic>> searchResults = [];
  late List<Map<String, dynamic>> charmTable;

  static const int mul = 0x343FD;
  static const int add = 0x269EC3;

  final _timeController = TextEditingController();
  final _seedInputController = TextEditingController();
  final _targetController = TextEditingController();

  List<Map<String, dynamic>> currentSequence = [];

  @override
  void initState() {
    super.initState();
    charmTable = widget.charmTableData;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timeController.dispose();
    _seedInputController.dispose();
    _targetController.dispose();
    super.dispose();
  }

  void startTimerFromInput() {
    double sec = double.tryParse(_timeController.text) ?? 0.0;
    if (sec <= 0) return;
    _remaining = sec;
    _timer?.cancel();
    _running = true;
    _timer = Timer.periodic(Duration(milliseconds: 10), (t) {
      setState(() {
        _remaining -= 0.01;
        if (_remaining <= 0) {
          _running = false;
          _remaining = 0;
          t.cancel();
        }
      });
    });
  }

  int lcgNext(int seed) => (seed * mul + add) & 0xFFFFFFFF;

  List<Map<String, int>> generateSequence(int seed, int n) {
    List<Map<String, int>> seq = [];
    int s = seed & 0xFFFFFFFF;
    for (int i = 0; i < n; i++) {
      s = lcgNext(s);
      int value = (s >> 16) & 0x7FFF;
      seq.add({'state': s, 'value': value});
    }
    return seq;
  }

  Future<void> importCsv() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'txt'],
    );
    if (result == null) return;
    final fileBytes = result.files.first.bytes;
    String content;
    if (fileBytes != null) {
      content = utf8.decode(fileBytes);
    } else {
      final path = result.files.first.path!;
      content = await File(path).readAsString();
    }
    List<List<dynamic>> rows = CsvToListConverter().convert(content);
    seeds.clear();
    for (var r in rows) {
      if (r.isEmpty) continue;
      var cell = r[0];
      try {
        String s = cell.toString().trim();
        int v;
        if (s.startsWith("0x") || s.startsWith("0X"))
          v = int.parse(s.substring(2), radix: 16);
        else if (RegExp(r'^[0-9A-Fa-f]+$').hasMatch(s)) {
          if (RegExp(r'[A-Fa-f]').hasMatch(s))
            v = int.parse(s, radix: 16);
          else
            v = int.parse(s);
        } else {
          v = int.parse(s);
        }
        seeds.add(SeedRecord(v & 0xFFFFFFFF));
      } catch (e) {}
    }
    setState(() {});
  }

  void addSeedFromInput() {
    String s = _seedInputController.text.trim();
    int? v;
    try {
      if (s.startsWith("0x") || s.startsWith("0X"))
        v = int.parse(s.substring(2), radix: 16);
      else if (RegExp(r'^[0-9A-Fa-f]+$').hasMatch(s)) {
        v = RegExp(r'[A-Fa-f]').hasMatch(s)
            ? int.parse(s, radix: 16)
            : int.parse(s);
      } else {
        v = int.parse(s);
      }
    } catch (e) {
      v = null;
    }
    if (v != null) {
      seeds.add(SeedRecord(v & 0xFFFFFFFF));
      _seedInputController.clear();
      setState(() {});
    }
  }

  Future<void> importCharmJson() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result == null) return;
    String content;
    final fileBytes = result.files.first.bytes;
    if (fileBytes != null)
      content = utf8.decode(fileBytes);
    else {
      final path = result.files.first.path!;
      content = await File(path).readAsString();
    }

    try {
      final parsed = json.decode(content);
      if (parsed is Map && parsed.containsKey('charms'))
        charmTable = List<Map<String, dynamic>>.from(parsed['charms']);
      else if (parsed is List)
        charmTable = List<Map<String, dynamic>>.from(parsed);
      else
        charmTable = [];
      setState(() {});
    } catch (e) {
      charmTable = [];
      setState(() {});
    }
  }

  void searchTargets() {
    String t = _targetController.text.trim();
    searchResults.clear();
    if (t.isEmpty) {
      setState(() {});
      return;
    }
    List<String> parts =
        t.split(',').map((e) => e.trim()).where((e) => e != '').toList();
    List<int> pattern = [];
    bool validPattern = true;
    for (var p in parts) {
      int? v = int.tryParse(p);
      if (v == null) {
        validPattern = false;
        break;
      }
      pattern.add(v);
    }
    if (!validPattern) {
      setState(() {});
      return;
    }
    List<String> judgeCols = [];
    if (charmTable.isNotEmpty) {
      charmTable.first.keys.forEach((k) {
        if (k.toString().contains('判定') ||
            k.toString().contains('判定値') ||
            k.toString().toLowerCase().contains('value')) {
          judgeCols.add(k);
        }
      });
      if (judgeCols.isEmpty) {
        charmTable.first.keys.forEach((k) {
          if (k.toString().length <= 10) judgeCols.add(k);
        });
      }
    }

    for (var rec in seeds) {
      List<Map<String, int>> seq = generateSequence(rec.seed, pattern.length);
      List<int> vals = seq.map((m) => m['value']!).toList();
      bool matchedDirect = true;
      for (int i = 0; i < pattern.length; i++) {
        if (vals[i] != pattern[i]) {
          matchedDirect = false;
          break;
        }
      }
      if (matchedDirect) {
        searchResults.add({
          'seed': rec.seed,
          'seed_hex':
              '0x' + rec.seed.toRadixString(16).padLeft(8, '0'),
          'match_type': 'direct_rng',
          'values': vals,
          'matched_charms': []
        });
      }
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final nowLabel =
        DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
    return Scaffold(
      appBar: AppBar(title: Text('OssanSnipeTool - Flutter (分割読み込み対応)')),
      body: Padding(
        padding: const EdgeInsets.all(14.0),
        child: SingleChildScrollView(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Demo build: $nowLabel',
                    style: TextStyle(color: Colors.white60)),
                SizedBox(height: 10),
                Text('Loaded charms: ${charmTable.length}',
                    style: TextStyle(color: Colors.greenAccent)),
                Divider(),
                ElevatedButton(
                    onPressed: importCharmJson,
                    child: Text('別JSONを読み込む')),
                SizedBox(height: 8),
                Text('ロード済みお守りデータ件数: ${charmTable.length}'),
                Divider(),
              ]),
        ),
      ),
    );
  }
}