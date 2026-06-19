import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// Photo resize-and-store helper for Tranche 2 offline queue.
///
/// Sub-area 2 (§5.2): image_picker already sets maxWidth:1280 / quality:80 on
/// supported devices. As a defensive second pass (some devices ignore picker
/// params), this helper:
///   1. Decodes the source file via the `image` package.
///   2. Resizes to 1280px on the longer edge (preserving aspect ratio).
///   3. Re-encodes as JPEG quality 80.
///   4. Writes to getApplicationDocumentsDirectory() with a unique name.
///   5. Returns the absolute file path.
///
/// The returned path is stored in pending_pickups (before_photo / after_photo)
/// and in pickup_drafts (before_photo_path / after_photo_path).
///
/// Photo cleanup:
///   - Call deletePhoto(path) after a successful queue flush (row deleted).
///   - Call deletePhoto(path) when a queued item is discarded from the UI.
///   - Draft photos are cleaned up when the draft is deleted on successful enqueue.
class PhotoStore {
  static const int _maxEdge = 1280;
  static const int _jpegQuality = 80;

  /// Resize-and-store [sourceFile] into the app documents directory.
  /// [prefix] is a short label like 'before' or 'after'.
  /// Returns the absolute path of the stored file.
  static Future<String> storePhoto(File sourceFile,
      {String prefix = 'photo'}) async {
    final bytes = await sourceFile.readAsBytes();

    // Decode — falls back to original bytes if decoding fails
    img.Image? decoded = img.decodeImage(bytes);
    if (decoded == null) {
      // Fallback: write original bytes unchanged
      return _writeBytes(bytes, prefix);
    }

    // Resize if either dimension exceeds _maxEdge
    if (decoded.width > _maxEdge || decoded.height > _maxEdge) {
      if (decoded.width >= decoded.height) {
        decoded = img.copyResize(decoded, width: _maxEdge);
      } else {
        decoded = img.copyResize(decoded, height: _maxEdge);
      }
    }

    final resized = img.encodeJpg(decoded, quality: _jpegQuality);
    return _writeBytes(resized, prefix);
  }

  static Future<String> _writeBytes(List<int> bytes, String prefix) async {
    final dir = await getApplicationDocumentsDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final filename = '${prefix}_$ts.jpg';
    final path = p.join(dir.path, filename);
    await File(path).writeAsBytes(bytes);
    return path;
  }

  /// Delete a stored photo file. No-op if the file does not exist.
  static Future<void> deletePhoto(String? path) async {
    if (path == null || path.isEmpty) return;
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {
      // Best-effort — don't crash on cleanup failure
    }
  }
}
