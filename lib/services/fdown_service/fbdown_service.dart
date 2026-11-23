// lib/services/fdown_service/fbdown_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io' show Directory, File;
import 'package:path_provider/path_provider.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sizer/sizer.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:downvid/models/video_meta_model/video_model.dart';
import 'package:downvid/models/video_downloaded_model/video_downloaded_model.dart';
import 'package:downvid/services/object_box/object_box_service.dart';
import 'package:downvid/service_locator.dart';

/// FbDownService
/// - Responsible for scraping fdown.net results via an embedded WebViewController
/// - After a successful scrape it will update HomeAndDownloadProvider and open the bottom sheet
class FbDownService {
  WebViewController? _controller;

  /// Completes when fdown.net HOMEPAGE has finished loading (Cloudflare passed).
  /// fetchVideoMetaData awaits this before submitting the form.
  Completer<void>? _webViewReady;

  /// Completes when fdown.net/download.php has FULLY loaded (page rendered).
  /// We reset this before submitting the form and await it before scraping results.
  Completer<void>? _downloadPageReady;

  /// Initialize a WebViewController with sensible settings
  Future<void> initWebView() async {
    // Reset both gates
    _webViewReady = Completer<void>();
    _downloadPageReady = null;

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(
          'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36')
      ..setBackgroundColor(const Color(0x00000000))
      ..enableZoom(true)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) => debugPrint('[WebView] START → $url'),
          onPageFinished: (url) {
            debugPrint('[WebView] FINISH → $url');

            // Gate 1: fdown.net homepage fully loaded → Cloudflare passed
            if (url.contains('fdown.net') &&
                !url.contains('download.php') &&
                _webViewReady != null &&
                !_webViewReady!.isCompleted) {
              debugPrint('[FbDownService] ✅ WebView ready — fdown.net loaded');
              _webViewReady!.complete();
            }

            // Gate 2: download.php fully loaded → safe to scrape results
            if (url.contains('download.php') &&
                _downloadPageReady != null &&
                !_downloadPageReady!.isCompleted) {
              debugPrint('[FbDownService] ✅ download.php fully loaded — scraping now');
              _downloadPageReady!.complete();
            }
          },
          onWebResourceError: (e) => debugPrint(
              '[WebView] ERROR: ${e.description} (code ${e.errorCode})'),
        ),
      );

    await _controller?.loadRequest(Uri.parse('https://fdown.net/'));
  }

  /// Suspends until the WebView has finished loading fdown.net (Cloudflare bypass
  /// complete). Times out after [timeoutSeconds].
  Future<void> _waitForWebViewReady({int timeoutSeconds = 30}) async {
    if (_webViewReady == null) {
      debugPrint('[FbDownService] ⚠️ _waitForWebViewReady: Completer is null — WebView not initialised yet');
      await Future.delayed(const Duration(seconds: 2));
      return;
    }
    if (_webViewReady!.isCompleted) return;

    debugPrint('[FbDownService] ⏳ Waiting up to ${timeoutSeconds}s for fdown.net to load...');
    try {
      await _webViewReady!.future.timeout(Duration(seconds: timeoutSeconds));
      debugPrint('[FbDownService] ✅ WebView ready — proceeding with fetch');
    } on TimeoutException {
      debugPrint('[FbDownService] ⚠️ WebView ready-wait timed out after ${timeoutSeconds}s — proceeding anyway');
    }
  }

  /// Suspends until download.php has FULLY loaded (onPageFinished fired).
  /// This prevents scraping a half-rendered results page.
  Future<void> _waitForDownloadPageReady({int timeoutSeconds = 15}) async {
    if (_downloadPageReady == null || _downloadPageReady!.isCompleted) return;
    debugPrint('[FbDownService] ⏳ Waiting up to ${timeoutSeconds}s for download.php to finish rendering...');
    try {
      await _downloadPageReady!.future.timeout(Duration(seconds: timeoutSeconds));
      debugPrint('[FbDownService] ✅ download.php rendered — scraping results');
    } on TimeoutException {
      debugPrint('[FbDownService] ⚠️ download.php render wait timed out — scraping anyway');
    }
  }

  Future<void> goHome() async {
    try {
      if (_controller == null) {
        debugPrint('FbDownService.goHome → Controller is null. Initializing WebView...');
        await initWebView();
        return;
      }

      _webViewReady = Completer<void>();
      _downloadPageReady = null;
      await _controller!.loadRequest(Uri.parse('https://fdown.net/'));
      debugPrint('FbDownService.goHome → Navigated to fdown.net homepage');
    } catch (e, st) {
      debugPrint('FbDownService.goHome ERROR → $e\n$st');
    }
  }

  Future<VideoMetaDataModel?> fetchVideoMetaData(
      String userUrl, BuildContext context) async {
    if (userUrl.isEmpty) return null;

    try {
      // Step 1: Wait for fdown.net homepage to finish loading (Cloudflare gate)
      await _waitForWebViewReady(timeoutSeconds: 30);

      // Step 2: Make sure we are on the homepage before looking for the form
      final currentUrl = await _controller?.currentUrl();
      if (currentUrl == null ||
          !currentUrl.contains('fdown.net') ||
          currentUrl.contains('download.php')) {
        await goHome();
        await _waitForWebViewReady(timeoutSeconds: 20);
      }

      // Step 3: Arm the download-page gate BEFORE submitting so we don't
      //         miss the onPageFinished event if download.php loads fast.
      _downloadPageReady = Completer<void>();

      // Step 4: Wait for the input form to appear
      await _waitForForm();
      // Allow scripts and handlers on fdown.net to settle before submitting
      await Future.delayed(const Duration(milliseconds: 600));

      // Step 5: Fill and submit the URL
      await _fillAndSubmit(userUrl);
      debugPrint('[FbDownService] 🚀 Form submitted for URL. Waiting for redirect to download.php...');

      // Step 6: Wait for fdown.net to navigate to download.php AND for that
      //         page to fully render before we attempt any scraping.
      //         Allow up to 45 seconds (90 attempts * 500ms) for slower Facebook reel responses.
      final resultPageUrl = await _waitForResultPage(maxAttempts: 90);

      if (resultPageUrl.contains('error=')) {
        debugPrint('[FbDownService] ❌ Result page returned error: $resultPageUrl');
        Fluttertoast.showToast(msg: 'This video is private or not supported.');
        return null;
      }

      // Step 7: Wait for download.php to FINISH rendering
      await _waitForDownloadPageReady(timeoutSeconds: 15);

      // Step 8: Scrape — page is guaranteed to be fully loaded now
      VideoMetaDataModel? meta = await _scrapeDownloadPage();

      // Step 9: If scrape on download.php still found nothing, do a few
      //         extra attempts in case of dynamic content injection
      if (meta == null || meta.videoLinks.isEmpty) {
        const extraAttempts = 5;
        const delayMs = 800;
        for (int i = 0; i < extraAttempts; i++) {
          await Future.delayed(const Duration(milliseconds: delayMs));
          meta = await _scrapeDownloadPage();
          if (meta != null && meta.videoLinks.isNotEmpty) break;
        }
      }

      if (meta == null || meta.videoLinks.isEmpty) {
        Fluttertoast.showToast(msg: 'No downloadable video found.');
        return null;
      }

      debugPrint('[FbDownService] ✅ Metadata fetched successfully for URL: $userUrl');

      // Clear WebView to free memory
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          await _controller?.loadRequest(Uri.parse('about:blank'));
          debugPrint('[FbDownService] 🧹 WebView cleared to free memory.');
        } catch (e, st) {
          debugPrint('[FbDownService] ⚠️ Failed to clear WebView: $e\n$st');
        }
      });

      return meta;
    } catch (e, st) {
      debugPrint('FbDownService error: $e\n$st');
      Fluttertoast.showToast(msg: 'Failed to process URL');
      return null;
    }
  }

  Future<void> _waitForForm({int maxAttempts = 40}) async {
    for (int i = 0; i < maxAttempts; i++) {
      final ok = await _controller!.runJavaScriptReturningResult('''
        (function(){
          return !!document.querySelector('input[name="URLz"]') &&
                 !!document.querySelector('.btn.btn-primary.input-lg');
        })();
      ''');
      if (ok == true) return;
      await Future.delayed(const Duration(milliseconds: 400));
    }
    throw Exception('Form not found on fdown.net');
  }

  Future<void> _fillAndSubmit(String url) async {
    final js = '''
      (function(){
        try {
          const inp = document.querySelector('input[name="URLz"]');
          const btn = document.querySelector('.btn.btn-primary.input-lg') ||
                      document.querySelector('button[type="submit"]') ||
                      document.querySelector('input[type="submit"]');
          if (!inp) return JSON.stringify({status: 'no_input'});
          if (!btn) return JSON.stringify({status: 'no_btn'});

          inp.value = decodeURIComponent("${Uri.encodeComponent(url)}");
          inp.dispatchEvent(new Event('input', { bubbles: true }));
          inp.dispatchEvent(new Event('change', { bubbles: true }));

          btn.click();

          return JSON.stringify({
            status: 'ok',
            btnFound: true,
            valLength: inp.value.length
          });
        } catch(err) {
          return JSON.stringify({status: 'error', error: err.toString()});
        }
      })();
    ''';
    final result = await _controller!.runJavaScriptReturningResult(js);
    debugPrint('[FbDownService] 📝 Form submit result: $result');
  }

  Future<String> _waitForResultPage({int maxAttempts = 90}) async {
    for (int i = 0; i < maxAttempts; i++) {
      final url = (await _controller!.currentUrl()) ?? '';
      if (url.contains('download.php') || url.contains('error=')) {
        debugPrint('[FbDownService] 🔗 Navigated to result page: $url (attempt ${i + 1}/$maxAttempts)');
        return url;
      }

      if ((i + 1) % 10 == 0) {
        debugPrint('[FbDownService] ⏳ Waiting for result page... (${(i + 1) * 500 / 1000}s elapsed, current: $url)');
      }
      await Future.delayed(const Duration(milliseconds: 500));
    }
    throw Exception('Did not reach download.php or error page within timeout');
  }

  Future<VideoMetaDataModel?> _scrapeDownloadPage() async {
    try {
      final raw = await _controller!.runJavaScriptReturningResult('''
        (function(){
          const title = document.querySelector('meta[property="og:title"]')?.content ||
                        document.querySelector('title')?.innerText || 'Untitled Video';

          let thumb = document.querySelector('meta[property="og:image"]')?.content || '';
          if (!thumb) {
            const img = document.querySelector('img.lib-img-show');
            if (img && img.src) thumb = img.src;
          }

          let duration = '';
          const descEls = document.querySelectorAll('.lib-row.lib-desc');
          for (const el of descEls) {
            const txt = el.textContent.trim();
            if (/Duration/i.test(txt)) {
              duration = txt.replace(/.*Duration[:\\s]*/i, '').trim();
              break;
            }
          }

          const links = [];
          const anchors = document.querySelectorAll('a');
          for (let a of anchors) {
            const txt = (a.textContent || '').toLowerCase();
            const href = a.href || '';
            if (txt.includes('download') && href.includes('.mp4')) {
              const quality = txt.includes('hd') ? 'HD' : 'SD';
              links.push({href, quality});
            }
          }

          return JSON.stringify({title, thumb, duration, links});
        })();
      ''');

      String jsonString = raw.toString();
      if (jsonString.startsWith('"') && jsonString.endsWith('"')) {
        jsonString = jsonString.substring(1, jsonString.length - 1);
      }
      jsonString = jsonString.replaceAll(r'\"', '"').replaceAll(r'\\', r'\');

      final Map<String, dynamic> data = jsonDecode(jsonString);
      final List<dynamic> linkList = data['links'] ?? [];

      final videoLinks = linkList
          .map((e) => VideoLinkModel(
                link: (e['href'] ?? '') as String,
                quality: (e['quality'] ?? 'SD') as String,
                type: 'mp4',
              ))
          .where((link) => link.link.isNotEmpty)
          .toList();

      return VideoMetaDataModel(
        title: data['title'] ?? 'Untitled Video',
        description: '',
        duration: data['duration'] ?? 'Unknown',
        thumbnail: data['thumb'] ?? '',
        videoLinks: videoLinks,
        hasScrappingError: videoLinks.isEmpty,
      );
    } catch (e, st) {
      debugPrint('❌ Error scraping download page: $e\n$st');
      return null;
    }
  }

  Future<void> downloadVideo({
    required VideoMetaDataModel meta,
    required int selectedLinkIndex,
    required String userUrl,
    required Function(double) onProgress,
    required Function(String) onComplete,
    required Function(String) onError,
  }) async {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(minutes: 30),
      sendTimeout: const Duration(seconds: 30),
      followRedirects: true,
      maxRedirects: 10,
      persistentConnection: true,
      receiveDataWhenStatusError: true,
    ));

    try {
      final link = meta.videoLinks[selectedLinkIndex];
      final safeTitle = (meta.title ?? "Video")
          .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')
          .trim();
      final fileName = '${safeTitle}_${DateTime.now().millisecondsSinceEpoch}.mp4';

      int? androidSdkVersion;
      if (defaultTargetPlatform == TargetPlatform.android) {
        try {
          final deviceInfo = DeviceInfoPlugin();
          final androidInfo = await deviceInfo.androidInfo;
          androidSdkVersion = androidInfo.version.sdkInt;
        } catch (e) {
          debugPrint('Error getting Android version: $e');
          androidSdkVersion = 0;
        }
      }

      const android13SdkVersion = 33;
      if (androidSdkVersion != null && androidSdkVersion >= android13SdkVersion) {
        if (await Permission.videos.isDenied) {
          final status = await Permission.videos.request();
          if (!status.isGranted) {
            Fluttertoast.showToast(
              msg: "Video permission required",
              backgroundColor: Colors.red.shade700,
            );
            onError("Permission denied");
            return;
          }
        }
      } else {
        if (await Permission.storage.isDenied) {
          final status = await Permission.storage.request();
          if (!status.isGranted) {
            Fluttertoast.showToast(
              msg: "Storage permission required",
              backgroundColor: Colors.red.shade700,
            );
            onError("Permission denied");
            return;
          }
        }
      }

      final baseDir = await getExternalStorageDirectory();
      final dir = baseDir != null ? Directory('${baseDir.path}/DownVid') : Directory('/storage/emulated/0/Download/DownVid');
      if (!await dir.exists()) await dir.create(recursive: true);
      final filePath = '${dir.path}/$fileName';
      debugPrint("Downloading to: $filePath");

      DateTime? lastUpdateTime;
      double lastReportedProgress = 0.0;

      await dio.download(
        link.link,
        filePath,
        onReceiveProgress: (received, total) {
          if (total <= 0) return;
          final double progress = received / total;
          final DateTime now = DateTime.now();
          final bool progressChangedEnough = (progress - lastReportedProgress).abs() >= 0.01;
          final bool timePassed = lastUpdateTime == null ||
              now.difference(lastUpdateTime!).inMilliseconds >= 500;
          if (progressChangedEnough || timePassed) {
            onProgress(progress);
            lastReportedProgress = progress;
            lastUpdateTime = now;
          }
        },
        options: Options(
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Linux; Android 14; Pixel 9 Pro Build/AP2A.241205.001; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/131.0.6738.108 Mobile Safari/537.36',
            'Referer': 'https://fdown.net/',
            'Origin': 'https://fdown.net',
            'Accept': '*/*',
            'Connection': 'keep-alive',
          },
        ),
      );

      final file = File(filePath);
      if (!await file.exists()) {
        onError("File not saved");
        return;
      }

      final sizeMB = (await file.length()) / (1024 * 1024);

      getIt<ObjectBox>().store.box<VideoDownloadedModel>().put(VideoDownloadedModel(
        title: meta.title ?? "Untitled Video",
        thumbnail: meta.thumbnail ?? "",
        videoSocialUrl: link.link,
        videoPath: filePath,
        videoType: "mp4",
        videoQuality: link.quality,
        videoFileSize: "${sizeMB.toStringAsFixed(2)} MB",
        videoDuration: meta.duration ?? "Unknown",
        videoDownloadedDate: DateTime.now(),
        originalUrl: userUrl,
      ));

      Fluttertoast.showToast(
        msg: "Saved → Downloads",
        toastLength: Toast.LENGTH_LONG,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.green.shade600,
        textColor: Colors.white,
        fontSize: 16.0,
      );

      onComplete(filePath);
    } catch (e, st) {
      debugPrint("Download error: $e\n$st");
      Fluttertoast.showToast(msg: "Download failed");
      onError(e.toString());
    }
  }

    // WebView widget accessor
    /// Returns the raw [WebViewWidget] for mounting in the UI.
  /// The caller is responsible for hiding it (use Stack+Positioned off-screen,
  /// NOT Offstage — Offstage suspends Android WebView JS execution).
  Widget? get webViewWidget {
    if (_controller == null) return null;
    return WebViewWidget(controller: _controller!);
  }
}
