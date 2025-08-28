import 'media_item.dart';

/// Represents a playlist of media items
class Playlist {
  /// Unique identifier for the playlist
  final String id;

  /// Display name of the playlist
  final String title;

  /// List of media items in the playlist
  final List<MediaItem> items;

  /// Current playing index
  final int currentIndex;

  /// Playback mode for the playlist
  final PlaybackMode mode;

  /// Whether the playlist should repeat
  final RepeatMode repeatMode;

  /// Additional metadata
  final Map<String, dynamic>? metadata;

  const Playlist({
    required this.id,
    required this.title,
    required this.items,
    this.currentIndex = 0,
    this.mode = PlaybackMode.sequential,
    this.repeatMode = RepeatMode.none,
    this.metadata,
  });

  /// Creates a copy of this playlist with updated values
  Playlist copyWith({
    String? id,
    String? title,
    List<MediaItem>? items,
    int? currentIndex,
    PlaybackMode? mode,
    RepeatMode? repeatMode,
    Map<String, dynamic>? metadata,
  }) {
    return Playlist(
      id: id ?? this.id,
      title: title ?? this.title,
      items: items ?? this.items,
      currentIndex: currentIndex ?? this.currentIndex,
      mode: mode ?? this.mode,
      repeatMode: repeatMode ?? this.repeatMode,
      metadata: metadata ?? this.metadata,
    );
  }

  /// Current media item being played
  MediaItem? get currentItem {
    if (currentIndex >= 0 && currentIndex < items.length) {
      return items[currentIndex];
    }
    return null;
  }

  /// Whether there is a next item available
  bool get hasNext {
    switch (repeatMode) {
      case RepeatMode.all:
        return items.isNotEmpty;
      case RepeatMode.single:
        return true;
      case RepeatMode.none:
        return currentIndex < items.length - 1;
    }
  }

  /// Whether there is a previous item available
  bool get hasPrevious {
    switch (repeatMode) {
      case RepeatMode.all:
        return items.isNotEmpty;
      case RepeatMode.single:
        return true;
      case RepeatMode.none:
        return currentIndex > 0;
    }
  }

  /// Get the next index based on current playback mode
  int? get nextIndex {
    if (items.isEmpty) return null;

    switch (mode) {
      case PlaybackMode.sequential:
        return _getNextSequentialIndex();
      case PlaybackMode.shuffle:
        return _getNextShuffleIndex();
    }
  }

  /// Get the previous index based on current playback mode
  int? get previousIndex {
    if (items.isEmpty) return null;

    switch (mode) {
      case PlaybackMode.sequential:
        return _getPreviousSequentialIndex();
      case PlaybackMode.shuffle:
        return _getPreviousShuffleIndex();
    }
  }

  int? _getNextSequentialIndex() {
    switch (repeatMode) {
      case RepeatMode.single:
        return currentIndex;
      case RepeatMode.all:
        return (currentIndex + 1) % items.length;
      case RepeatMode.none:
        return currentIndex < items.length - 1 ? currentIndex + 1 : null;
    }
  }

  int? _getPreviousSequentialIndex() {
    switch (repeatMode) {
      case RepeatMode.single:
        return currentIndex;
      case RepeatMode.all:
        return currentIndex > 0 ? currentIndex - 1 : items.length - 1;
      case RepeatMode.none:
        return currentIndex > 0 ? currentIndex - 1 : null;
    }
  }

  int? _getNextShuffleIndex() {
    // For simplicity, return a random index for shuffle mode
    // In a real implementation, you'd maintain a shuffle queue
    if (items.isEmpty) return null;
    switch (repeatMode) {
      case RepeatMode.single:
        return currentIndex;
      case RepeatMode.all:
      case RepeatMode.none:
        // This is a simplified implementation
        // A proper shuffle would maintain a queue of shuffled indices
        return (currentIndex + 1) % items.length;
    }
  }

  int? _getPreviousShuffleIndex() {
    // For simplicity, return previous index for shuffle mode
    // In a real implementation, you'd maintain a shuffle history
    if (items.isEmpty) return null;
    switch (repeatMode) {
      case RepeatMode.single:
        return currentIndex;
      case RepeatMode.all:
      case RepeatMode.none:
        return currentIndex > 0 ? currentIndex - 1 : items.length - 1;
    }
  }

  /// Add an item to the playlist
  Playlist addItem(MediaItem item) {
    return copyWith(items: [...items, item]);
  }

  /// Insert an item at a specific index
  Playlist insertItem(int index, MediaItem item) {
    final newItems = List<MediaItem>.from(items);
    newItems.insert(index.clamp(0, items.length), item);
    return copyWith(items: newItems);
  }

  /// Remove an item at a specific index
  Playlist removeItemAt(int index) {
    if (index < 0 || index >= items.length) return this;

    final newItems = List<MediaItem>.from(items);
    newItems.removeAt(index);

    int newCurrentIndex = currentIndex;
    if (index < currentIndex) {
      newCurrentIndex = currentIndex - 1;
    } else if (index == currentIndex && currentIndex >= newItems.length) {
      newCurrentIndex = newItems.isEmpty ? 0 : newItems.length - 1;
    }

    return copyWith(
      items: newItems,
      currentIndex: newCurrentIndex,
    );
  }

  /// Move to a specific index
  Playlist moveToIndex(int index) {
    if (index < 0 || index >= items.length) return this;
    return copyWith(currentIndex: index);
  }

  /// Total duration of all items in the playlist
  Duration get totalDuration {
    return items.fold(Duration.zero, (total, item) {
      return total + (item.duration ?? Duration.zero);
    });
  }

  /// Whether the playlist is empty
  bool get isEmpty => items.isEmpty;

  /// Number of items in the playlist
  int get length => items.length;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Playlist && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'Playlist(id: $id, title: $title, items: ${items.length}, currentIndex: $currentIndex)';
  }
}

/// Playback mode for playlists
enum PlaybackMode {
  /// Play items in sequential order
  sequential,

  /// Play items in random order
  shuffle,
}

/// Repeat mode for playlists
enum RepeatMode {
  /// No repeat
  none,

  /// Repeat current item
  single,

  /// Repeat entire playlist
  all,
}
