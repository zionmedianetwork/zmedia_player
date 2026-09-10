import AVFoundation
import Foundation

/// Builds an `AVURLAsset` for [url] that carries the item's
/// `MediaItem.httpHeaders` on **every** request AVFoundation makes for it.
///
/// Extracted so that every asset this plugin creates for a media URL is built
/// the same way. There are two of them, and they used to disagree:
///
///  - `MediaPlayerManager.swift`'s `loadMediaItem` — playback. Always applied
///    the headers.
///  - `NotificationHandler.swift`'s `generateThumbnail` — the video-frame
///    fallback used as notification/Now Playing artwork when the item has no
///    `artworkUrl`. Built its asset as a bare `AVURLAsset(url:)`, so the frame
///    fetch was an **unauthenticated** HTTP request and returned 401/403
///    against an authenticated or signed media URL, silently leaving the
///    notification with no artwork. Same defect family as issue #127
///    ("headers don't reach every request"), one layer up.
///
/// A single helper is what keeps them from diverging again: a third caller
/// that needs an asset for a media URL gets the headers by construction.
///
/// - Parameters:
///   - url: the media URL. Also supplies the host used for cookie scoping.
///   - httpHeaders: `mediaItem["httpHeaders"]` verbatim. `nil` or empty means
///     no options are applied and a plain `AVURLAsset(url:)` is returned —
///     the correct, unchanged behavior for an unauthenticated URL.
///   - logTag: prefix for this call site's `zlog` lines, so the existing
///     `MediaPlayerInstance: …` diagnostics keep reading the way they did.
func makeAVURLAsset(
    url: URL,
    httpHeaders: [String: String]?,
    logTag: String
) -> AVURLAsset {
    guard let httpHeaders = httpHeaders, !httpHeaders.isEmpty else {
        return AVURLAsset(url: url)
    }

    var headerFields = httpHeaders
    var options: [String: Any] = [:]
    // Signed-cookie auth (e.g. CloudFront live/VOD): AVFoundation does NOT
    // reliably apply a custom "Cookie" HTTP header to every request the
    // AVPlayer makes — playlist refreshes and segment fetches run out of
    // process in mediaplaybackd and intermittently drop the header,
    // producing HTTP 403s (CoreMediaErrorDomain -12660), especially on long
    // or live streams. Forwarding the cookies via AVURLAssetHTTPCookiesKey
    // makes AVFoundation apply them to ALL requests.
    if let cookieHeader = httpHeaders["Cookie"], !cookieHeader.isEmpty {
        let host = url.host ?? ""
        var cookies: [HTTPCookie] = []
        for pair in cookieHeader.components(separatedBy: ";") {
            let trimmed = pair.trimmingCharacters(in: .whitespaces)
            guard let eq = trimmed.firstIndex(of: "="), !trimmed.isEmpty else { continue }
            let name = String(trimmed[..<eq])
            let value = String(trimmed[trimmed.index(after: eq)...])
            if name.isEmpty { continue }
            var props: [HTTPCookiePropertyKey: Any] = [
                .name: name,
                .value: value,
                .domain: host,
                .path: "/",
                .version: "0",
                .expires: Date(timeIntervalSinceNow: 6 * 3600),
            ]
            props[HTTPCookiePropertyKey("Secure")] = "TRUE"
            if let cookie = HTTPCookie(properties: props) {
                cookies.append(cookie)
            } else {
                zlog("\(logTag): HTTPCookie construction failed for cookie \(name)")
            }
        }
        if !cookies.isEmpty {
            options["AVURLAssetHTTPCookiesKey"] = cookies
            // Remove the Cookie HTTP header: when BOTH the header and the
            // cookies key are set, AVFoundation prefers the header (which it
            // drops on some out-of-process requests). Using only the cookies
            // key applies the cookies to every request.
            headerFields.removeValue(forKey: "Cookie")
            zlog("\(logTag): forwarding \(cookies.count) cookie(s) via AVURLAssetHTTPCookiesKey for host \(host)")
        }
    }
    if !headerFields.isEmpty {
        options["AVURLAssetHTTPHeaderFieldsKey"] = headerFields
    }
    return options.isEmpty ? AVURLAsset(url: url) : AVURLAsset(url: url, options: options)
}
