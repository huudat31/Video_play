import 'package:dual_video_player/binocular_player_page.dart';
import 'package:dual_video_player/dual_video_player_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:media_kit/media_kit.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: const Size(844, 390),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, child) {
        return MaterialApp(
          title: 'Dual Video Player',
          debugShowCheckedModeBanner: false,
          theme: ThemeData.dark().copyWith(
            scaffoldBackgroundColor: const Color(0xFF0F0C20),
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.deepPurple,
              brightness: Brightness.dark,
            ),
          ),
          home: const HomePage(),
        );
      },
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final TextEditingController _binocularController;
  late final TextEditingController _dual1Controller;
  late final TextEditingController _dual2Controller;

  @override
  void initState() {
    super.initState();
    _binocularController = TextEditingController();
    _dual1Controller = TextEditingController();
    _dual2Controller = TextEditingController();
  }

  @override
  void dispose() {
    _binocularController.dispose();
    _dual1Controller.dispose();
    _dual2Controller.dispose();
    super.dispose();
  }

  void _playBinocular() {
    final inputUrl = _binocularController.text.trim();
    final url = inputUrl.isNotEmpty
        ? inputUrl
        : 'https://user-images.githubusercontent.com/28951144/229373695-22f88f13-d18f-4288-9bf1-c3e078d83722.mp4';
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => BinocularPlayerPage(url: url)));
  }

  void _playDual() {
    final inputUrl1 = _dual1Controller.text.trim();
    final inputUrl2 = _dual2Controller.text.trim();
    const defaultUrl =
        'https://user-images.githubusercontent.com/28951144/229373695-22f88f13-d18f-4288-9bf1-c3e078d83722.mp4';
    final url1 = inputUrl1.isNotEmpty ? inputUrl1 : defaultUrl;
    final url2 = inputUrl2.isNotEmpty ? inputUrl2 : defaultUrl;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DualVideoPlayerPage(videoUrl1: url1, videoUrl2: url2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0F0C20), Color(0xFF15102A), Color(0xFF0A0814)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 16.h),
              child: Column(
                children: [
                  // Top Panel: Binocular Player
                  _buildPanel(
                    title: 'Binocular Player',
                    subtitle: 'Single source, split output screen',
                    icon: Icons.visibility_rounded,
                    color: Colors.blueAccent,
                    children: [
                      _buildTextField(
                        controller: _binocularController,
                        label: 'Video URL',
                        icon: Icons.link_rounded,
                      ),
                      SizedBox(height: 16.h),
                      _buildPlayButton(
                        onPressed: _playBinocular,
                        colors: [Colors.blue.shade600, Colors.blue.shade800],
                      ),
                    ],
                  ),
                  SizedBox(height: 20.h),
                  // Horizontal divider
                  Container(
                    height: 1.h,
                    width: double.infinity,
                    color: Colors.white10,
                  ),
                  SizedBox(height: 20.h),
                  // Bottom Panel: Dual Video Player
                  _buildPanel(
                    title: 'Dual Video Player',
                    subtitle: 'Two independent video streams side-by-side',
                    icon: Icons.screen_share,
                    color: Colors.deepPurpleAccent,
                    children: [
                      _buildTextField(
                        controller: _dual1Controller,
                        label: 'Left Video URL',
                        icon: Icons.link_rounded,
                      ),
                      SizedBox(height: 10.h),
                      _buildTextField(
                        controller: _dual2Controller,
                        label: 'Right Video URL',
                        icon: Icons.link_rounded,
                      ),
                      SizedBox(height: 16.h),
                      _buildPlayButton(
                        onPressed: _playDual,
                        colors: [
                          Colors.deepPurple.shade500,
                          Colors.deepPurple.shade700,
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPanel({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required List<Widget> children,
  }) {
    return Container(
      padding: EdgeInsets.all(16.r),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: Colors.white.withOpacity(0.08), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(8.r),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 24.r),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 18.sp,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 10.sp, color: Colors.white54),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 16.h),
          Column(children: children),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
  }) {
    return TextField(
      controller: controller,
      style: TextStyle(fontSize: 12.sp, color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(fontSize: 12.sp, color: Colors.white38),
        hintText: 'Enter URL (Leave empty for default)...',
        hintStyle: TextStyle(fontSize: 10.sp, color: Colors.white12),
        prefixIcon: Icon(icon, size: 16.r, color: Colors.white38),
        contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
        filled: true,
        fillColor: Colors.black26,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8.r),
          borderSide: const BorderSide(color: Colors.white12),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8.r),
          borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
        ),
      ),
    );
  }

  Widget _buildPlayButton({
    required VoidCallback onPressed,
    required List<Color> colors,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8.r),
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: colors.last.withOpacity(0.4),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8.r),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 12.h),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20.r),
                SizedBox(width: 8.w),
                Text(
                  'PLAY NOW',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13.sp,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
