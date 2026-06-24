import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Cấu hình tối ưu cho phát song song 2 video.
const _playerConfiguration = PlayerConfiguration(bufferSize: 48 * 1024 * 1024);

/// Giảm scale vì mỗi video chỉ chiếm ~nửa màn hình, giảm tải GPU/CPU.
const _videoConfiguration = VideoControllerConfiguration(
  scale: 0.75,
  enableHardwareAcceleration: true,
);

const _minBufferAhead = Duration(seconds: 3);

/// Màn hình phát đồng thời 2 video trên cùng 1 màn hình theo chiều ngang.
class DualVideoPlayerPage extends StatefulWidget {
  const DualVideoPlayerPage({
    super.key,
    this.videoUrl1 =
        'https://user-images.githubusercontent.com/28951144/229373695-22f88f13-d18f-4288-9bf1-c3e078d83722.mp4',
    this.videoUrl2 =
        'https://user-images.githubusercontent.com/28951144/229373695-22f88f13-d18f-4288-9bf1-c3e078d83722.mp4',
  });

  /// URL của video bên trái.
  final String videoUrl1;

  /// URL của video bên phải.
  final String videoUrl2;

  @override
  State<DualVideoPlayerPage> createState() => _DualVideoPlayerPageState();
}

class _DualVideoPlayerPageState extends State<DualVideoPlayerPage> {
  late final Player _player1 = Player(configuration: _playerConfiguration);
  late final Player _player2 = Player(configuration: _playerConfiguration);

  late final VideoController _controller1 = VideoController(
    _player1,
    configuration: _videoConfiguration,
  );
  late final VideoController _controller2 = VideoController(
    _player2,
    configuration: _videoConfiguration,
  );

  bool _isLoading = true;

  StreamSubscription<bool>? _playingSub1;
  StreamSubscription<Duration>? _positionSub1;
  StreamSubscription<Duration>? _durationSub1;
  StreamSubscription<bool>? _completedSub1;
  StreamSubscription<String>? _errorSub1;
  StreamSubscription<String>? _errorSub2;

  final _progressNotifier = ValueNotifier<double>(0);
  final _positionNotifier = ValueNotifier<Duration>(Duration.zero);
  final _durationNotifier = ValueNotifier<Duration>(Duration.zero);

  bool _isDragging = false;
  double _dragValue = 0;

  bool _showControls = true;
  bool _isPlaying = false;
  bool _isCompleted = false;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _playingSub1 = _player1.stream.playing.listen((playing) {
      if (mounted) {
        setState(() => _isPlaying = playing);
      }
    });

    _positionSub1 = _player1.stream.position.listen((pos) {
      _positionNotifier.value = pos;
      if (!_isDragging) {
        final dur = _durationNotifier.value;
        if (dur.inMilliseconds > 0) {
          _progressNotifier.value =
              (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0);
        }
      }
    });

    _durationSub1 = _player1.stream.duration.listen((dur) {
      _durationNotifier.value = dur;
    });

    _completedSub1 = _player1.stream.completed.listen((completed) {
      if (completed) {
        _positionNotifier.value = _durationNotifier.value;
        _progressNotifier.value = 1.0;
        if (mounted) {
          setState(() {
            _isCompleted = true;
            _showControls = true;
          });
        }
        _hideTimer?.cancel();
      }
    });

    _errorSub1 = _player1.stream.error.listen((error) {
      _showError(error);
    });

    _errorSub2 = _player2.stream.error.listen((error) {
      _showError(error);
    });

    _prepareAndPlayTogether();
  }

  void _showError(String error) {
    if (mounted && error.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('動画の再生に失敗しました: $error')),
      );
    }
  }

  /// Mở tuần tự để tránh tranh băng thông, preload buffer rồi phát đồng thời.
  Future<void> _prepareAndPlayTogether() async {
    try {
      await _player1.open(Media(widget.videoUrl1), play: false);
      await _player2.open(Media(widget.videoUrl2), play: false);

      await Future.wait([
        _waitForPlayerReady(_player1),
        _waitForPlayerReady(_player2),
      ]);

      if (!mounted) return;

      await Future.wait([
        _player1.seek(Duration.zero),
        _player2.seek(Duration.zero),
      ]);
      await Future.wait([_player1.play(), _player2.play()]);
      _startHideTimer();
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Đợi metadata, frame đầu, hết buffering và buffer đủ trước khi phát.
  Future<void> _waitForPlayerReady(Player player) async {
    if (player.state.duration == Duration.zero) {
      await player.stream.duration.firstWhere((d) => d > Duration.zero);
    }
    if (player.state.width == null || player.state.width! <= 0) {
      await player.stream.width.firstWhere((w) => w != null && w > 0);
    }
    if (player.state.buffering) {
      await player.stream.buffering.firstWhere((b) => !b);
    }

    final duration = player.state.duration;
    final targetBuffer = duration < _minBufferAhead
        ? duration
        : _minBufferAhead;
    if (targetBuffer > Duration.zero && player.state.buffer < targetBuffer) {
      await player.stream.buffer.firstWhere((b) => b >= targetBuffer);
    }
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    if (_isCompleted) return;
    _hideTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && !_isCompleted) {
        setState(() => _showControls = false);
      }
    });
  }

  void _onTapScreen() {
    if (_isCompleted) return;
    setState(() => _showControls = !_showControls);
    if (_showControls) _startHideTimer();
  }

  void _togglePlayPause() {
    _startHideTimer();
    if (_isPlaying) {
      _player1.pause();
      _player2.pause();
    } else {
      _player1.play();
      _player2.play();
    }
  }

  void _onSeek(double value) {
    _startHideTimer();
    final dur = _durationNotifier.value;
    if (dur == Duration.zero) return;
    final seekTo = Duration(milliseconds: (value * dur.inMilliseconds).round());
    if (_isCompleted && seekTo < dur) {
      setState(() => _isCompleted = false);
    }
    _player1.seek(seekTo);
    _player2.seek(seekTo);
  }

  void _replay() {
    setState(() {
      _isCompleted = false;
      _showControls = true;
    });
    _progressNotifier.value = 0;
    _positionNotifier.value = Duration.zero;
    _player1.seek(Duration.zero);
    _player2.seek(Duration.zero);
    _player1.play();
    _player2.play();
    _startHideTimer();
  }

  @override
  void dispose() {
    _playingSub1?.cancel();
    _positionSub1?.cancel();
    _durationSub1?.cancel();
    _completedSub1?.cancel();
    _errorSub1?.cancel();
    _errorSub2?.cancel();

    _progressNotifier.dispose();
    _positionNotifier.dispose();
    _durationNotifier.dispose();
    _hideTimer?.cancel();

    _player1.dispose();
    _player2.dispose();

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );

    super.dispose();
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _onTapScreen,
            child: Stack(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _VideoPanel(
                        controller: _controller1,
                        enableWakelock: true,
                      ),
                    ),
                    const VerticalDivider(
                      width: 2,
                      thickness: 2,
                      color: Colors.white24,
                    ),
                    Expanded(
                      child: _VideoPanel(
                        controller: _controller2,
                        enableWakelock: false,
                      ),
                    ),
                  ],
                ),
                // Controls Overlay
                AnimatedOpacity(
                  opacity: _showControls ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 250),
                  child: IgnorePointer(
                    ignoring: !_showControls,
                    child: _isCompleted
                        ? _buildCompletedOverlay()
                        : _buildPlayingOverlay(),
                  ),
                ),
                if (_isLoading)
                  const Positioned.fill(
                    child: ColoredBox(
                      color: Colors.black54,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(color: Colors.white),
                            SizedBox(height: 16),
                            Text(
                              'Đang tải video...',
                              style: TextStyle(color: Colors.white70),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlayingOverlay() {
    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withAlpha(128),
                  Colors.transparent,
                  Colors.transparent,
                  Colors.black.withAlpha(153),
                ],
                stops: const [0, 0.2, 0.75, 1],
              ),
            ),
          ),
        ),
        Positioned(
          top: 16.h,
          left: 16.w,
          child: _CircleButton(
            onTap: () async {
              _startHideTimer();
              await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
              await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
              if (mounted) Navigator.of(context).pop();
            },
            child: Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20.w),
          ),
        ),
        Center(
          child: _CircleButton(
            size: 64.w,
            onTap: _togglePlayPause,
            child: Icon(
              _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: Colors.white,
              size: 28.w,
            ),
          ),
        ),
        Positioned(
          left: 16.w,
          right: 16.w,
          bottom: 52.h,
          child: _buildProgressBar(),
        ),
      ],
    );
  }

  Widget _buildCompletedOverlay() {
    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withAlpha(128),
                  Colors.transparent,
                  Colors.transparent,
                  Colors.black.withAlpha(153),
                ],
                stops: const [0, 0.3, 0.65, 1],
              ),
            ),
          ),
        ),
        Positioned(
          top: 16.h,
          left: 16.w,
          child: _CircleButton(
            onTap: () async {
              await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
              await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
              if (mounted) Navigator.of(context).pop();
            },
            child: Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20.w),
          ),
        ),
        Center(
          child: _CircleButton(
            size: 64.w,
            onTap: _replay,
            child: Icon(Icons.replay_rounded, color: Colors.white, size: 28.w),
          ),
        ),
        Positioned(
          left: 16.w,
          right: 16.w,
          bottom: 52.h,
          child: _buildProgressBar(),
        ),
      ],
    );
  }

  Widget _buildProgressBar() {
    final barWidth = MediaQuery.of(context).size.width - 32.w;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            ValueListenableBuilder<Duration>(
              valueListenable: _positionNotifier,
              builder: (_, pos, child) => Text(
                _formatDuration(pos),
                style: TextStyle(color: Colors.white, fontSize: 11.sp),
              ),
            ),
            ValueListenableBuilder<Duration>(
              valueListenable: _durationNotifier,
              builder: (_, dur, child) => Text(
                _formatDuration(dur),
                style: TextStyle(color: Colors.white, fontSize: 11.sp),
              ),
            ),
          ],
        ),
        SizedBox(height: 6.h),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {},
          onHorizontalDragStart: (d) {
            _hideTimer?.cancel();
            _isDragging = true;
            _dragValue = (d.localPosition.dx / barWidth).clamp(0.0, 1.0);
            _progressNotifier.value = _dragValue;
          },
          onHorizontalDragUpdate: (d) {
            _dragValue = (d.localPosition.dx / barWidth).clamp(0.0, 1.0);
            _progressNotifier.value = _dragValue;
          },
          onHorizontalDragEnd: (_) {
            _onSeek(_dragValue);
            _isDragging = false;
            _startHideTimer();
          },
          onTapDown: (d) {
            final ratio = (d.localPosition.dx / barWidth).clamp(0.0, 1.0);
            _progressNotifier.value = ratio;
            _onSeek(ratio);
          },
          child: Container(
            width: barWidth,
            height: 48.h,
            alignment: Alignment.center,
            child: ValueListenableBuilder<double>(
              valueListenable: _progressNotifier,
              builder: (_, progress, child) {
                return SizedBox(
                  width: barWidth,
                  height: 40.h,
                  child: Stack(
                    children: [
                      Container(
                        width: barWidth,
                        height: 40.h,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(2.r),
                          border: Border.all(
                            color: Colors.white.withAlpha(90),
                            width: 1,
                          ),
                          color: Colors.white.withAlpha(51),
                        ),
                      ),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2.r),
                        child: SizedBox(
                          width: barWidth * progress,
                          height: 40.h,
                          child: const ColoredBox(color: Color(0xFF1C79C3)),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _CircleButton extends StatelessWidget {
  final VoidCallback onTap;
  final Widget child;
  final double? size;

  const _CircleButton({
    required this.onTap,
    required this.child,
    this.size,
  });

  @override
  Widget build(BuildContext context) {
    final s = size ?? 48.w;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: s,
        height: s,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withAlpha(51),
          border: Border.all(
            color: Colors.black.withAlpha(128),
            width: 1.2,
          ),
        ),
        alignment: Alignment.center,
        child: child,
      ),
    );
  }
}

/// Tách riêng từng panel để giảm repaint và tối ưu render.
class _VideoPanel extends StatelessWidget {
  const _VideoPanel({required this.controller, required this.enableWakelock});

  final VideoController controller;
  final bool enableWakelock;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Video(
        controller: controller,
        controls: NoVideoControls,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.none,
        wakelock: enableWakelock,
      ),
    );
  }
}
