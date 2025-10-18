/// Flutter Media Player Package
///
/// A comprehensive media player package for Flutter applications with
/// advanced features including DRM support, streaming protocols, and
/// cross-platform compatibility.
library flutter_media_player;

// Core
export 'src/core/media_player.dart';
export 'src/core/media_controller.dart';
export 'src/core/media_config.dart';

// Models
export 'src/models/media_item.dart';
export 'src/models/player_state.dart';
export 'src/models/playlist.dart';
export 'src/models/subtitle_track.dart';
export 'src/models/drm_config.dart';
export 'src/models/streaming_config.dart';

// Services (Phase 2)
export 'src/services/cache_service.dart';
export 'src/services/subtitle_service.dart';
export 'src/services/streaming_service.dart';

// Widgets
export 'src/widgets/media_player_widget.dart';
export 'src/widgets/media_controls.dart';
export 'src/widgets/subtitle_view.dart';
