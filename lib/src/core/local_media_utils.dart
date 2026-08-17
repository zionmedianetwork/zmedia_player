/// Helpers for building [MediaItem] URLs that point at a file on the local
/// filesystem (C-02 Stage 1 — local file playback).
library;

/// Utilities for constructing `file://` URLs suitable for
/// `MediaItem.url`/`DrmConfig` inputs.
///
/// [InputValidator.validateUrl] (see `security/input_validation.dart`)
/// accepts `file://` URIs for media playback but deliberately does NOT
/// accept bare filesystem paths (e.g. `/data/user/0/.../movie.mp4`) — every
/// other URL this package accepts is scheme-qualified, and a bare path
/// handed straight to native code has, elsewhere in this codebase, caused
/// bugs for paths containing spaces or other characters that need percent
/// encoding. [fileUri] does that conversion correctly (delegating to
/// `dart:core`'s `Uri.file`) so callers never have to hand-build a
/// `file://` string.
///
/// Example:
/// ```dart
/// final path = '${(await getApplicationDocumentsDirectory()).path}/clip.mp4';
/// final item = MediaItem(
///   id: 'local-clip',
///   title: 'Local clip',
///   url: LocalMediaUtils.fileUri(path),
/// );
/// ```
class LocalMediaUtils {
  const LocalMediaUtils._();

  /// Converts a filesystem [path] (as returned by, e.g.,
  /// `path_provider`'s `getApplicationDocumentsDirectory()`) into a
  /// `file://` URL string that [InputValidator.validateUrl] and
  /// `MediaItem.url` accept.
  ///
  /// [path] must be an absolute path. Set [windows] to force
  /// Windows-style path parsing (drive letters, backslashes) regardless of
  /// the host platform this code is running on; by default it is inferred
  /// from `Platform.isWindows` via `Uri.file`'s own default.
  static String fileUri(String path, {bool? windows}) {
    return Uri.file(path, windows: windows).toString();
  }
}
