
// lib/main.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:intl/intl.dart';

void main() => runApp(MH4G_OssanFlutter());

class MH4G_OssanFlutter extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OssanSnipeTool (Flutter)',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Color(0xFF0B0B0B),
        primaryColor: Colors.greenAccent,
      ),
      home: HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
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
  List<Map<String, dynamic>> charmTable = [];

  static const int mul = 0x343FD;
  static const int add = 0x269EC3;

  final _timeController = TextEditingController();
  final _seedInputController = TextEditingController();
  final _targetController = TextEditingController();

  List<Map<String, dynamic>> currentSequence = [];

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

  int lcgNext(int seed) {
    return (seed * mul + add) & 0xFFFFFFFF;
  }

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
        if (s.startsWith("0x") || s.startsWith("0X")) v = int.parse(s.substring(2), radix: 16);
        else if (RegExp(r'^[0-9A-Fa-f]+$').hasMatch(s)) {
          if (RegExp(r'[A-Fa-f]').hasMatch(s)) v = int.parse(s, radix: 16);
          else v = int.parse(s);
        } else {
          v = int.parse(s);
        }
        seeds.add(SeedRecord(v & 0xFFFFFFFF));
      } catch (e) {
      }
    }
    setState(() {});
  }

  void addSeedFromInput() {
    String s = _seedInputController.text.trim();
    int? v;
    try {
      if (s.startsWith("0x") || s.startsWith("0X")) v = int.parse(s.substring(2), radix: 16);
      else if (RegExp(r'^[0-9A-Fa-f]+$').hasMatch(s)) {
        v = RegExp(r'[A-Fa-f]').hasMatch(s) ? int.parse(s, radix: 16) : int.parse(s);
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
    if (fileBytes != null) {
      content = utf8.decode(fileBytes);
    } else {
      final path = result.files.first.path!;
      content = await File(path).readAsString();
    }
    try {
      final parsed = json.decode(content);
      if (parsed is Map && parsed.containsKey('charms')) {
        charmTable = List<Map<String, dynamic>>.from(parsed['charms']);
      } else if (parsed is List) {
        charmTable = List<Map<String, dynamic>>.from(parsed);
      } else {
        charmTable = [];
      }
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
    List<String> parts = t.split(',').map((e) => e.trim()).where((e)=>e!='').toList();
    List<int> pattern = [];
    bool validPattern = true;
    for (var p in parts) {
      int? v = int.tryParse(p);
      if (v == null) { validPattern=false; break; }
      pattern.add(v);
    }
    if (!validPattern) {
      setState(() {});
      return;
    }
    List<String> judgeCols = [];
    if (charmTable.isNotEmpty) {
      charmTable.first.keys.forEach((k) {
        if (k.toString().contains('判定') || k.toString().contains('判定値') || k.toString().toLowerCase().contains('value')) {
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
      List<Map<String,int>> seq = generateSequence(rec.seed, pattern.length);
      List<int> vals = seq.map((m) => m['value']!).toList();
      bool matchedDirect = true;
      for (int i = 0; i < pattern.length; i++) {
        if (vals[i] != pattern[i]) { matchedDirect = false; break; }
      }
      if (matchedDirect) {
        searchResults.add({
          'seed': rec.seed,
          'seed_hex': '0x' + rec.seed.toRadixString(16).padLeft(8, '0'),
          'match_type': 'direct_rng',
          'values': vals,
          'matched_charms': []
        });
      }
      List<Map<String,dynamic>> matchedCharmRows = [];
      if (charmTable.isNotEmpty && judgeCols.isNotEmpty) {
        for (int i = 0; i < vals.length; i++) {
          int v = vals[i];
          for (var row in charmTable) {
            for (var jc in judgeCols) {
              try {
                var cell = row[jc];
                if (cell == null) continue;
                if (cell is num) {
                  if (cell == v) {
                    matchedCharmRows.add({'seed': rec.seed, 'pos': i, 'value': v, 'charm': row});
                    break;
                  }
                } else {
                  var s = cell.toString();
                  int? iv = int.tryParse(s);
                  if (iv != null && iv == v) {
                    matchedCharmRows.add({'seed': rec.seed, 'pos': i, 'value': v, 'charm': row});
                    break;
                  }
                }
              } catch (e) {
                continue;
              }
            }
          }
        }
      }
      if (matchedCharmRows.isNotEmpty) {
        searchResults.add({
          'seed': rec.seed,
          'seed_hex': '0x' + rec.seed.toRadixString(16).padLeft(8, '0'),
          'match_type': 'table_match',
          'values': vals,
          'matched_charms': matchedCharmRows
        });
      }
    }
    setState(() {});
  }

  void pickSeedAndShowSequence(int seed) {
    currentSequence = generateSequence(seed, 20).map((m) => {'s': m['state'], 'v': m['value']}).toList();
    setState(() {});
  }

  Widget seedListWidget() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Loaded seeds: ${seeds.length}', style: TextStyle(color: Colors.greenAccent)),
        SizedBox(height: 6),
        Container(
          height: 140,
          decoration: BoxDecoration(
            color: Color(0xFF101010),
            borderRadius: BorderRadius.circular(8),
          ),
          child: ListView.builder(
            itemCount: seeds.length,
            itemBuilder: (_, i) {
              final s = seeds[i];
              return ListTile(
                dense: true,
                title: Text('seed: ${s.seed}  (0x${s.seed.toRadixString(16).padLeft(8,'0')})', style: TextStyle(fontFamily: 'monospace')),
                trailing: IconButton(
                  icon: Icon(Icons.visibility),
                  onPressed: () => pickSeedAndShowSequence(s.seed),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget searchResultsWidget() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Search results: ${searchResults.length}', style: TextStyle(color: Colors.greenAccent)),
        SizedBox(height: 6),
        ...searchResults.map((r) => ListTile(
          dense: true,
          title: Text('${r['seed_hex']} -> ${r['match_type']}  values=${r['values']}', style: TextStyle(fontFamily: 'monospace')),
          subtitle: r['matched_charms'] != null && (r['matched_charms'] as List).isNotEmpty
              ? Text('matched charms: ${(r['matched_charms'] as List).take(3).map((m)=> m['charm'].toString()).join(" | ")}', maxLines: 2, overflow: TextOverflow.ellipsis)
              : null,
          onTap: () => pickSeedAndShowSequence(r['seed']),
        ))
      ],
    );
  }

  Widget sequenceWidget() {
    if (currentSequence.isEmpty) return Text('No sequence selected', style: TextStyle(color: Colors.white70));
    return Container(
      padding: EdgeInsets.all(8),
      decoration: BoxDecoration(color: Color(0xFF0F0F0F), borderRadius: BorderRadius.circular(6)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: currentSequence.map((m) =>
          Text('state=0x${m['s'].toRadixString(16).padLeft(8,'0')}  val=${m['v']}', style: TextStyle(fontFamily: 'monospace'))
        ).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nowLabel = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
    return Scaffold(
      appBar: AppBar(title: Text('OssanSnipeTool - Flutter (ver.1.1 prototype)')),
      body: Padding(
        padding: const EdgeInsets.all(14.0),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Demo build: $nowLabel', style: TextStyle(color: Colors.white60)),
            SizedBox(height: 10),
            Text('Timer', style: TextStyle(fontSize: 18, color: Colors.greenAccent)),
            Row(children: [
              Expanded(child: TextField(controller: _timeController, keyboardType: TextInputType.numberWithOptions(decimal:true), decoration: InputDecoration(labelText: '秒で入力 (例 5.630)'))),
              SizedBox(width: 8),
              ElevatedButton(onPressed: startTimerFromInput, child: Text('開始')),
            ]),
            SizedBox(height: 6),
            Text('残り: ${_remaining.toStringAsFixed(3)} s', style: TextStyle(fontSize: 16)),
            Divider(),
            Row(children: [
              ElevatedButton(onPressed: importCsv, child: Text('CSVからシード読み込み')),
              SizedBox(width: 8),
              ElevatedButton(onPressed: importCharmJson, child: Text('Import charm JSON')),
            ]),
            SizedBox(height: 8),
            Row(children: [
              Expanded(child: TextField(controller: _seedInputController, decoration: InputDecoration(labelText: '手動シード追加 (10進 or 0xHEX)'))),
              SizedBox(width: 8),
              ElevatedButton(onPressed: addSeedFromInput, child: Text('追加')),
            ]),
            SizedBox(height: 12),
            seedListWidget(),
            Divider(),
            Text('狙いのお守り検索（プロトタイプ）', style: TextStyle(fontSize: 18, color: Colors.greenAccent)),
            SizedBox(height: 6),
            Text('使い方: カンマ区切りの数値を入力すると、生成列の先頭と一致するシードを探します。\nまたは生成値がテーブル中の「判定値」列と一致するお守りを列挙します。', style: TextStyle(color: Colors.white70)),
            Row(children: [
              Expanded(child: TextField(controller: _targetController, decoration: InputDecoration(labelText: 'ターゲット値または列（カンマ区切り）'))),
              SizedBox(width: 8),
              ElevatedButton(onPressed: searchTargets, child: Text('検索')),
            ]),
            SizedBox(height: 8),
            searchResultsWidget(),
            Divider(),
            Text('選択シードの乱数列（最大20）', style: TextStyle(fontSize: 16, color: Colors.greenAccent)),
            SizedBox(height: 6),
            sequenceWidget(),
            SizedBox(height: 30),
            Text('注意: 実際のお守り属性に変換するにはゲームのスキルテーブル/スロットテーブルが必要です。', style: TextStyle(color: Colors.orangeAccent)),
            SizedBox(height: 30),
          ]),
        ),
      ),
    );
  }
}

import 'package:flutter/services.dart' show rootBundle;
import 'dart:convert';

Future<void> loadCharmTable() async {
  try {
    String jsonString = await rootBundle.loadString('assets/mh4g_charm_tables.json');
    Map<String, dynamic> charmData = json.decode(jsonString);
    // ここでcharmDataを使って処理
    print("チャームテーブル読み込み成功！エントリ数: ${charmData.length}");
  } catch (e) {
    print("読み込み失敗: $e");
  }
}
