import 'package:flutter/material.dart';

import '../../widgets/feature_card.dart';
import '../../widgets/measurement_log_panel.dart';
import 'decoder_ceiling_page.dart';
import 'live_offscreen_bandwidth_page.dart';
import 'memory_paused_playing_page.dart';
import 'scroll_bandwidth_page.dart';
import 'time_to_first_frame_page.dart';

/// Entry point for the Stage 7a measurement harness (Phase 7, production
/// feed architecture).
///
/// This is a **throwaway measurement harness**, not production API — its
/// entire purpose is to produce the numbers Stage 7b's `MediaFeed`/pool
/// design cites instead of guessing. Nothing here is exported from
/// `lib/zmedia_player.dart`; it lives only in the example app.
///
/// Every page below emits `[7A-MEASURE] start:<phase> ...` /
/// `[7A-MEASURE] end:<phase> ...` markers (see
/// `measurement_log_panel.dart`) so console output (`adb logcat`, Xcode
/// console) can be correlated against an external reading
/// (`adb shell dumpsys media.resource_manager | grep -c 'Name: OMX'` — NOT
/// `dumpsys media.codec`, which returns nothing on some devices, e.g.
/// MediaTek — `adb shell dumpsys meminfo`, Android Studio's Network
/// Profiler, Xcode Instruments) taken at the same moment.
/// The on-screen log mirrors the same lines and is copyable, since the
/// operator is reading a phone, not attached to a debugger.
class MeasurementHubPage extends StatelessWidget {
  const MeasurementHubPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Stage 7a Measurement Harness')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const MeasurementIntroCard(
              text: 'Five measurements that Stage 7b\'s pool/prewarm/'
                  'prefetch defaults are designed against. Some are read '
                  'entirely in-app (time-to-first-frame); others need '
                  'external tooling running alongside this app (decoder '
                  'ceiling, memory, bandwidth) — each page below states '
                  'exactly which and gives the operator command(s). Run '
                  'these one at a time, not concurrently: several spawn '
                  'many native player instances and would otherwise '
                  'confound each other\'s readings.',
            ),
            const SizedBox(height: 16),
            _measurement(
              context,
              number: 1,
              title: 'Hardware decoder ceiling',
              description: 'Spawn players one at a time until failure. Watch '
                  '`adb shell dumpsys media.resource_manager` externally.',
              icon: Icons.memory,
              page: const DecoderCeilingPage(),
            ),
            const SizedBox(height: 8),
            _measurement(
              context,
              number: 2,
              title: 'Memory: prepared-but-paused vs playing',
              description: 'Spawn N players in either condition; read '
                  'memory externally for each. Decides whether pooling is '
                  'mandatory (F-01).',
              icon: Icons.pause_circle_outline,
              page: const MemoryPausedPlayingPage(),
            ),
            const SizedBox(height: 8),
            _measurement(
              context,
              number: 3,
              title: 'Time-to-first-frame (prewarm vs cold)',
              description: 'Measured entirely in-app. MP4, HLS and DASH; '
                  'cold load-and-play vs prewarmed load-then-play.',
              icon: Icons.timer_outlined,
              page: const TimeToFirstFramePage(),
            ),
            const SizedBox(height: 8),
            _measurement(
              context,
              number: 4,
              title: 'Bandwidth across a 50-item fast scroll',
              description: 'A 50-item MediaListPlayer feed to fling through. '
                  'Bandwidth read externally (Network Profiler / '
                  'Instruments).',
              icon: Icons.view_agenda_outlined,
              page: const ScrollBandwidthPage(),
            ),
            const SizedBox(height: 8),
            _measurement(
              context,
              number: 5,
              title: 'Off-screen paused live stream bandwidth',
              description: 'Play a live HLS stream, scroll it off-screen so '
                  'it pauses, hold. Bandwidth read externally (F-04).',
              icon: Icons.live_tv,
              page: const LiveOffscreenBandwidthPage(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _measurement(
    BuildContext context, {
    required int number,
    required String title,
    required String description,
    required IconData icon,
    required Widget page,
  }) {
    return FeatureCard(
      title: '$number. $title',
      description: description,
      icon: icon,
      iconColor: Colors.brown,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => page),
      ),
    );
  }
}
