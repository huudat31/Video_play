import 'dart:async';
import 'dart:math';
import 'package:audioplayers/audioplayers.dart';
import 'package:display_metrics/display_metrics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

class BinocularPlayerPage extends StatefulWidget {
  final String url;
  final bool isBinocular;
  const BinocularPlayerPage({
    super.key,
    this.url = 'https://user-images.githubusercontent.com/28951144/229373695-22f88f13-d18f-4288-9bf1-c3e078d83722.mp4',
    this.isBinocular = true,
  });

  @override
  State<BinocularPlayerPage> createState() => BinocularPlayerPageState();
}

class BinocularPlayerPageState extends State<BinocularPlayerPage>
    with WidgetsBindingObserver {
  late final Player _player;
  late final VideoController _controller;

  final Stopwatch _watch = Stopwatch();
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<bool>? _bufferingSub;
  StreamSubscription<bool>? _completedSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<String>? _errorSub;
  bool _isBuffering = false;
  int _lastSentDuration = 0;

  final _progressNotifier = ValueNotifier<double>(0);
  final _positionNotifier = ValueNotifier<Duration>(Duration.zero);
  final _durationNotifier = ValueNotifier<Duration>(Duration.zero);
  bool _isDragging = false;
  double _dragValue = 0;

  bool _showControls = true;
  bool _isPlaying = false;
  bool _isCompleted = false;
  Timer? _hideTimer;

  bool _isLoading = true;
  final _networkSpeedNotifier = ValueNotifier<String>('');
  int _lastPositionMs = 0;
  DateTime _lastPositionTime = DateTime.now();

  AudioPlayer? _audioPlayer;

  Offset _videoOffset = Offset.zero;
  double _videoScale = 1.0;
  double _minScale = 0.7;
  double _maxScale = 1.0;
  double _scaleStart = 1.0;
  bool _isPanning = false;

  Size? _cachedVideoSize;
  Size? _cachedHalfSize;
  StreamSubscription<VideoParams>? _videoParamsSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    _player = Player();
    _controller = VideoController(_player);
    _videoParamsSub = _player.stream.videoParams.listen((params) {
      if (params.w != null && params.h != null && mounted) {
        setState(() {
          _cachedVideoSize = null;
          _cachedHalfSize = null;
        });
      }
    });
    void updateWatch() {
      if (_player.state.playing && !_isBuffering) {
        if (!_watch.isRunning) _watch.start();
      } else {
        if (_watch.isRunning) _watch.stop();
      }
    }

    _playingSub = _player.stream.playing.listen((playing) {
      setState(() => _isPlaying = playing);
      updateWatch();
    });

    _bufferingSub = _player.stream.buffering.listen((buffering) {
      _isBuffering = buffering;
      updateWatch();
    });

    _positionSub = _player.stream.position.listen((pos) {
      _positionNotifier.value = pos;
      if (!_isDragging) {
        final dur = _durationNotifier.value;
        if (dur.inMilliseconds > 0) {
          _progressNotifier.value =
              (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0);
        }
      }

      final now = DateTime.now();
      final dtMs = now.difference(_lastPositionTime).inMilliseconds;
      if (dtMs >= 1000) {
        final playedMs = pos.inMilliseconds - _lastPositionMs;
        if (playedMs > 0) {
          final bufferAheadSec = _player.state.buffer.inMilliseconds - pos.inMilliseconds;
          final kbps = (bufferAheadSec / 1000 * 2000).clamp(0, 99999).toInt();
          _networkSpeedNotifier.value = kbps > 1000
              ? '${(kbps / 1000 / 8).toStringAsFixed(1)} MB/s'
              : '${(kbps / 8).toStringAsFixed(0)} KB/s';
        }
        _lastPositionMs = pos.inMilliseconds;
        _lastPositionTime = now;
      }
    });

    _durationSub = _player.stream.duration.listen((dur) {
      _durationNotifier.value = dur;
    });

    _completedSub = _player.stream.completed.listen((completed) {
      if (completed) {
        _positionNotifier.value = _durationNotifier.value;
        _progressNotifier.value = 1.0;
        _sendTracking();

        if (widget.isBinocular) {
          Future.delayed(const Duration(milliseconds: 300), () async {
            if (!mounted) return;
            await _playOwariAudio();
            await SystemChrome.setPreferredOrientations([
              DeviceOrientation.portraitUp,
            ]);
            await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
            if (!mounted) return;
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (_) => BinocularResultPage(duration: _watch.elapsed.inSeconds),
              ),
            );
          });
          return;
        }

        Future.delayed(const Duration(milliseconds: 300), () {
          if (!mounted) return;
          setState(() {
            _isCompleted = true;
            _showControls = true;
          });
          _hideTimer?.cancel();
        });
      }
    });

    _errorSub = _player.stream.error.listen((error) {
      if (mounted && error.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('動画の再生に失敗しました。再度お試しください: $error')),
        );
      }
    });

    _prepareAndPlay();
  }

  Future<void> _prepareAndPlay() async {
    try {
      await _player.open(Media(widget.url), play: false);
      await _waitForPlayerReady(_player);
      if (!mounted) return;
      await _player.seek(Duration.zero);
      await _player.play();
      if (mounted) {
        setState(() {
          _showControls = true;
        });
      }
      _startHideTimer();
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

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
    final targetBuffer = duration < const Duration(seconds: 3)
        ? duration
        : const Duration(seconds: 3);
    if (targetBuffer > Duration.zero && player.state.buffer < targetBuffer) {
      await player.stream.buffer.firstWhere((b) => b >= targetBuffer);
    }
  }

  Future<void> _playOwariAudio() async {
    _audioPlayer?.stop();
    _audioPlayer = AudioPlayer();
    final completer = Completer<void>();
    _audioPlayer!.onPlayerComplete.listen((_) {
      if (!completer.isCompleted) completer.complete();
    });
    await _audioPlayer!.play(AssetSource('sound/end_binocular.mp3'), volume: 1.5);
    await completer.future;
  }

  void _sendTracking() {
    if (widget.isBinocular) return;
    final totalSeconds = _watch.elapsed.inSeconds;
    final delta = totalSeconds - _lastSentDuration;
    if (delta > 0) {
      _lastSentDuration = totalSeconds;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _player.pause();
      _watch.stop();
      _sendTracking();
      if (widget.isBinocular) {
        _audioPlayer?.pause();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sendTracking();
    _hideTimer?.cancel();
    _playingSub?.cancel();
    _bufferingSub?.cancel();
    _completedSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _errorSub?.cancel();
    _videoParamsSub?.cancel();
    _networkSpeedNotifier.dispose();
    _progressNotifier.dispose();
    _positionNotifier.dispose();
    _durationNotifier.dispose();
    _audioPlayer?.stop();
    _audioPlayer?.dispose();
    _player.dispose();
    super.dispose();
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
      _player.pause();
    } else {
      _player.play();
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
    _player.seek(seekTo);
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Size _computeVideoSize(Size halfSize) {
    final stateW = _controller.player.state.width;
    final stateH = _controller.player.state.height;
    if (stateW == null || stateH == null || stateH == 0) return Size.zero;

    final aspectRatio = stateW / stateH;
    final fitW = halfSize.width;
    final fitH = fitW / aspectRatio;
    return Size(fitW, fitH);
  }

  void _clampOffsetToLimits(Size halfSize, Size videoSize) {
    final scaledW = videoSize.width * _videoScale;
    final scaledH = videoSize.height * _videoScale;
    final dxLimit = (halfSize.width - scaledW).abs() / 2;
    final dyLimit = (halfSize.height - scaledH).abs() / 2;

    _videoOffset = Offset(
      _videoOffset.dx.clamp(-dxLimit, dxLimit),
      _videoOffset.dy.clamp(-dyLimit, dyLimit),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DisplayMetricsWidget(
      child: Builder(builder: (innerContext) {
        return PopScope(
          canPop: false,
          child: Scaffold(
            backgroundColor: Colors.black,
            body: LayoutBuilder(
              builder: (ctx, constraints) {
                final screenSize = Size(constraints.maxWidth, constraints.maxHeight);

                return Builder(builder: (metricsCtx) {
                  final metrics = DisplayMetrics.maybeOf(metricsCtx);
                  final gapPx = metrics != null ? _mmToLogicalPx(3, metricsCtx) : 0.0;

                  final halfWidth = (screenSize.width - gapPx) / 2;
                  final halfSize = Size(halfWidth, screenSize.height);

                  if (_cachedHalfSize != halfSize) {
                    final computed = _computeVideoSize(halfSize);
                    if (computed != Size.zero) {
                      _cachedVideoSize = computed;
                      _cachedHalfSize = halfSize;
                      _minScale = 0.7;
                      _maxScale = 1.0;
                      _videoScale = 1.0;
                      _videoOffset = Offset.zero;
                    }
                  }
                  final videoSize = _cachedVideoSize ?? _computeVideoSize(halfSize);
                  if (videoSize == Size.zero) {
                    // Chưa có metadata → render Video bình thường, chờ _videoParamsSub trigger rebuild
                    return Stack(
                      children: [
                        const Center(child: SizedBox.expand()),
                        Positioned.fill(
                          child: AbsorbPointer(
                            child: Video(
                              controller: _controller,
                              filterQuality: FilterQuality.high,
                              controls: NoVideoControls,
                            ),
                          ),
                        ),
                      ],
                    );
                  }

                  return Listener(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        if (!_isPanning) {
                          _onTapScreen();
                        }
                      },
                      onScaleStart: (details) {
                        _scaleStart = _videoScale;
                        _isPanning = details.pointerCount == 1;
                      },
                      onScaleUpdate: (details) {
                        if (details.pointerCount >= 2) {
                          _isPanning = false;
                          final newScale = (_scaleStart * details.scale)
                              .clamp(_minScale, _maxScale);
                          _videoScale = newScale;
                          _clampOffsetToLimits(halfSize, videoSize);
                          setState(() {});
                        } else {
                          _isPanning = true;
                          _videoOffset = Offset(
                            _videoOffset.dx + details.focalPointDelta.dx,
                            _videoOffset.dy + details.focalPointDelta.dy,
                          );
                          _clampOffsetToLimits(halfSize, videoSize);
                          setState(() {});
                        }
                      },
                      onScaleEnd: (_) {
                        Future.delayed(Duration.zero, () {
                          if (mounted) setState(() => _isPanning = false);
                        });
                      },
                      child: Stack(
                        children: [
                          Positioned(
                            left: 0, top: 0,
                            width: halfSize.width,
                            height: halfSize.height,
                            child: ClipRect(
                              child: Align(
                                alignment: Alignment.center,
                                child: Transform.translate(
                                  offset: Offset(-_videoOffset.dx, _videoOffset.dy),
                                  child: Transform.scale(
                                    scale: _videoScale,
                                    child: SizedBox(
                                      width: videoSize.width,
                                      height: videoSize.height,
                                      child: AbsorbPointer(
                                        child: Video(
                                          controller: _controller,
                                          filterQuality: FilterQuality.high,
                                          controls: NoVideoControls,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),

                          Positioned(
                            left: halfSize.width,
                            top: 0,
                            width: gapPx,
                            height: screenSize.height,
                            child: const ColoredBox(color: Colors.black),
                          ),

                          Positioned(
                            left: halfSize.width + gapPx, top: 0,
                            width: halfSize.width,
                            height: halfSize.height,
                            child: ClipRect(
                              child: Align(
                                alignment: Alignment.center,
                                child: Transform.translate(
                                  offset: Offset(_videoOffset.dx, _videoOffset.dy),
                                  child: Transform.scale(
                                    scale: _videoScale,
                                    child: SizedBox(
                                      width: videoSize.width,
                                      height: videoSize.height,
                                      child: AbsorbPointer(
                                        child: Video(
                                          controller: _controller,
                                          filterQuality: FilterQuality.high,
                                          controls: NoVideoControls,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),

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
                          if (!_isCompleted)
                          Positioned(
                            top: 0, left: 0, right: 0,
                            child: Center(
                              child: Builder(
                                builder: (ctx) {
                                  final m = DisplayMetrics.maybeOf(ctx);
                                  if (m == null) return const SizedBox.shrink();
                                  final sidePx = _mmToLogicalPx(3, ctx);
                                  return CustomPaint(
                                    size: Size(sidePx, sidePx * sqrt(3) / 2),
                                    painter: DownArrowPainter(),
                                  );
                                },
                              ),
                            ),
                          ),
                          if (!_isCompleted)
                          Builder(
                            builder: (ctx) {
                              final m = DisplayMetrics.maybeOf(ctx);
                              if (m == null) return const SizedBox.shrink();
                              final sidePx = _mmToLogicalPx(3, ctx);
                              final arrowW = sidePx;
                              final arrowH = sidePx * sqrt(3) / 2;
                              final centerX = halfSize.width / 2 - _videoOffset.dx;
                              return Positioned(
                                top: 0,
                                left: centerX - arrowW / 2,
                                child: CustomPaint(
                                  size: Size(arrowW, arrowH),
                                  painter: DownArrowPainter(),
                                ),
                              );
                            },
                          ),
                          if (!_isCompleted)
                          Builder(
                            builder: (ctx) {
                              final m = DisplayMetrics.maybeOf(ctx);
                              if (m == null) return const SizedBox.shrink();
                              final sidePx = _mmToLogicalPx(3, ctx);
                              final arrowW = sidePx;
                              final arrowH = sidePx * sqrt(3) / 2;
                              final centerX = halfSize.width + gapPx + halfSize.width / 2 + _videoOffset.dx;
                              return Positioned(
                                top: 0,
                                left: centerX - arrowW / 2,
                                child: CustomPaint(
                                  size: Size(arrowW, arrowH),
                                  painter: DownArrowPainter(),
                                ),
                              );
                            },
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

                          Positioned(
                            bottom: 8.h, left: 8.w,
                            child: ValueListenableBuilder<String>(
                              valueListenable: _networkSpeedNotifier,
                              builder: (_, speed, child) => speed.isEmpty
                                  ? const SizedBox.shrink()
                                  : Text(speed,
                                  style: TextStyle(
                                    color: Colors.white.withAlpha(64),
                                    fontSize: 8,
                                    fontFamily: 'monospace',
                                  )),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                });
              },
            ),
          ),
        );
      }),
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
            onTap: () {
              setState(() => _isCompleted = false);
              _progressNotifier.value = 0;
              _positionNotifier.value = Duration.zero;
              _player.seek(Duration.zero);
              _player.play();
              _startHideTimer();
            },
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
}

double _mmToLogicalPx(double mm, BuildContext context) {
  final metrics = DisplayMetrics.of(context);
  return mm / 25.4 * metrics.inchesToLogicalPixelRatio;
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

class DownArrowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class BinocularResultPage extends StatelessWidget {
  final int duration;
  const BinocularResultPage({super.key, required this.duration});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 84),
            const SizedBox(height: 24),
            const Text(
              'トレーニング完了',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '再生時間: $duration 秒',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 36),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1C79C3),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('ホームに戻る', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}
