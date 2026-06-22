/// Represents a subtitle track for media content
class SubtitleTrack {
  /// Unique identifier for the subtitle track
  final String id;

  /// Display name of the subtitle track
  final String title;

  /// Language code (e.g., 'en', 'es', 'fr')
  final String? language;

  /// URL or file path to the subtitle file
  final String? url;

  /// Subtitle format
  final SubtitleFormat format;

  /// Whether this track is currently selected
  final bool isSelected;

  /// Whether this is the default subtitle track
  final bool isDefault;

  /// Additional metadata
  final Map<String, dynamic>? metadata;

  const SubtitleTrack({
    required this.id,
    required this.title,
    this.language,
    this.url,
    this.format = SubtitleFormat.srt,
    this.isSelected = false,
    this.isDefault = false,
    this.metadata,
  });

  /// Creates a copy of this subtitle track with updated values
  SubtitleTrack copyWith({
    String? id,
    String? title,
    String? language,
    String? url,
    SubtitleFormat? format,
    bool? isSelected,
    bool? isDefault,
    Map<String, dynamic>? metadata,
  }) {
    return SubtitleTrack(
      id: id ?? this.id,
      title: title ?? this.title,
      language: language ?? this.language,
      url: url ?? this.url,
      format: format ?? this.format,
      isSelected: isSelected ?? this.isSelected,
      isDefault: isDefault ?? this.isDefault,
      metadata: metadata ?? this.metadata,
    );
  }

  /// Converts the subtitle track to a map for serialization
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'language': language,
      'url': url,
      'format': format.name,
      'isSelected': isSelected,
      'isDefault': isDefault,
      'metadata': metadata,
    };
  }

  /// Creates a subtitle track from a map
  factory SubtitleTrack.fromMap(Map<String, dynamic> map) {
    return SubtitleTrack(
      id: map['id'] as String,
      title: map['title'] as String,
      language: map['language'] as String?,
      url: map['url'] as String?,
      format: SubtitleFormat.values.firstWhere(
        (format) => format.name == map['format'],
        orElse: () => SubtitleFormat.srt,
      ),
      isSelected: map['isSelected'] as bool? ?? false,
      isDefault: map['isDefault'] as bool? ?? false,
      metadata: map['metadata'] as Map<String, dynamic>?,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SubtitleTrack && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'SubtitleTrack(id: $id, title: $title, language: $language, format: $format)';
  }
}

/// Supported subtitle formats
enum SubtitleFormat {
  /// SubRip Subtitle format (.srt)
  srt,

  /// WebVTT format (.vtt)
  webvtt,

  /// Advanced SubStation Alpha format (.ass)
  ass,

  /// SubStation Alpha format (.ssa)
  ssa,

  /// Timed Text Markup Language (.ttml)
  ttml,
}

/// Configuration for subtitle display
class SubtitleConfig {
  /// Font size for subtitles
  final double fontSize;

  /// Font color for subtitles
  final int fontColor;

  /// Background color for subtitles
  final int? backgroundColor;

  /// Font family for subtitles
  final String? fontFamily;

  /// Whether to show outline around text
  final bool showOutline;

  /// Outline color
  final int? outlineColor;

  /// Subtitle position (0.0 = top, 1.0 = bottom)
  final double verticalPosition;

  /// Horizontal alignment
  final SubtitleAlignment horizontalAlignment;

  const SubtitleConfig({
    this.fontSize = 16.0,
    this.fontColor = 0xFFFFFFFF, // White
    this.backgroundColor,
    this.fontFamily,
    this.showOutline = true,
    this.outlineColor = 0xFF000000, // Black
    this.verticalPosition = 0.9,
    this.horizontalAlignment = SubtitleAlignment.center,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SubtitleConfig &&
        other.fontSize == fontSize &&
        other.fontColor == fontColor &&
        other.backgroundColor == backgroundColor &&
        other.fontFamily == fontFamily &&
        other.showOutline == showOutline &&
        other.outlineColor == outlineColor &&
        other.verticalPosition == verticalPosition &&
        other.horizontalAlignment == horizontalAlignment;
  }

  @override
  int get hashCode => Object.hash(
        fontSize,
        fontColor,
        backgroundColor,
        fontFamily,
        showOutline,
        outlineColor,
        verticalPosition,
        horizontalAlignment,
      );

  /// Creates a copy of this subtitle config with updated values
  SubtitleConfig copyWith({
    double? fontSize,
    int? fontColor,
    int? backgroundColor,
    String? fontFamily,
    bool? showOutline,
    int? outlineColor,
    double? verticalPosition,
    SubtitleAlignment? horizontalAlignment,
  }) {
    return SubtitleConfig(
      fontSize: fontSize ?? this.fontSize,
      fontColor: fontColor ?? this.fontColor,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      fontFamily: fontFamily ?? this.fontFamily,
      showOutline: showOutline ?? this.showOutline,
      outlineColor: outlineColor ?? this.outlineColor,
      verticalPosition: verticalPosition ?? this.verticalPosition,
      horizontalAlignment: horizontalAlignment ?? this.horizontalAlignment,
    );
  }
}

/// Subtitle text alignment
enum SubtitleAlignment {
  /// Left aligned
  left,

  /// Center aligned
  center,

  /// Right aligned
  right,
}
