import 'package:flutter/material.dart';
import 'package:zmedia_player/zmedia_player.dart';
import '../data/sample_media.dart';
import '../widgets/player_scaffold.dart';

/// Demonstrates C-03 (part a) — playing media back out of [CacheService]
/// instead of only using it to prefetch bytes into memory.
///
/// Two distinct steps, deliberately kept separate so the "works with no
/// network" claim is actually exercisable on device:
///
/// 1. **Download & cache** (`_downloadToCache`) — requires network. Calls
///    [CacheService.downloadAndCache], which streams the response straight
///    to a file under the cache directory (never buffers the whole file in
///    memory — see `CacheService._downloadAndCacheToFile`'s dartdoc).
/// 2. **Play from cache** (`_playFromCache`) — requires NO network.
///    [CacheService.getCachedMediaItem] returns a [MediaItem] whose `url`
///    has been swapped for a `file://` URI built via
///    [LocalMediaUtils.fileUri] (the same helper the Local File Playback
///    page uses), which is then handed to the ordinary
///    [MediaController.load] — no special-cased "play from cache" API on
///    the player side, no manual [MediaItem] reassembly on the caller
///    side.
///
/// To verify step 2 truly needs no network: run step 1 once, then enable
/// airplane mode and tap "Play from cache" again (or relaunch the app —
/// the cache persists to disk).
///
/// Only progressive (single-file) sources can be cached this way — HLS/DASH
/// manifests are out of scope (see [CacheService]'s dartdoc / PLAN.md C-03).
class CachePlaybackPage extends StatefulWidget {
  const CachePlaybackPage({super.key});

  @override
  State<CachePlaybackPage> createState() => _CachePlaybackPageState();
}

class _CachePlaybackPageState extends State<CachePlaybackPage> {
  static const _item = SampleMedia.forBiggerEscapes;

  late final MediaController _controller;
  late final CacheService _cache;

  bool _isBusy = false;
  String? _error;
  String? _status;
  double? _downloadProgress;
  String? _playedFromUrl;

  @override
  void initState() {
    super.initState();
    _controller = MediaController.create(
      playerId: 'cache_playback',
      config: const MediaConfig(respectSafeArea: true, autoPlay: false),
    );
    _cache = CacheService(const CacheConfig(
      maxCacheSize: 200 * 1024 * 1024,
      cacheExpiration: Duration(days: 7),
      enabled: true,
    ));
    _cache.downloadProgressStream.listen((progress) {
      if (!mounted) return;
      if (progress.mediaId != _item.id) return;
      setState(() => _downloadProgress = progress.progress);
    });
    _init();
  }

  Future<void> _init() async {
    await _controller.initialize();
    await _cache.initialize();
    final cached = await _cache.isCached(_item.id);
    if (mounted) {
      setState(() {
        _status = cached
            ? 'Already cached on disk -- tap "Play from cache" (works with '
                'no network).'
            : 'Not cached yet -- tap "Download & cache" first (requires '
                'network).';
      });
    }
  }

  Future<void> _downloadToCache() async {
    setState(() {
      _isBusy = true;
      _error = null;
      _downloadProgress = 0;
      _status = 'Downloading...';
    });
    try {
      await _cache.downloadAndCache(_item);
      if (mounted) {
        setState(() {
          _status = 'Downloaded and cached. Now try "Play from cache" -- '
              'switch to airplane mode first to prove it needs no network.';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
          _downloadProgress = null;
        });
      }
    }
  }

  Future<void> _playFromCache() async {
    setState(() {
      _isBusy = true;
      _error = null;
      _status = 'Loading from cache...';
    });
    try {
      // No network used from here on: getCachedMediaItem only touches the
      // on-disk cache file and local metadata, and MediaController.load()
      // with a file:// MediaItem.url never opens a socket.
      final cachedItem = await _cache.getCachedMediaItem(_item.id);
      if (cachedItem == null) {
        setState(() {
          _status = 'Not cached (or the cached copy expired) -- download '
              'it first.';
        });
        return;
      }

      await _controller.load(cachedItem);
      if (mounted) {
        setState(() {
          _playedFromUrl = cachedItem.url;
          _status = 'Playing from disk -- no network required.';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _clearCache() async {
    setState(() => _isBusy = true);
    try {
      await _cache.clearCache();
      if (mounted) {
        setState(() {
          _playedFromUrl = null;
          _status = 'Cache cleared.';
        });
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _cache.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PlayerScaffold(
      title: 'Cache -> Playback',
      controller: _controller,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Now Playing'),
        _NowPlayingCard(
          controller: _controller,
          url: _playedFromUrl,
          status: _status,
        ),
        if (_downloadProgress != null) ...[
          const SizedBox(height: 8),
          LinearProgressIndicator(value: _downloadProgress),
        ],
        if (_error != null) ...[
          const SizedBox(height: 8),
          _ErrorCard(message: _error!),
        ],
        const SectionHeader('Actions'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              icon: const Icon(Icons.download),
              label: const Text('Download & cache'),
              onPressed: _isBusy ? null : _downloadToCache,
            ),
            FilledButton.icon(
              icon: const Icon(Icons.play_circle_outline),
              label: const Text('Play from cache'),
              onPressed: _isBusy ? null : _playFromCache,
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.delete_outline),
              label: const Text('Clear cache'),
              onPressed: _isBusy ? null : _clearCache,
            ),
          ],
        ),
        const SizedBox(height: 16),
        const _ApiNote(),
      ],
    );
  }
}

class _NowPlayingCard extends StatelessWidget {
  final MediaController controller;
  final String? url;
  final String? status;
  const _NowPlayingCard({
    required this.controller,
    required this.url,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final state = controller.state;
        return Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (status != null) ...[
                  Text(status!, style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 8),
                ],
                InfoRow(label: 'State', value: state.state.name),
                InfoRow(
                  label: 'Position',
                  value:
                      '${controller.formattedPosition} / ${controller.formattedDuration}',
                ),
                InfoRow(label: 'Cached file:// URL', value: url ?? '-'),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  const _ErrorCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          message,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onErrorContainer,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class _ApiNote extends StatelessWidget {
  const _ApiNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .secondaryContainer
            .withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'API Used',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            'CacheService.downloadAndCache(item) streams the file to disk '
            '(network required). CacheService.getCachedMediaItem(item.id) '
            'later returns a MediaItem with url swapped for a file:// URI '
            '(LocalMediaUtils.fileUri) -- no network involved -- which goes '
            'through the normal MediaController.load() path like any other '
            'item. Only progressive (single-file) media can be cached this '
            'way; HLS/DASH manifests are not supported. A DRM-protected '
            'item\'s cached copy is still rejected by validation, since DRM '
            'requires an HTTPS media URL and offline DRM is not supported.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
