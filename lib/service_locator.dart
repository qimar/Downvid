// lib/service_locator.dart
import 'package:flutter/foundation.dart';
import 'package:downvid/providers/ad_provider/ads_provider.dart';
import 'package:downvid/providers/downloaded_video_list_provider/downloaded_video_list_provider.dart';
import 'package:downvid/services/fdown_service/fbdown_service.dart';
import 'package:downvid/services/object_box/object_box_service.dart';
import 'package:get_it/get_it.dart';

final getIt = GetIt.instance;

Future<void> setupServiceLocator({
  required AdProvider adProvider,
  required DownloadedVideoListProvider downloadedVideoListProvider,
}) async {
  // 1. Register ObjectBox with a retry loop (async channel might fail in release)
  //    FbDownService is registered regardless — it does NOT depend on ObjectBox.
  ObjectBox? objectBox;
  int retries = 5;
  while (retries > 0) {
    try {
      objectBox = await ObjectBox.create();
      if (!getIt.isRegistered<ObjectBox>()) {
        getIt.registerSingleton<ObjectBox>(objectBox);
      }
      break;
    } catch (e) {
      retries--;
      if (retries == 0) {
        // Fail gracefully — ObjectBox unavailable, but app can still run without history
        debugPrint('[ServiceLocator] ObjectBox failed after all retries: ');
        break;
      }
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  // 2. Register FbDownService unconditionally — it does NOT need ObjectBox
  if (!getIt.isRegistered<FbDownService>()) {
    getIt.registerLazySingleton<FbDownService>(() => FbDownService());
  }

  // 3. Register pre-created Providers
  getIt.registerSingleton<DownloadedVideoListProvider>(downloadedVideoListProvider);
  getIt.registerSingleton<AdProvider>(adProvider);

  // Load once at startup
  try {
    getIt<DownloadedVideoListProvider>().loadDownloadedVideos();
  } catch (e) {
    print('Failed to load downloaded videos: $e');
  }

  print('Service Locator: ALL REGISTERED SUCCESSFULLY');
}