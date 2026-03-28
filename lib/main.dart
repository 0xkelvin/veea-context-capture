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

class _DashboardScreenState extends State<DashboardScreen> {
  String? _sharedDirPath;
  List<File> _snapshots = [];
  Timer? _pollingTimer;
  double _currentFPS = 1.0;
  int _maxFrames = 300;
  final Set<String> _selectedPaths = {};

  @override
  void initState() {
    super.initState();
    _initBridge();
  }

  Future<void> _initBridge() async {
    final path = await BridgeService.getSharedDirectory();
    final fps = await BridgeService.getFPS();
    final maxF = await BridgeService.getMaxFrames();
    setState(() {
      _sharedDirPath = path;
      _currentFPS = fps;
      _maxFrames = maxF;
    });

    if (_sharedDirPath != null) {
      _loadSnapshots();
      // Poll for new frames from the background Swift extension
      _pollingTimer = Timer.periodic(const Duration(seconds: 1), (_) => _loadSnapshots());
    }
  }

  void _loadSnapshots() {
    if (_sharedDirPath == null) return;
    final dir = Directory(_sharedDirPath!);
    if (!dir.existsSync()) return;

    final files = dir.listSync().whereType<File>().where((f) => f.existsSync()).toList();
    files.sort((a, b) {
      try {
        if (!a.existsSync() || !b.existsSync()) return 0;
        return b.lastModifiedSync().compareTo(a.lastModifiedSync()); // Newest first
      } catch (_) {
        return 0;
      }
    });

    setState(() {
      _snapshots = files;
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
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

  void _deleteSelected() {
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
    _loadSnapshots();
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
                  const Text("Capture Rate", style: TextStyle(fontWeight: FontWeight.w600)),
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
                          Image.file(file, fit: BoxFit.cover, gaplessPlayback: true),
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
    return InkWell(
      onTap: () {
        BridgeService.launchCapture();
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
              const Text("Tap to Record", style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
              const SizedBox(width: 8),
            ],
            const Icon(Icons.radio_button_checked, color: Colors.redAccent),
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
