/// File save + share helper (Phase 5): writes export text to the app
/// documents dir, then opens the platform share sheet.
library;

import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Writes [content] to `filename` under the app documents dir and shares it.
/// Returns the saved path. Throws a user-showable message string on failure.
Future<String> saveAndShare(String filename, String content) async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsString(content, flush: true);
    await SharePlus.instance.share(
      ShareParams(files: <XFile>[XFile(file.path)], text: filename),
    );
    return file.path;
  } catch (e) {
    throw 'Could not save $filename: $e';
  }
}
