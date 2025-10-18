import 'package:flutter/material.dart';
import 'package:flutter_media_player/flutter_media_player.dart';
import '../data/sample_videos.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late MediaController _controller;
  bool _isInitializing = true;

  // Configuration settings
  bool _autoPlay = false;
  bool _looping = false;
  double _volume = 0.8;
  double _speed = 1.0;
  bool _startMuted = false;
  BoxFit _boxFit = BoxFit.contain;
  bool _showControls = true;
  bool _useHardwareAcceleration = true;
  Map<String, String> _httpHeaders = {};

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    setState(() {
      _isInitializing = true;
    });

    _controller = MediaController.create(
      config: _getCurrentConfig(),
    );

    await _controller.initialize();
    await _controller.load(SampleVideos.defaultVideo);

    setState(() {
      _isInitializing = false;
    });
  }

  MediaConfig _getCurrentConfig() {
    return MediaConfig(
      autoPlay: _autoPlay,
      looping: _looping,
      volume: _volume,
      speed: _speed,
      startMuted: _startMuted,
      boxFit: _boxFit,
      showControls: _showControls,
      useHardwareAcceleration: _useHardwareAcceleration,
      httpHeaders: _httpHeaders.isNotEmpty ? _httpHeaders : null,
    );
  }

  Future<void> _applyConfiguration() async {
    await _controller.updateConfig(_getCurrentConfig());

    // Apply individual settings
    await _controller.setVolume(_volume);
    await _controller.setSpeed(_speed);
    await _controller.player.setBoxFit(_boxFit);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Configuration applied successfully'),
          backgroundColor: Color(0xFF10B981),
          duration: Duration(seconds: 2),
        ),
      );
    }
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
        title: const Text('Settings & Configuration'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: _applyConfiguration,
            tooltip: 'Apply Settings',
          ),
        ],
      ),
      body: Column(
        children: [
          // Video Preview
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Container(
              color: Colors.black,
              child: _isInitializing
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF6366F1),
                      ),
                    )
                  : MediaPlayerWidget(
                      controller: _controller,
                      showControls: _showControls,
                    ),
            ),
          ),

          // Settings List
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Playback Settings Section
                _SectionHeader(
                  icon: Icons.play_circle,
                  title: 'Playback Settings',
                ),
                const SizedBox(height: 8),

                _SettingCard(
                  children: [
                    _SwitchSetting(
                      title: 'Auto Play',
                      subtitle: 'Start playback automatically when media loads',
                      value: _autoPlay,
                      onChanged: (value) {
                        setState(() {
                          _autoPlay = value;
                        });
                      },
                    ),
                    const Divider(height: 1),
                    _SwitchSetting(
                      title: 'Looping',
                      subtitle: 'Repeat video when it reaches the end',
                      value: _looping,
                      onChanged: (value) {
                        setState(() {
                          _looping = value;
                        });
                      },
                    ),
                    const Divider(height: 1),
                    _SwitchSetting(
                      title: 'Start Muted',
                      subtitle: 'Begin playback with audio muted',
                      value: _startMuted,
                      onChanged: (value) {
                        setState(() {
                          _startMuted = value;
                        });
                      },
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Volume & Speed Section
                _SectionHeader(
                  icon: Icons.tune,
                  title: 'Volume & Speed',
                ),
                const SizedBox(height: 8),

                _SettingCard(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.volume_up,
                                  size: 20, color: Colors.white70),
                              const SizedBox(width: 12),
                              const Text(
                                'Volume',
                                style: TextStyle(
                                    color: Colors.white, fontSize: 14),
                              ),
                              const Spacer(),
                              Text(
                                '${(_volume * 100).toInt()}%',
                                style: const TextStyle(
                                  color: Color(0xFF6366F1),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          Slider(
                            value: _volume,
                            onChanged: (value) {
                              setState(() {
                                _volume = value;
                              });
                              _controller.setVolume(value);
                            },
                            min: 0.0,
                            max: 1.0,
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.speed,
                                  size: 20, color: Colors.white70),
                              const SizedBox(width: 12),
                              const Text(
                                'Playback Speed',
                                style: TextStyle(
                                    color: Colors.white, fontSize: 14),
                              ),
                              const Spacer(),
                              Text(
                                '${_speed}x',
                                style: const TextStyle(
                                  color: Color(0xFF6366F1),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          Slider(
                            value: _speed,
                            onChanged: (value) {
                              setState(() {
                                _speed = value;
                              });
                              _controller.setSpeed(value);
                            },
                            min: 0.25,
                            max: 4.0,
                            divisions: 15,
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [0.25, 0.5, 1.0, 1.5, 2.0, 4.0].map((s) {
                              return TextButton(
                                onPressed: () {
                                  setState(() {
                                    _speed = s;
                                  });
                                  _controller.setSpeed(s);
                                },
                                style: TextButton.styleFrom(
                                  minimumSize: const Size(40, 30),
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 8),
                                ),
                                child: Text(
                                  '${s}x',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: _speed == s
                                        ? const Color(0xFF6366F1)
                                        : Colors.white60,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Display Settings Section
                _SectionHeader(
                  icon: Icons.display_settings,
                  title: 'Display Settings',
                ),
                const SizedBox(height: 8),

                _SettingCard(
                  children: [
                    _DropdownSetting(
                      title: 'Box Fit',
                      subtitle: 'How video fits in the available space',
                      value: _boxFit,
                      items: const [
                        DropdownMenuItem(
                            value: BoxFit.contain, child: Text('Contain')),
                        DropdownMenuItem(
                            value: BoxFit.cover, child: Text('Cover')),
                        DropdownMenuItem(
                            value: BoxFit.fill, child: Text('Fill')),
                        DropdownMenuItem(
                            value: BoxFit.fitWidth, child: Text('Fit Width')),
                        DropdownMenuItem(
                            value: BoxFit.fitHeight, child: Text('Fit Height')),
                        DropdownMenuItem(
                            value: BoxFit.none, child: Text('None')),
                        DropdownMenuItem(
                            value: BoxFit.scaleDown, child: Text('Scale Down')),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            _boxFit = value;
                          });
                          _controller.player.setBoxFit(value);
                        }
                      },
                    ),
                    const Divider(height: 1),
                    _SwitchSetting(
                      title: 'Show Controls',
                      subtitle: 'Display default player controls',
                      value: _showControls,
                      onChanged: (value) {
                        setState(() {
                          _showControls = value;
                        });
                      },
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Performance Settings Section
                _SectionHeader(
                  icon: Icons.settings_suggest,
                  title: 'Performance',
                ),
                const SizedBox(height: 8),

                _SettingCard(
                  children: [
                    _SwitchSetting(
                      title: 'Hardware Acceleration',
                      subtitle: 'Use GPU for video decoding (recommended)',
                      value: _useHardwareAcceleration,
                      onChanged: (value) {
                        setState(() {
                          _useHardwareAcceleration = value;
                        });
                      },
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // HTTP Headers Section
                _SectionHeader(
                  icon: Icons.http,
                  title: 'HTTP Headers',
                ),
                const SizedBox(height: 8),

                _SettingCard(
                  children: [
                    ListTile(
                      title: const Text(
                        'Custom Headers',
                        style: TextStyle(color: Colors.white),
                      ),
                      subtitle: Text(
                        _httpHeaders.isEmpty
                            ? 'No custom headers set'
                            : '${_httpHeaders.length} header(s) configured',
                        style: const TextStyle(
                            color: Colors.white60, fontSize: 13),
                      ),
                      trailing: const Icon(Icons.arrow_forward_ios,
                          size: 16, color: Colors.white54),
                      onTap: () {
                        _showHeadersDialog();
                      },
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Current State Section
                _SectionHeader(
                  icon: Icons.info_outline,
                  title: 'Current State',
                ),
                const SizedBox(height: 8),

                ListenableBuilder(
                  listenable: _controller,
                  builder: (context, _) {
                    return _SettingCard(
                      children: [
                        _InfoRow(
                            label: 'State',
                            value: _controller.state.state.name),
                        const Divider(height: 1),
                        _InfoRow(
                            label: 'Position',
                            value: _controller.formattedPosition),
                        const Divider(height: 1),
                        _InfoRow(
                            label: 'Duration',
                            value: _controller.formattedDuration),
                        const Divider(height: 1),
                        _InfoRow(
                            label: 'Volume',
                            value: '${(_controller.volume * 100).toInt()}%'),
                        const Divider(height: 1),
                        _InfoRow(
                            label: 'Speed', value: '${_controller.speed}x'),
                        const Divider(height: 1),
                        _InfoRow(
                            label: 'Is Playing',
                            value: _controller.isPlaying ? 'Yes' : 'No'),
                      ],
                    );
                  },
                ),

                const SizedBox(height: 32),

                // Apply Button
                ElevatedButton(
                  onPressed: _applyConfiguration,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Apply Configuration',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showHeadersDialog() {
    final keyController = TextEditingController();
    final valueController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: const Text(
            'Add HTTP Header',
            style: TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: keyController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Header Key',
                  labelStyle: TextStyle(color: Colors.white60),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white24),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF6366F1)),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: valueController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Header Value',
                  labelStyle: TextStyle(color: Colors.white60),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white24),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF6366F1)),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Example: Authorization: Bearer your-token',
                style: TextStyle(
                  color: Colors.white60,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (keyController.text.isNotEmpty &&
                    valueController.text.isNotEmpty) {
                  setState(() {
                    _httpHeaders[keyController.text] = valueController.text;
                  });
                  Navigator.pop(context);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
              ),
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;

  const _SectionHeader({
    required this.icon,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF6366F1), size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}

class _SettingCard extends StatelessWidget {
  final List<Widget> children;

  const _SettingCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: children,
      ),
    );
  }
}

class _SwitchSetting extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchSetting({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      title: Text(
        title,
        style: const TextStyle(color: Colors.white),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: Colors.white60, fontSize: 13),
      ),
      value: value,
      onChanged: onChanged,
      activeColor: const Color(0xFF6366F1),
    );
  }
}

class _DropdownSetting extends StatelessWidget {
  final String title;
  final String subtitle;
  final BoxFit value;
  final List<DropdownMenuItem<BoxFit>> items;
  final ValueChanged<BoxFit?> onChanged;

  const _DropdownSetting({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(
        title,
        style: const TextStyle(color: Colors.white),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: Colors.white60, fontSize: 13),
      ),
      trailing: DropdownButton<BoxFit>(
        value: value,
        items: items,
        onChanged: onChanged,
        dropdownColor: const Color(0xFF1E293B),
        style: const TextStyle(color: Colors.white),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white60, fontSize: 14),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
