/// ZMedia Player Package
///
/// A comprehensive media player package for Flutter applications with
/// advanced features including DRM support, streaming protocols, and
/// cross-platform compatibility.
library zmedia_player;

// Core
export 'src/core/media_player.dart';
export 'src/core/media_controller.dart';
export 'src/core/media_config.dart';
export 'src/core/crash_reporter.dart';
export 'src/core/exceptions.dart';

// Models
export 'src/models/media_item.dart';
export 'src/models/player_state.dart';
export 'src/models/playlist.dart';
export 'src/models/subtitle_track.dart';
export 'src/models/drm_config.dart';
export 'src/models/streaming_config.dart';

// Phase 1 Models (Buffering & Network)
export 'src/models/buffering_config.dart';
export 'src/models/buffer_health.dart';
export 'src/models/network_status.dart';
export 'src/models/analytics_metrics.dart';

// Phase 3 Models
export 'src/models/notification_config.dart';
export 'src/models/pip_config.dart';
export 'src/models/cast_device.dart';

// Services (Phase 1 - P0)
export 'src/services/buffering_service.dart';
export 'src/services/network_resilience_service.dart';

// Services (Phase 1 - P1)
export 'src/services/analytics_service.dart';

// Services (Phase 2)
export 'src/services/cache_service.dart';
export 'src/services/subtitle_service.dart';
export 'src/services/streaming_service.dart';

// Phase 3 Services
export 'src/services/notification_service.dart';
export 'src/services/cast_service.dart';

// Widgets
export 'src/widgets/media_player_widget.dart';
export 'src/widgets/media_controls.dart';
export 'src/widgets/material_media_controls.dart';
export 'src/widgets/cupertino_media_controls.dart';
export 'src/widgets/adaptive_media_controls.dart';
export 'src/widgets/custom_controls_base.dart';
export 'src/widgets/fullscreen_controls_base.dart';
export 'src/widgets/material_fullscreen_player.dart';
export 'src/widgets/cupertino_fullscreen_player.dart';
export 'src/widgets/subtitle_view.dart';

// Phase 2 Widgets - UI/UX Enhancement
export 'src/widgets/menus/settings_menu.dart';
export 'src/widgets/menus/quality_menu.dart';
export 'src/widgets/menus/audio_track_menu.dart';
export 'src/widgets/menus/subtitle_menu.dart';
export 'src/widgets/menus/subtitle_styling_menu.dart';
export 'src/widgets/menus/speed_menu.dart';
export 'src/widgets/components/quality_badge.dart';
export 'src/widgets/components/time_display.dart';
export 'src/widgets/components/control_button.dart';
export 'src/widgets/components/seek_bar.dart';
export 'src/widgets/components/volume_slider.dart';
export 'src/widgets/components/live_badge.dart';
export 'src/widgets/components/buffer_health_badge.dart';
export 'src/widgets/overlays/buffering_indicator.dart';
export 'src/widgets/overlays/network_quality_indicator.dart';
export 'src/widgets/overlays/error_overlay.dart';
export 'src/widgets/overlays/feedback_overlay.dart';
export 'src/widgets/overlays/volume_change_overlay.dart';
export 'src/widgets/overlays/seek_feedback_overlay.dart';
export 'src/widgets/overlays/playback_feedback_overlay.dart';
export 'src/widgets/overlays/toast_notification.dart';

// Phase 3 Widgets
export 'src/widgets/media_list_player.dart';
export 'src/widgets/airplay_button.dart';

// Phase 7 (Stage 7b): player pool + MediaFeed
export 'src/core/media_player_pool.dart';
export 'src/widgets/media_feed.dart';

// Security (Phase 1 - P1)
export 'src/security/certificate_pinning.dart';
export 'src/security/secure_storage.dart';
export 'src/security/input_validation.dart';

// Security (Phase 5 wave 2 - B-12: screen-capture protection)
export 'src/security/screen_capture_protection.dart';
