import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  runApp(const VeeaContextApp());
}

class BridgeService {
  static const MethodChannel _channel = MethodChannel('ai.bluleap.veea/bridge');

  static Future<String?> getSharedDirectory() async {
    try {
      return await _channel.invokeMethod<String>('getSharedDir');
    } catch (e) {
      debugPrint("Bridge getSharedDir Error: $e");
      return null;
    }
  }

  static Future<void> setFPS(double fps) async {
    try {
      await _channel.invokeMethod('setSetting', {'key': 'capture_fps', 'value': fps});
    } catch (e) {
      debugPrint("Bridge setFPS Error: $e");
    }
  }

  static Future<double> getFPS() async {
    try {
      final res = await _channel.invokeMethod('getSetting', {'key': 'capture_fps'});
      return (res as num?)?.toDouble() ?? 1.0;
    } catch (e) {
      debugPrint("Bridge getFPS Error: $e");
      return 1.0;
    }
  }

  static Future<void> setMaxFrames(int max) async {
    try {
      await _channel.invokeMethod('setSetting', {'key': 'max_frames', 'value': max});
    } catch (e) {
      debugPrint("Bridge setMaxFrames Error: $e");
    }
  }

  static Future<int> getMaxFrames() async {
    try {
      final res = await _channel.invokeMethod('getSetting', {'key': 'max_frames'});
      return res as int? ?? 300;
    } catch (e) {
      debugPrint("Bridge getMaxFrames Error: $e");
      return 300;
    }
  }

  static Future<void> launchCapture() async {
    try {
      await _channel.invokeMethod('launchCapture');
    } catch (e) {
      debugPrint("Bridge launchCapture Error: $e");
    }
  }

  static Future<void> setSensitivity(double sensitivity) async {
    try {
      await _channel.invokeMethod('setSetting', {'key': 'capture_sensitivity', 'value': sensitivity});
    } catch (e) {
      debugPrint("Bridge setSensitivity Error: $e");
    }
  }

  static Future<double> getSensitivity() async {
    try {
      final res = await _channel.invokeMethod('getSetting', {'key': 'capture_sensitivity'});
      return (res as num?)?.toDouble() ?? 0.03;
    } catch (e) {
      debugPrint("Bridge getSensitivity Error: $e");
      return 0.03;
    }
  }

  /// Whether the user has requested capture to remain active (used for
  /// auto-restart after screen lock).
  static Future<bool> getCaptureWantsActive() async {
    try {
      final res = await _channel.invokeMethod('getSetting', {'key': 'capture_wants_active'});
      return res as bool? ?? false;
    } catch (e) {
      debugPrint("Bridge getCaptureWantsActive Error: $e");
      return false;
    }
  }

  /// Sets the user-intent flag that controls auto-restart after screen lock.
  static Future<void> setCaptureWantsActive(bool value) async {
    try {
      await _channel.invokeMethod('setSetting', {'key': 'capture_wants_active', 'value': value});
    } catch (e) {
      debugPrint("Bridge setCaptureWantsActive Error: $e");
    }
  }

  /// Whether the broadcast extension is currently running.
  /// This can differ from [getCaptureWantsActive] after a screen lock: the
  /// user still *wants* capture active but the extension was killed by iOS.
  static Future<bool> getCaptureIsRunning() async {
    try {
      final res = await _channel.invokeMethod('getSetting', {'key': 'capture_is_running'});
      return res as bool? ?? false;
    } catch (e) {
      debugPrint("Bridge getCaptureIsRunning Error: $e");
      return false;
    }
  }
}

class VeeaContextApp extends StatelessWidget {
  const VeeaContextApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Veea Edge AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F0F13),
        primaryColor: const Color(0xFF5E5CE6),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF5E5CE6),
          secondary: Color(0xFFBF5AF2),
          surface: Color(0xFF1C1C1E),
        ),
        textTheme: const TextTheme(
          headlineMedium: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontFamily: '.SF Pro Display'),
        ),
      ),
      home: const DashboardScreen(),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  String? _sharedDirPath;
  List<File> _snapshots = [];
  Timer? _pollingTimer;
  double _currentFPS = 1.0;
  int _maxFrames = 300;
  // Change sensitivity threshold stored as a percentage (1–20 %).
  // The native layer expects a fraction (0.01–0.20); conversion is done at
  // the bridge call sites to avoid repeated round-trip precision loss.
  double _sensitivityPct = 3.0; // default 3 %
  final Set<String> _selectedPaths = {};

  /// Whether the user has asked capture to stay active (controls auto-restart).
  bool _captureWantsActive = false;

  /// Whether the broadcast extension is currently running.
  /// Can differ from [_captureWantsActive] when recording was paused by a
  /// screen lock (wantsActive=true, isRunning=false → "Resume Capture" state).
  bool _captureIsRunning = false;

  // Adaptive polling: backs off when nothing changes, resets on change.
  Duration _pollInterval = const Duration(seconds: 1);
  static const _pollIntervalMin = Duration(seconds: 1);
  static const _pollIntervalMax = Duration(seconds: 5);
  int _lastKnownFileCount = 0;
  String? _lastNewestPath;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initBridge();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollingTimer?.cancel();
    super.dispose();
  }

  /// Refresh capture-state flags when the app returns to the foreground
  /// (e.g. after a screen unlock) so the UI reflects the current situation.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshCaptureState();
    }
  }

  Future<void> _refreshCaptureState() async {
    final wantsActive = await BridgeService.getCaptureWantsActive();
    final isRunning = await BridgeService.getCaptureIsRunning();
    if (mounted) setState(() {
      _captureWantsActive = wantsActive;
      _captureIsRunning = isRunning;
    });
  }

  Future<void> _initBridge() async {
    final path = await BridgeService.getSharedDirectory();
    final fps = await BridgeService.getFPS();
    final maxF = await BridgeService.getMaxFrames();
    final sensitivity = await BridgeService.getSensitivity();
    final wantsActive = await BridgeService.getCaptureWantsActive();
    final isRunning = await BridgeService.getCaptureIsRunning();
    if (!mounted) return;
    setState(() {
      _sharedDirPath = path;
      _currentFPS = fps;
      _maxFrames = maxF;
      _sensitivityPct = (sensitivity * 100).roundToDouble().clamp(1, 20);
      _captureWantsActive = wantsActive;
      _captureIsRunning = isRunning;
    });

    if (_sharedDirPath != null) {
      await _loadSnapshots();
      if (!mounted) return;
      _schedulePoll();
    }
  }

  /// Schedules the next poll using a one-shot timer so the interval can adapt.
  /// The delay is measured from the *end* of each poll, which naturally prevents
  /// overlapping polls if a directory listing takes longer than the interval.
  void _schedulePoll() {
    _pollingTimer = Timer(_pollInterval, () async {
      await _loadSnapshots();
      if (mounted) _schedulePoll();
    });
  }

  Future<void> _loadSnapshots() async {
    if (_sharedDirPath == null) return;
    final dir = Directory(_sharedDirPath!);
    try {
      if (!await dir.exists()) return;

      final files = await dir
          .list()
          .where((e) => e is File)
          .cast<File>()
          .toList();

      if (!mounted) return;

      // O(n) scan to find the newest filename — much cheaper than an
      // O(n log n) sort that we can skip entirely when nothing changed.
      final newestPath = files.isNotEmpty
          ? files.reduce((a, b) => a.path.compareTo(b.path) > 0 ? a : b).path
          : null;

      if (files.length == _lastKnownFileCount && newestPath == _lastNewestPath) {
        // Nothing changed — exponentially back off the polling interval
        // (1 s → 2 s → 4 s → 5 s cap) to reduce idle I/O churn.
        _pollInterval = Duration(
          milliseconds: (_pollInterval.inMilliseconds * 2).clamp(
            _pollIntervalMin.inMilliseconds,
            _pollIntervalMax.inMilliseconds,
          ),
        );
        return;
      }

      // Change detected — sort newest-first and refresh the UI.
      files.sort((a, b) => b.path.compareTo(a.path));
      _lastKnownFileCount = files.length;
      _lastNewestPath = newestPath;
      _pollInterval = _pollIntervalMin;

      setState(() {
        _snapshots = files;
      });
    } catch (e) {
      debugPrint('_loadSnapshots error: $e');
    }
  }

  Future<void> _shareSelected() async {
    final pathsToShare = _selectedPaths.isNotEmpty
        ? _selectedPaths.toList()
        : (_snapshots.isNotEmpty ? [_snapshots.first.path] : []);
        
    if (pathsToShare.isEmpty) return;
    
    final xFiles = pathsToShare.map((p) => XFile(p)).toList();
    await Share.shareXFiles(xFiles, text: 'Veea Edge Context');
    
    setState(() {
      _selectedPaths.clear();
    });
  }

  Future<void> _deleteSelected() async {
    if (_selectedPaths.isEmpty) return;
    for (final path in _selectedPaths) {
      final file = File(path);
      if (file.existsSync()) {
        try {
          file.deleteSync();
        } catch (_) {}
      }
    }
    setState(() {
      _selectedPaths.clear();
    });
    await _loadSnapshots();
  }

  void _toggleSelectAll() {
    setState(() {
      if (_selectedPaths.length == _snapshots.length) {
        _selectedPaths.clear();
      } else {
        _selectedPaths.addAll(_snapshots.map((f) => f.path));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background Gradient
          Positioned(
            top: -100, left: -100,
            child: Container(
              width: 300, height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4),
                boxShadow: [BoxShadow(blurRadius: 100, spreadRadius: 50, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5))],
              ),
            ),
          ),
          Positioned(
            bottom: -50, right: -50,
            child: Container(
              width: 250, height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.3),
                boxShadow: [BoxShadow(blurRadius: 100, spreadRadius: 50, color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.4))],
              ),
            ),
          ),
          
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(),
                _buildSettingsBar(),
                Expanded(child: _buildGallery()),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: _snapshots.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _shareSelected,
              icon: const Icon(Icons.ios_share_rounded, color: Colors.white),
              label: Text(_selectedPaths.isNotEmpty ? "Share \${_selectedPaths.length} Selected" : "Share Latest", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              backgroundColor: Theme.of(context).colorScheme.primary,
            )
          : null,
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Veea Edge AI", style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 34)),
          const SizedBox(height: 8),
          const Text("Live Context Bridge", style: TextStyle(color: Colors.white70, fontSize: 16)),
        ],
      ),
    );
  }

  Widget _buildSettingsBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: GlassMorphCard(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Column(
            children: [
              Row(
                children: [
                  const Icon(Icons.speed, color: Colors.white70),
                  const SizedBox(width: 12),
                  const Text("Max Capture Rate", style: TextStyle(fontWeight: FontWeight.w600)),
                  const Spacer(),
                  DropdownButton<double>(
                    value: _currentFPS,
                    dropdownColor: const Color(0xFF2C2C2E),
                    underline: const SizedBox(),
                    icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white54),
                    items: [0.1, 0.2, 0.5, 1.0, 2.0, 5.0].map((fps) => DropdownMenuItem(value: fps, child: Text("$fps FPS", style: const TextStyle(color: Colors.white)))).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        BridgeService.setFPS(val);
                        setState(() => _currentFPS = val);
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.tune, color: Colors.white70),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      "Change Sensitivity",
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(
                    "${_sensitivityPct.round()}%",
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent),
                  ),
                ],
              ),
              Slider(
                value: _sensitivityPct.clamp(1, 20),
                min: 1,
                max: 20,
                divisions: 19,
                activeColor: Theme.of(context).colorScheme.secondary,
                inactiveColor: Colors.white24,
                onChanged: (val) {
                  setState(() => _sensitivityPct = val);
                },
                onChangeEnd: (val) {
                  BridgeService.setSensitivity(val / 100);
                },
              ),
              const Padding(
                padding: EdgeInsets.only(bottom: 4.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("Sensitive", style: TextStyle(fontSize: 11, color: Colors.white38)),
                    Text("Major changes only", style: TextStyle(fontSize: 11, color: Colors.white38)),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.sd_storage, color: Colors.white70),
                  const SizedBox(width: 12),
                  const Text("Max Storage", style: TextStyle(fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Text("$_maxFrames", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent)),
                ],
              ),
              Slider(
                value: _maxFrames.toDouble(),
                min: 30,
                max: 10000,
                divisions: 100,
                activeColor: Theme.of(context).colorScheme.primary,
                inactiveColor: Colors.white24,
                onChanged: (val) {
                  setState(() => _maxFrames = val.toInt());
                },
                onChangeEnd: (val) {
                  BridgeService.setMaxFrames(val.toInt());
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGallery() {
    if (_snapshots.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.remove_red_eye_outlined, size: 60, color: Colors.white24),
            const SizedBox(height: 16),
            const Text("No Context Available", style: TextStyle(color: Colors.white54, fontSize: 18)),
            const SizedBox(height: 32),
            _buildCaptureLauncher(),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (_selectedPaths.isEmpty)
                Expanded(child: Text("Live Stream (${_snapshots.length} frames)", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)))
              else
                Expanded(
                  child: Row(
                    children: [
                      Text("${_selectedPaths.length} Selected", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.blueAccent)),
                      IconButton(icon: const Icon(Icons.select_all), color: Colors.white70, onPressed: _toggleSelectAll),
                      IconButton(icon: const Icon(Icons.delete_outline, color: Colors.redAccent), onPressed: _deleteSelected),
                    ],
                  ),
                ),
              _buildCaptureLauncher(mini: true),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: GridView.builder(
              physics: const BouncingScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 0.56, // Tall ratio for phone screens
              ),
              itemCount: _snapshots.length,
              itemBuilder: (context, index) {
                final file = _snapshots[index];
                final isLatest = index == 0;
                final isSelected = _selectedPaths.contains(file.path);
                
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      if (isSelected) {
                        _selectedPaths.remove(file.path);
                      } else {
                        _selectedPaths.add(file.path);
                      }
                    });
                  },
                  child: Hero(
                    tag: file.path,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected
                              ? Theme.of(context).colorScheme.secondary
                              : (isLatest ? Theme.of(context).colorScheme.primary : Colors.transparent),
                          width: isSelected || isLatest ? 3 : 0,
                        ),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 10, offset: const Offset(0, 5)),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.file(file, fit: BoxFit.cover, gaplessPlayback: true, cacheWidth: 480),
                          if (isSelected)
                            Container(
                              color: Colors.black45,
                              child: const Center(
                                child: Icon(Icons.check_circle, color: Colors.white, size: 40),
                              ),
                            ),
                          if (isLatest && !isSelected) ...[
                            Positioned(
                              top: 8, left: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, borderRadius: BorderRadius.circular(8)),
                                child: const Text("LIVE", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                              ),
                            )
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCaptureLauncher({bool mini = false}) {
    final wantsActive = _captureWantsActive;
    final isRunning   = _captureIsRunning;

    // Derive the three distinct UI states:
    //   • running  – wantsActive=true,  isRunning=true  → "Stop Capture"
    //   • paused   – wantsActive=true,  isRunning=false → "Resume Capture"
    //     (extension was killed by a screen lock)
    //   • stopped  – wantsActive=false                  → "Tap to Record"
    final String label;
    final Color  iconColor;
    final IconData icon;
    if (wantsActive && isRunning) {
      label     = "Stop Capture";
      iconColor = Colors.orangeAccent;
      icon      = Icons.stop_circle_outlined;
    } else if (wantsActive && !isRunning) {
      label     = "Resume Capture";
      iconColor = Colors.blueAccent;
      icon      = Icons.play_circle_outline;
    } else {
      label     = "Tap to Record";
      iconColor = Colors.redAccent;
      icon      = Icons.radio_button_checked;
    }

    return InkWell(
      onTap: () async {
        if (wantsActive && isRunning) {
          // Stop: cancel the auto-restart intent.
          // The broadcast itself keeps running until stopped via iOS Control
          // Centre / status bar.
          await BridgeService.setCaptureWantsActive(false);
          if (mounted) setState(() {
            _captureWantsActive = false;
            _captureIsRunning = false;
          });
        } else if (wantsActive && !isRunning) {
          // Paused after a screen lock – re-trigger the broadcast picker.
          await BridgeService.launchCapture();
        } else {
          // Start fresh: persist intent then show the broadcast picker.
          await BridgeService.setCaptureWantsActive(true);
          if (mounted) setState(() => _captureWantsActive = true);
          await BridgeService.launchCapture();
        }
      },
      borderRadius: BorderRadius.circular(25),
      child: Container(
        width: mini ? 50 : 200,
        height: 50,
        decoration: BoxDecoration(
          color: !mini ? Theme.of(context).colorScheme.surface.withValues(alpha: 0.8) : Colors.transparent,
          borderRadius: BorderRadius.circular(25),
          border: mini ? Border.all(color: Colors.white12) : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (!mini) ...[
              Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white),
              ),
              const SizedBox(width: 8),
            ],
            Icon(icon, color: iconColor),
          ],
        ),
      ),
    );
  }
}

class GlassMorphCard extends StatelessWidget {
  final Widget child;
  const GlassMorphCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: child,
        ),
      ),
    );
  }
}
