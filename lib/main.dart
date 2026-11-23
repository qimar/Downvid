import 'dart:io';
import 'package:downvid/providers/ad_provider/ads_provider.dart';
import 'package:downvid/providers/downloaded_video_list_provider/downloaded_video_list_provider.dart';
import 'package:downvid/providers/home_download_provider/home_download_provider.dart';
import 'package:downvid/providers/theme_provider/theme_provider.dart';
import 'package:downvid/screens/downloaded/downloaded_list_screen.dart';
import 'package:downvid/screens/home/home_screen.dart';
import 'package:downvid/screens/home/remove_ads/remove_ads_screen.dart';
import 'package:background_downloader/background_downloader.dart';
import 'package:downvid/screens/setttings/languages_list_screen.dart';
import 'package:downvid/service_locator.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:media_store_plus/media_store_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:sizer/sizer.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';

void main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  
  // Hold the splash screen while plugins initialize
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  // 1. Give Android channels time to register — release mode needs longer than debug
  await Future.delayed(const Duration(milliseconds: 800));

  // 2. Pre-create providers (AdProvider created AFTER delay so plugin channels are warm)
  final adProvider = AdProvider();
  final downloadedVideoListProvider = DownloadedVideoListProvider();
  final themeProvider = ThemeProvider();

  // IMPORTANT: Every async call must be wrapped in try-catch.
  // If ANY call throws an unhandled exception, FlutterNativeSplash.remove()
  // is never reached, and the app gets permanently stuck on the splash screen.

  try {
    await FileDownloader().configure();
    debugPrint('[main] FileDownloader configured successfully');
  } catch (e) {
    debugPrint('[main] ⚠️ FileDownloader configure failed (non-fatal): $e');
  }

  try {
    await setupServiceLocator(
      adProvider: adProvider,
      downloadedVideoListProvider: downloadedVideoListProvider,
    );
    debugPrint('[main] Service locator setup complete');
  } catch (e) {
    debugPrint('[main] ⚠️ Service locator setup failed (non-fatal): $e');
  }

  // initialize media store (Android only)
  if (Platform.isAndroid) {
    try {
      MediaStore.appFolder = "DownVid"; // Creates /Download/DownVid
      await MediaStore.ensureInitialized();
      debugPrint('[main] MediaStore initialized');
    } catch (e) {
      debugPrint('[main] ⚠️ MediaStore init failed (non-fatal): $e');
    }
  }

  final homeAndDownloadProvider = HomeAndDownloadProvider();

  // Always remove the splash — guaranteed even if all inits above fail
  FlutterNativeSplash.remove();
  debugPrint('[main] Splash removed — starting app');

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
        ChangeNotifierProvider<AdProvider>.value(value: adProvider),
        ChangeNotifierProvider<HomeAndDownloadProvider>.value(value: homeAndDownloadProvider),
        ChangeNotifierProvider<DownloadedVideoListProvider>.value(value: downloadedVideoListProvider),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(
      context,
    ); // Listen to changes

    return Sizer(
      builder: (context, orientation, deviceType) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'DownVid',
          theme: ThemeData(
            useMaterial3: true,
            primaryColor: const Color(0xFF2563EB),
            scaffoldBackgroundColor: const Color(0xFFF8FAFC),
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF2563EB),
              primary: const Color(0xFF2563EB),
              secondary: const Color(0xFF3B82F6),
              background: const Color(0xFFF8FAFC),
              surface: Colors.white,
              brightness: Brightness.light,
            ),
            cardTheme: const CardThemeData(
              color: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(16)),
              ),
            ),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            primaryColor: const Color(0xFF3B82F6),
            scaffoldBackgroundColor: const Color(0xFF0F172A),
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color.fromARGB(255, 173, 192, 224),
              primary: const Color(0xFF3B82F6),
              secondary: const Color(0xFF60A5FA),
              background: const Color(0xFF0F172A),
              surface: const Color(0xFF1E293B),
              brightness: Brightness.dark,
            ),
            cardTheme: const CardThemeData(
              color: Color(0xFF1E293B),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(16)),
              ),
            ),
          ),
          themeMode: themeProvider.isDarkMode
              ? ThemeMode.dark
              : ThemeMode.light,
          initialRoute: "/home",
          routes: {
            '/home': (context) => const HomeScreen(),
            '/downloaded': (context) => const DownloadedListScreen(),
          },
        );
      },
    );
  }
}
