import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive.dart';

/// 巨大JSON＋オフラインキャッシュ対応版
Future<Map<String, dynamic>?> downloadAndLoadCharmTable({
  void Function(double progress)? onProgress,
}) async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final cacheFile = File('${dir.path}/mh4g_charm_tables_cache.json');

    // 🔁 すでにキャッシュがある場合はそれを即ロード
    if (await cacheFile.exists()) {
      print("✅ Using cached charm table: ${cacheFile.path}");
      final cachedData = await _readLargeJson(cacheFile, null);
      return cachedData;
    }

    // 🔗 GitHubリリースZIP（ここをあなたのURLに変更）
    const url =
        "https://github.com/touyahoko/mh/releases/download/v1.0/mh4g_charm_tables.zip";

    print("⬇️ Downloading charm table...");
    final response = await http.get(Uri.parse(url));

    if (response.statusCode != 200) {
      print("❌ Download failed: ${response.statusCode}");
      return null;
    }

    // 一時フォルダにZIP保存
    final tmpDir = await getTemporaryDirectory();
    final zipPath = '${tmpDir.path}/mh4g_charm_tables.zip';
    final file = File(zipPath);
    await file.writeAsBytes(response.bodyBytes);

    print("📦 Unzipping...");
    final archive = ZipDecoder().decodeBytes(file.readAsBytesSync());

    // JSONファイルを探して分割読み込み
    for (final entry in archive) {
      if (entry.name.endsWith('.json')) {
        final outPath = '${tmpDir.path}/${entry.name}';
        File(outPath)
          ..createSync(recursive: true)
          ..writeAsBytesSync(entry.content as List<int>);
        print("📄 Found JSON: $outPath");

        // 分割ストリーム読み込み
        final data = await _readLargeJson(File(outPath), onProgress);

        // キャッシュ保存
        await cacheFile.writeAsString(jsonEncode(data));
        print("💾 Cached locally at: ${cacheFile.path}");

        return data;
      }
    }

    print("⚠️ JSON file not found in ZIP");
    return null;
  } catch (e) {
    print("❌ Error loading charm table: $e");
    return null;
  }
}

/// 巨大JSONを分割してメモリ効率的に読み込む
Future<Map<String, dynamic>> _readLargeJson(
  File file,
  void Function(double progress)? onProgress,
) async {
  final totalSize = await file.length();
  final stream = file.openRead();

  final buffer = StringBuffer();
  final Map<String, dynamic> result = {};
  int bytesRead = 0;

  final completer = Completer<Map<String, dynamic>>();

  stream.listen(
    (data) {
      bytesRead += data.length;
      if (onProgress != null && totalSize > 0) {
        onProgress(bytesRead / totalSize);
      }

      buffer.write(utf8.decode(data, allowMalformed: true));

      if (buffer.length > 1000000) {
        try {
          final partial = jsonDecode("{${_sanitizeChunk(buffer.toString())}}");
          result.addAll(partial);
          buffer.clear();
        } catch (_) {
          // 途中データはスキップ
        }
      }
    },
    onDone: () {
      try {
        final remaining = jsonDecode(buffer.toString());
        result.addAll(remaining);
      } catch (_) {}
      completer.complete(result);
    },
    onError: (err) {
      completer.completeError(err);
    },
  );

  return completer.future;
}

String _sanitizeChunk(String chunk) {
  return chunk.replaceAll(RegExp(r',\s*}'), '}').trim();
}
