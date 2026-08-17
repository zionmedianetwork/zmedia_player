import Foundation

/// Centralized console logging for the zmedia_player plugin (H-03).
///
/// Every native call site in this plugin used a raw `print(...)` — roughly
/// 268 of them, none guarded — so diagnostic strings, including media,
/// manifest and FairPlay certificate URLs, shipped straight to a release
/// build's console/device log. `zlog` is a mechanical drop-in replacement
/// for `print` that every one of those call sites now uses instead.
///
/// In RELEASE builds the body compiles out entirely via `#if DEBUG`, so the
/// `message` autoclosure — and therefore any string interpolation used to
/// build it — is never evaluated and nothing is emitted. In DEBUG builds it
/// behaves exactly like `print`.
///
/// This single-helper approach was chosen over wrapping each of the ~268
/// call sites individually in `#if DEBUG { ... }` blocks, or converting
/// each to `os_log`/`Logger` with a hand-picked privacy annotation:
///  - It requires no per-site privacy-level judgement calls.
///  - The guarantee is "nothing logs in Release" rather than "logs but
///    redacted", which is the stronger of the two options H-03 allows for.
///  - It is a single mechanical substitution (`print(` -> `zlog(`) instead
///    of ~268 bespoke edits, so it doesn't touch call-site formatting or
///    risk transcription errors across ten files.
///
/// Call sites that interpolate a URL (media/manifest/license/certificate)
/// additionally route it through `redactedURL(_:)` below, since those still
/// print in DEBUG builds and query strings on those URLs can carry
/// signed-cookie or DRM auth tokens.
@inline(__always)
func zlog(_ message: @autoclosure () -> String) {
    #if DEBUG
    print(message())
    #endif
}

/// Strips the query string from a URL-shaped string before it is logged.
///
/// Query strings on media/manifest/license/certificate URLs frequently carry
/// signed-cookie or DRM auth tokens (H-03). Scheme/host/path are kept for
/// diagnostic value; everything from `?` onward is replaced. Applied even
/// though the call sites go through `zlog` (DEBUG-only), because a local
/// developer console/device log is still not somewhere token material
/// should linger.
func redactedURL(_ urlString: String) -> String {
    guard let queryStart = urlString.firstIndex(of: "?") else { return urlString }
    return String(urlString[urlString.startIndex..<queryStart]) + "?<redacted>"
}
