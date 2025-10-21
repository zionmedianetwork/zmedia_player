import 'package:flutter/material.dart';
import 'package:zmedia_player/zmedia_player.dart';

/// Demonstrates comprehensive exception handling with ZMedia Player
class ExceptionHandlingDemoPage extends StatefulWidget {
  const ExceptionHandlingDemoPage({super.key});

  @override
  State<ExceptionHandlingDemoPage> createState() =>
      _ExceptionHandlingDemoPageState();
}

class _ExceptionHandlingDemoPageState extends State<ExceptionHandlingDemoPage> {
  late MediaController _controller;
  final List<String> _errorLog = [];

  @override
  void initState() {
    super.initState();
    _controller = MediaController(MediaPlayer());
    _setupErrorHandling();
  }

  void _setupErrorHandling() {
    // Listen to player state for errors
    _controller.player.stateStream.listen((state) {
      if (state.state == PlayerState.error) {
        _logError('Playback error: ${state.errorMessage}');
      }
    });
  }

  void _logError(String message) {
    setState(() {
      _errorLog.insert(
          0, '[${DateTime.now().toString().substring(11, 19)}] $message');
      if (_errorLog.length > 20) {
        _errorLog.removeLast();
      }
    });
  }

  void _showErrorDialog(String title, String message,
      {String? recommendation}) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            if (recommendation != null) ...[
              const SizedBox(height: 16),
              Text(
                'Recommendation:',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(recommendation),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleMediaOperation(
    Future<void> Function() operation,
    String operationName,
  ) async {
    try {
      await operation();
      _logError('✓ $operationName succeeded');
    } on DrmException catch (e) {
      _logError('DRM Error: ${e.message}');
      String recommendation;
      if (e.isLicenseError) {
        recommendation =
            'Check your subscription status and license server configuration.';
      } else if (e.isCertificateError) {
        recommendation =
            'Verify DRM certificates are properly installed. Update the app if needed.';
      } else {
        recommendation = 'Contact support if the problem persists.';
      }
      _showErrorDialog('DRM Error', e.message, recommendation: recommendation);
    } on NetworkException catch (e) {
      _logError('Network Error: ${e.message}');
      String recommendation;
      if (e.isOffline) {
        recommendation = 'Check your internet connection and try again.';
      } else if (e.isTimeout) {
        recommendation =
            'The connection timed out. Try again or check your network speed.';
      } else {
        recommendation = 'Network connection failed. Please try again.';
      }
      _showErrorDialog('Network Error', e.message,
          recommendation: recommendation);
    } on MediaLoadException catch (e) {
      _logError('Load Error: ${e.message}');
      String recommendation = 'Check the media URL and format. ';
      if (e.statusCode != null) {
        if (e.statusCode == 404) {
          recommendation += 'The video was not found (404).';
        } else if (e.statusCode! >= 500) {
          recommendation += 'Server error (${e.statusCode}). Try again later.';
        } else {
          recommendation += 'HTTP error ${e.statusCode}.';
        }
      } else {
        recommendation += 'Verify the media is accessible.';
      }
      _showErrorDialog('Load Failed', e.message,
          recommendation: recommendation);
    } on PlaybackException catch (e) {
      _logError('Playback Error: ${e.message}');
      _showErrorDialog(
        'Playback Error',
        e.message,
        recommendation:
            'The video format may not be supported or the file is corrupted.',
      );
    } on InvalidStateException catch (e) {
      _logError('Invalid State: ${e.message}');
      _showErrorDialog(
        'Invalid Operation',
        '${e.message}\n\nCurrent: ${e.currentState}\nRequired: ${e.requiredState}',
        recommendation:
            'Make sure the player is in the correct state before this operation.',
      );
    } on ConfigurationException catch (e) {
      _logError('Config Error: ${e.message}');
      _showErrorDialog(
        'Configuration Error',
        '${e.message}\n\nParameter: ${e.parameter}\nValue: ${e.value}',
        recommendation: 'Check the parameter value and try again.',
      );
    } on PlayerDisposedException catch (e) {
      _logError('Player Disposed: ${e.message}');
      _showErrorDialog(
        'Player Disposed',
        e.message,
        recommendation:
            'The player was already disposed. Create a new player instance.',
      );
    } on PlatformOperationException catch (e) {
      _logError('Platform Error: ${e.message}');
      _showErrorDialog(
        'Platform Error',
        '${e.message} (${e.platform})',
        recommendation:
            'This is a platform-specific error. Check device compatibility.',
      );
    } on MediaPlayerException catch (e) {
      // Catch-all for any other MediaPlayerException
      _logError('Media Player Error: ${e.message}');
      _showErrorDialog(
        'Playback Error',
        e.message,
        recommendation: 'An unexpected error occurred. Please try again.',
      );
    } catch (e) {
      // Catch any other unexpected errors
      _logError('Unexpected Error: $e');
      _showErrorDialog(
        'Unexpected Error',
        '$e',
        recommendation:
            'An unexpected error occurred. Please report this issue.',
      );
    }
  }

  void _testNetworkError() {
    _handleMediaOperation(
      () => _controller.load(MediaItem(
        id: 'network-error',
        url: 'https://invalid-domain-that-does-not-exist.com/video.mp4',
        title: 'Network Error Test',
      )),
      'Load video (network error)',
    );
  }

  void _testInvalidUrl() {
    _handleMediaOperation(
      () => _controller.load(MediaItem(
        id: 'invalid-url',
        url: 'https://example.com/nonexistent-video.mp4',
        title: 'Invalid URL Test',
      )),
      'Load video (404)',
    );
  }

  void _testDrmError() {
    _handleMediaOperation(
      () => _controller.load(MediaItem(
        id: 'drm-error',
        url: 'https://example.com/drm-video.mp4',
        title: 'DRM Error Test',
        drmConfig: DrmConfig.widevine(
          licenseUrl: 'https://invalid-license-server.com/license',
        ),
      )),
      'Load DRM video (license error)',
    );
  }

  void _testInvalidState() {
    _handleMediaOperation(
      () => _controller.skipToNext(),
      'Skip to next (no playlist)',
    );
  }

  void _testConfigError() {
    _handleMediaOperation(
      () => _controller.seekTo(const Duration(milliseconds: -1000)),
      'Seek to negative position',
    );
  }

  void _testDisposedPlayer() async {
    final tempPlayer = MediaPlayer();
    await tempPlayer.initialize();
    await tempPlayer.dispose();

    try {
      // This should throw PlayerDisposedException
      tempPlayer.config;
      _logError('ERROR: Should have thrown PlayerDisposedException');
    } on PlayerDisposedException catch (e) {
      _logError('✓ PlayerDisposedException caught correctly');
      _showErrorDialog(
        'Player Disposed',
        e.message,
        recommendation: 'The player was already disposed.',
      );
    }
  }

  void _clearLog() {
    setState(() {
      _errorLog.clear();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Exception Handling Demo'),
        actions: [
          IconButton(
            icon: const Icon(Icons.clear_all),
            onPressed: _clearLog,
            tooltip: 'Clear Error Log',
          ),
        ],
      ),
      body: Column(
        children: [
          // Player widget
          Container(
            height: 200,
            color: Colors.black,
            child: Center(
              child: MediaPlayerWidget(controller: _controller),
            ),
          ),

          // Test buttons
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Test Exception Types',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _testNetworkError,
                      icon: const Icon(Icons.signal_wifi_off),
                      label: const Text('Network Error'),
                    ),
                    ElevatedButton.icon(
                      onPressed: _testInvalidUrl,
                      icon: const Icon(Icons.error_outline),
                      label: const Text('404 Error'),
                    ),
                    ElevatedButton.icon(
                      onPressed: _testDrmError,
                      icon: const Icon(Icons.lock_outline),
                      label: const Text('DRM Error'),
                    ),
                    ElevatedButton.icon(
                      onPressed: _testInvalidState,
                      icon: const Icon(Icons.warning_amber),
                      label: const Text('Invalid State'),
                    ),
                    ElevatedButton.icon(
                      onPressed: _testConfigError,
                      icon: const Icon(Icons.settings),
                      label: const Text('Config Error'),
                    ),
                    ElevatedButton.icon(
                      onPressed: _testDisposedPlayer,
                      icon: const Icon(Icons.delete_forever),
                      label: const Text('Disposed Player'),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Error log
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.description,
                          size: 20, color: Colors.grey[600]),
                      const SizedBox(width: 8),
                      Text(
                        'Error Log',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                      ),
                      const Spacer(),
                      Text(
                        '${_errorLog.length} entries',
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                    ],
                  ),
                  const Divider(),
                  Expanded(
                    child: _errorLog.isEmpty
                        ? Center(
                            child: Text(
                              'No errors yet. Try the test buttons above.',
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                          )
                        : ListView.builder(
                            itemCount: _errorLog.length,
                            itemBuilder: (context, index) {
                              final entry = _errorLog[index];
                              final isSuccess = entry.contains('✓');
                              return Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 2),
                                child: Text(
                                  entry,
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                    color: isSuccess
                                        ? Colors.green[700]
                                        : Colors.red[700],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),

          // Information panel
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.blue[50],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue[700]),
                    const SizedBox(width: 8),
                    Text(
                      'Exception Handling Best Practices',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue[900],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '• Catch specific exception types first (DrmException, NetworkException, etc.)\n'
                  '• Use MediaPlayerException as catch-all for player errors\n'
                  '• Provide user-friendly error messages and recovery options\n'
                  '• Log errors with context for debugging',
                  style: TextStyle(fontSize: 12, color: Colors.blue[900]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
