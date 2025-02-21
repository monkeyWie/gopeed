import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:install_plugin/install_plugin.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/api.dart';
import '../app/views/outlined_button_loading.dart';
import 'log_util.dart';
import 'message.dart';
import 'package_info.dart';
import 'util.dart';

enum Channel {
  windows,
  macos,
  linuxFlathub,
  linuxSnap,
  linuxDeb,
  linuxAppImage,
  androidApk,
  iosIpa,
  docker,
}

const _channelEnv = String.fromEnvironment("UPDATE_CHANNEL");
final _channel =
    Channel.values.where((e) => e.name == _channelEnv).firstOrNull ??
        () {
          if (Util.isWindows()) {
            return Channel.windows;
          } else if (Util.isMacos()) {
            return Channel.macos;
          } else if (Util.isAndroid()) {
            return Channel.androidApk;
          } else if (Util.isIOS()) {
            return Channel.iosIpa;
          } else {
            return null;
          }
        }();
final _updaterBin = Util.isWindows() ? "updater.exe" : "updater";

Future<void> installUpdater() async {
  await Util.installAsset(
      'assets/exec/$_updaterBin', Util.homePathJoin(_updaterBin),
      executable: true);
}

class VersionInfo {
  final String version;
  final String changeLog;

  VersionInfo(this.version, this.changeLog);
}

Future<VersionInfo?> checkUpdate() async {
  String? releaseDataStr;
  try {
    releaseDataStr = (await proxyRequest(
            "https://api.github.com/repos/GopeedLab/gopeed/releases/latest"))
        .data;
  } catch (e) {
    releaseDataStr =
        (await proxyRequest("https://gopeed.com/api/release")).data;
  }
  if (releaseDataStr == null) {
    return null;
  }
  final releaseData = jsonDecode(releaseDataStr);
  final tagName = releaseData["tag_name"];
  if (tagName == null) {
    return null;
  }
  final latestVersion = releaseData["tag_name"].substring(1);

  // compare version x.y.z to x.y.z
  final currentVersion = packageInfo.version;
  var isNewVersion = false;
  if (latestVersion != currentVersion) {
    final currentVersionList = currentVersion.split(".");
    final latestVersionList = latestVersion.split(".");
    for (var i = 0; i < currentVersionList.length; i++) {
      if (int.parse(latestVersionList[i]) > int.parse(currentVersionList[i])) {
        isNewVersion = true;
        break;
      }
    }
  }

  if (!isNewVersion) {
    return null;
  }

  return VersionInfo(latestVersion, releaseData["body"]);
}

Future<void> showUpdateDialog(
    BuildContext context, VersionInfo versionInfo) async {
  final fullChangeLog = versionInfo.changeLog;
  final isZh = Get.locale?.languageCode == "zh";
  final changeLogRegex = isZh
      ? RegExp(r"(#\s+更新日志.*)", multiLine: true, dotAll: true)
      : RegExp(r"(# Release notes.*)#\s+更新日志", multiLine: true, dotAll: true);
  final changeLog = changeLogRegex.firstMatch(fullChangeLog)?.group(1) ?? "";
  await showDialog(
    context: Get.context!,
    barrierDismissible: false,
    builder: (context) {
      bool isDownloading = false;
      double progress = 0;
      int total = 0;
      final buttonController = OutlinedButtonLoadingController();
      return StatefulBuilder(
        builder: (context, setState) {
          final screenSize = MediaQuery.of(context).size;
          final dialogWidth =
              screenSize.width < 500 ? screenSize.width * 0.9 : 500.0;
          final dialogHeight =
              screenSize.height < 600 ? screenSize.height * 0.8 : 400.0;

          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: SizedBox(
              width: dialogWidth,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'newVersionTitle'
                          .trParams({'version': versionInfo.version}),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      height: dialogHeight * 0.5,
                      decoration: BoxDecoration(
                        border:
                            Border.all(color: Theme.of(context).dividerColor),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ScrollConfiguration(
                        behavior: ScrollConfiguration.of(context).copyWith(
                          scrollbars: true,
                        ),
                        child: Builder(
                          builder: (context) {
                            final controller = ScrollController();
                            return Scrollbar(
                              controller: controller,
                              thumbVisibility: true,
                              child: SingleChildScrollView(
                                controller: controller,
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children:
                                        _parseMarkdown(changeLog, context),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    if (isDownloading) ...[
                      const SizedBox(height: 16),
                      LinearProgressIndicator(
                        value: progress,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${(progress * 100).toStringAsFixed(1)}%',
                            style: const TextStyle(fontSize: 12),
                          ),
                          Text(
                            total == 0
                                ? ''
                                : '${Util.fmtByte((total * progress).toInt())} / ${Util.fmtByte(total)}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      )
                    ],
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: isDownloading ? null : () => Get.back(),
                          child: Text(
                            'newVersionLater'.tr,
                            style: TextStyle(
                                color: isDownloading
                                    ? Theme.of(context).disabledColor
                                    : Theme.of(context).colorScheme.error),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButtonLoading(
                          controller: buttonController,
                          onPressed: () async {
                            setState(() {
                              isDownloading = true;
                            });
                            buttonController.start();
                            try {
                              await _update(versionInfo.version,
                                  (received, fileTotal) {
                                setState(() {
                                  total = fileTotal;
                                  progress = received / fileTotal;
                                });
                              });
                            } catch (e) {
                              showErrorMessage(e);
                            } finally {
                              setState(() {
                                isDownloading = false;
                              });
                              buttonController.stop();
                            }
                          },
                          child: Text('newVersionUpdate'.tr),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
}

List<Widget> _parseMarkdown(String markdown, BuildContext context) {
  final List<Widget> widgets = [];
  final lines = markdown.split('\n');

  for (final line in lines) {
    if (line.trim().isEmpty) continue;
    if (line.startsWith('# ')) {
      // H1 header
      widgets.add(Text(
        line.substring(2),
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ));
    } else if (line.startsWith('## ')) {
      // H2 header
      widgets.add(Text(
        line.substring(3),
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ));
    } else if (line.trim().startsWith('- ')) {
      // List item
      widgets.add(Padding(
        padding: const EdgeInsets.only(left: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('• ', style: TextStyle(fontSize: 14)),
            Expanded(
              child: Text(
                line.substring(line.indexOf('-') + 1).trim().replaceFirst(
                    RegExp(r'@[^\s]*\s\(#\d+\)'),
                    ''), // Remove contributor and pr number
                style: const TextStyle(fontSize: 14),
              ),
            ),
          ],
        ),
      ));
    } else {
      // Normal text
      widgets.add(Text(
        line,
        style: const TextStyle(fontSize: 14),
      ));
    }

    // Add spacing between elements
    widgets.add(const SizedBox(height: 8));
  }

  return widgets;
}

Future<void> _update(String version, Function(int, int) onProgress) async {
  final downloadUrl =
      'https://github.com/GopeedLab/gopeed/releases/download/v$version/${_getAssetName(version)}';
  final newVersionAssetPath = await _getAssetPath(version);

  if (downloadUrl.isNotEmpty) {
    final downloadClient = Dio();
    await downloadClient.download(downloadUrl, newVersionAssetPath,
        onReceiveProgress: onProgress);
  }

  switch (_channel) {
    case Channel.windows:
    case Channel.macos:
    case Channel.linuxDeb:
      // updater <pid> <asset> [log]
      await Process.start(Util.homePathJoin(_updaterBin), [
        pid.toString(),
        newVersionAssetPath,
        path.join(logsDir(), "updater.log")
      ]);
      break;
    case Channel.androidApk:
      await InstallPlugin.installApk(newVersionAssetPath);
      break;
    default:
      await launchUrl(
          Uri.parse(
              'https://github.com/GopeedLab/gopeed/releases/tag/v$version'),
          mode: LaunchMode.externalApplication);
      break;
  }
}

String _getAssetName(String version) {
  switch (_channel) {
    case Channel.windows:
      return 'Gopeed-v$version-windows-amd64-portable.zip';
    case Channel.macos:
      return 'Gopeed-v$version-macos.dmg';
    case Channel.linuxDeb:
      return 'Gopeed-v$version-linux-amd64.deb';
    case Channel.androidApk:
      return 'Gopeed-v$version-android.apk';
    default:
      return "";
  }
}

Future<String> _getAssetPath(String version) async {
  return path.join(
      (await getTemporaryDirectory()).path, _getAssetName(version));
}
