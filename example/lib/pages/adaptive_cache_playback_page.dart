import 'package:flutter/material.dart';
import 'package:zmedia_player/zmedia_player.dart';
import '../data/sample_media.dart';
import '../widgets/player_scaffold.dart';

/// Demonstrates C-03b — transparent Media3 segment caching for adaptive
/// (HLS/DASH) streams. **Android-only**; see [AdaptiveCacheConfig]'s
/// dartdoc for why iOS has no equivalent yet.
///
/// Unlike the progressive [CacheService] flow on the "Cache -> Playback
/// (C-03a)" page, there is no separate "download" step and no Dart-visible
/// cache API here: enabling [AdaptiveCacheConfig] just makes the *normal*
/// [MediaController.load] / playback path transparently cache HLS/DASH
/// segments, init segments and manifests to disk as they're fetched during
/// ordinary playback (native `CacheDataSource` wrapping a shared, process-
/// wide `SimpleCache` — see `AdaptiveCacheHolder.kt`). Whatever was actually
/// played gets cached; there is no prefetch-ahead.
///
/// On-device verification steps:
///  1. With network on, tap "Load & play" and let the stream play for at
///     least 20-30 seconds (long enough to cache several segments across
///     however many ABR renditions get selected).
///  2. Enable Airplane Mode.
///  3. Tap "Replay from position 0". Playback should resume from disk for
///     whatever was already cached in step 1 with no network at all; once
///     playback reaches content beyond what was previously played, it will
///     stall (nothing to serve it from cache with the network down) --
///     that's expected, not a bug: this is a read-through cache of what
///     was played, not a download-ahead cache of the whole stream.
///  4. Disable Airplane Mode, restart the app, repeat step 3 immediately
///     (no re-play in between) to confirm the cache persisted to disk
///     across a process restart -- the whole point of `SimpleCache`
///     writing through a `StandaloneDatabaseProvider`-backed index rather
///     than an in-memory structure.
class AdaptiveCachePlaybackPage extends StatefulWidget {
  const AdaptiveCachePlaybackPage({super.key});

  @override
  State<AdaptiveCachePlaybackPage> createState() =>
      _AdaptiveCachePlaybackPageState();
}

class _AdaptiveCachePlaybackPageState
    extends State<AdaptiveCachePlaybackPage> {
  static const _item = SampleMedia.hlsStream;

  late final MediaController _controller;
  bool _isBusy = false;
  String? _error;
  String? _status;

  @override
  void initState() {
    super.initState();
    _controller = MediaController.create(
      playerId: 'adaptive_cache_playback',
      config: const MediaConfig(
        respectSafeArea: true,
        autoPlay: false,
        // C-03b opt-in: off by default on every other page in this app.
        // Android-only -- see AdaptiveCacheConfig's dartdoc. Has no effect
        // on iOS (the key is simply never read there).
        adaptiveCacheConfig: AdaptiveCacheConfig(
          enabled: true,
          maxCacheSizeBytes: 100 * 1024 * 1024, // 100MB for this demo
        ),
      ),
    );
    _init();
  }

  Future<void> _init() async {
    await _controller.initialize();
    if (mounted) {
      setState(() {
        _status = 'Not loaded yet -- tap "Load & play" (requires network). '
            'Segments cache to disk transparently as they play.';
      });
    }
  }

  Future<void> _loadAndPlay() async {
    setState(() {
      _isBusy = true;
      _error = null;
      _status = 'Loading...';
    });
    try {
      await _controller.load(_item);
      await _controller.play();
      if (mounted) {
        setState(() {
          _status = 'Playing -- let it run ~20-30s, then enable Airplane '
              'Mode and tap "Replay from position 0".';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _replayFromStart() async {
    setState(() {
      _isBusy = true;
      _error = null;
      _status = 'Reloading from position 0 -- watch for playback to '
          'succeed with no network for however much was previously cached.';
    });
    try {
      // Deliberately the exact same MediaItem/URL and the exact same
      // MediaController (same adaptiveCacheConfig-enabled config) -- the
      // native CacheDataSource decides transparently, per byte range,
      // whether to read from the shared disk cache or the network.
      await _controller.load(_item);
      await _controller.play();
      if (mounted) {
        setState(() {
          _status = 'Replaying. If Airplane Mode is on and this is still '
              'playing, you are watching previously-cached segments come '
              'from disk.';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PlayerScaffold(
      title: 'Adaptive Segment Cache (C-03b)',
      controller: _controller,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Now Playing'),
        _StatusCard(controller: _controller, status: _status),
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
              icon: const Icon(Icons.play_circle_outline),
              label: const Text('Load & play'),
              onPressed: _isBusy ? null : _loadAndPlay,
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.replay),
              label: const Text('Replay from position 0'),
              onPressed: _isBusy ? null : _replayFromStart,
            ),
          ],
        ),
        const SizedBox(height: 16),
        const _ApiNote(),
      ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  final MediaController controller;
  final String? status;
  const _StatusCard({required this.controller, required this.status});

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
            'API Used -- Android only',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            'MediaConfig(adaptiveCacheConfig: AdaptiveCacheConfig(enabled: '
            'true)) opts an HLS/DASH player into transparent, read-through '
            'segment caching -- no separate download step, no Dart-visible '
            'cache object. Natively this wraps ExoPlayer/Media3\'s '
            'DataSource.Factory in a CacheDataSource backed by a single, '
            'process-wide SimpleCache (AdaptiveCacheHolder.kt) bounded by an '
            'LRU evictor. DRM-configured items are never wrapped in this '
            'cache, regardless of this setting. This has NO effect on iOS -- '
            'AVFoundation has no equivalent transparent cache; offline HLS '
            'there needs the explicit-download AVAssetDownloadTask API, '
            'which is separate, not-yet-implemented work.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
