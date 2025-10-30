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
export 'src/widgets/subtitle_view.dart';

// Phase 3 Widgets
export 'src/widgets/media_list_player.dart';

// Security (Phase 1 - P1)
export 'src/security/certificate_pinning.dart';
export 'src/security/secure_storage.dart';
export 'src/security/input_validation.dart';
