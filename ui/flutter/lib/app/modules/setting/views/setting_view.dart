import 'dart:async';
import 'dart:io';

import 'package:badges/badges.dart' as badges;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:gopeed/app/views/copy_button.dart';
import 'package:intl/intl.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../api/model/downloader_config.dart';
import '../../../../i18n/message.dart';
import '../../../../util/input_formatter.dart';
import '../../../../util/locale_manager.dart';
import '../../../../util/log_util.dart';
import '../../../../util/message.dart';
import '../../../../util/package_info.dart';
import '../../../../util/scheme_register/scheme_register.dart';
import '../../../../util/updater.dart';
import '../../../../util/util.dart';
import '../../../views/check_list_view.dart';
import '../../../views/directory_selector.dart';
import '../../../views/open_in_new.dart';
import '../../../views/outlined_button_loading.dart';
import '../../app/controllers/app_controller.dart';
import '../controllers/setting_controller.dart';

const _padding = SizedBox(height: 10);
final _divider = const Divider().paddingOnly(left: 10, right: 10);

class SettingView extends GetView<SettingController> {
  const SettingView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final appController = Get.find<AppController>();
    final downloaderCfg = appController.downloaderConfig;
    final startCfg = appController.startConfig;

    Timer? timer;
    Future<bool> debounceSave(
        {Future<String> Function()? check, bool needRestart = false}) {
      var completer = Completer<bool>();
      timer?.cancel();
      timer = Timer(const Duration(milliseconds: 1000), () async {
        if (check != null) {
          final checkResult = await check();
          if (checkResult.isNotEmpty) {
            showErrorMessage(checkResult);
            completer.complete(false);
            return;
          }
        }
        appController
            .saveConfig()
            .then((_) => completer.complete(true))
            .onError(completer.completeError);
        if (needRestart) {
          showMessage('tip'.tr, 'effectAfterRestart'.tr);
        }
      });
      return completer.future;
    }

    // download basic config items start
    final buildDownloadDir = _buildConfigItem(
        'downloadDir', () => downloaderCfg.value.downloadDir, (Key key) {
      final downloadDirController =
          TextEditingController(text: downloaderCfg.value.downloadDir);
      downloadDirController.addListener(() async {
        if (downloadDirController.text != downloaderCfg.value.downloadDir) {
          downloaderCfg.value.downloadDir = downloadDirController.text;
          if (Util.isDesktop()) {
            controller.clearTap();
          }

          await debounceSave();
        }
      });
      return DirectorySelector(
        controller: downloadDirController,
        showLabel: false,
        showAndoirdToggle: true,
      );
    });
    final buildMaxRunning = _buildConfigItem(
        'maxRunning', () => downloaderCfg.value.maxRunning.toString(),
        (Key key) {
      final maxRunningController = TextEditingController(
          text: downloaderCfg.value.maxRunning.toString());
      maxRunningController.addListener(() async {
        if (maxRunningController.text.isNotEmpty &&
            maxRunningController.text !=
                downloaderCfg.value.maxRunning.toString()) {
          downloaderCfg.value.maxRunning = int.parse(maxRunningController.text);

          await debounceSave();
        }
      });

      return TextField(
        key: key,
        focusNode: FocusNode(),
        controller: maxRunningController,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          NumericalRangeFormatter(min: 1, max: 256),
        ],
      );
    });

    final buildDefaultDirectDownload =
        _buildConfigItem('defaultDirectDownload', () {
      return appController.downloaderConfig.value.extra.defaultDirectDownload
          ? 'on'.tr
          : 'off'.tr;
    }, (Key key) {
      return Container(
        alignment: Alignment.centerLeft,
        child: Switch(
          value:
              appController.downloaderConfig.value.extra.defaultDirectDownload,
          onChanged: (bool value) async {
            appController.downloaderConfig.update((val) {
              val!.extra.defaultDirectDownload = value;
            });
            await debounceSave();
          },
        ),
      );
    });

    buildBrowserExtension() {
      return ListTile(
          title: Text('browserExtension'.tr),
          subtitle: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              OpenInNew(
                text: "Chrome",
                url:
                    "https://chromewebstore.google.com/detail/gopeed/mijpgljlfcapndmchhjffkpckknofcnd",
              ),
              SizedBox(width: 10),
              OpenInNew(
                text: "Edge",
                url:
                    "https://microsoftedge.microsoft.com/addons/detail/dkajnckekendchdleoaenoophcobooce",
              ),
              SizedBox(width: 10),
              OpenInNew(
                text: "Firefox",
                url:
                    "https://addons.mozilla.org/zh-CN/firefox/addon/gopeed-extension",
              ),
            ],
          ).paddingOnly(top: 5));
    }

    // Currently auto startup only support Windows and Linux
    final buildAutoStartup = !Util.isWindows() && !Util.isLinux()
        ? () => null
        : _buildConfigItem('launchAtStartup', () {
            return appController.autoStartup.value ? 'on'.tr : 'off'.tr;
          }, (Key key) {
            return Container(
              alignment: Alignment.centerLeft,
              child: Switch(
                value: appController.autoStartup.value,
                onChanged: (bool value) async {
                  try {
                    if (value) {
                      await launchAtStartup.enable();
                    } else {
                      await launchAtStartup.disable();
                    }
                    appController.autoStartup.value = value;
                  } catch (e) {
                    showErrorMessage(e);
                    logger.e('launchAtStartup fail', e);
                  }
                },
              ),
            );
          });

    // http config items start
    final httpConfig = downloaderCfg.value.protocolConfig.http;
    final buildHttpUa =
        _buildConfigItem('User-Agent', () => httpConfig.userAgent, (Key key) {
      final uaController = TextEditingController(text: httpConfig.userAgent);
      uaController.addListener(() async {
        if (uaController.text.isNotEmpty &&
            uaController.text != httpConfig.userAgent) {
          httpConfig.userAgent = uaController.text;

          await debounceSave();
        }
      });

      return TextField(
        key: key,
        focusNode: FocusNode(),
        controller: uaController,
      );
    });
    final buildHttpConnections = _buildConfigItem(
        'connections', () => httpConfig.connections.toString(), (Key key) {
      final connectionsController =
          TextEditingController(text: httpConfig.connections.toString());
      connectionsController.addListener(() async {
        if (connectionsController.text.isNotEmpty &&
            connectionsController.text != httpConfig.connections.toString()) {
          httpConfig.connections = int.parse(connectionsController.text);

          await debounceSave();
        }
      });

      return TextField(
        key: key,
        focusNode: FocusNode(),
        controller: connectionsController,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          NumericalRangeFormatter(min: 1, max: 256),
        ],
      );
    });
    final buildHttpUseServerCtime = _buildConfigItem(
        'useServerCtime', () => httpConfig.useServerCtime ? 'on'.tr : 'off'.tr,
        (Key key) {
      return Container(
        alignment: Alignment.centerLeft,
        child: Switch(
          value: httpConfig.useServerCtime,
          onChanged: (bool value) {
            downloaderCfg.update((val) {
              val!.protocolConfig.http.useServerCtime = value;
            });
            debounceSave();
          },
        ),
      );
    });

    // bt config items start
    final btConfig = downloaderCfg.value.protocolConfig.bt;
    final btExtConfig = downloaderCfg.value.extra.bt;
    final buildBtListenPort = _buildConfigItem(
        'port', () => btConfig.listenPort.toString(), (Key key) {
      final listenPortController =
          TextEditingController(text: btConfig.listenPort.toString());
      listenPortController.addListener(() async {
        if (listenPortController.text.isNotEmpty &&
            listenPortController.text != btConfig.listenPort.toString()) {
          btConfig.listenPort = int.parse(listenPortController.text);

          await debounceSave();
        }
      });

      return TextField(
        key: key,
        focusNode: FocusNode(),
        controller: listenPortController,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          NumericalRangeFormatter(min: 0, max: 65535),
        ],
      );
    });
    final buildBtTrackerSubscribeUrls = _buildConfigItem(
        'subscribeTracker',
        () => 'items'.trParams(
            {'count': btExtConfig.trackerSubscribeUrls.length.toString()}),
        (Key key) {
      final trackerUpdateController = OutlinedButtonLoadingController();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 200,
            child: CheckListView(
              items: allTrackerSubscribeUrls,
              checked: btExtConfig.trackerSubscribeUrls,
              onChanged: (value) {
                btExtConfig.trackerSubscribeUrls = value;

                debounceSave();
              },
            ),
          ),
          _padding,
          Row(
            children: [
              OutlinedButtonLoading(
                onPressed: () async {
                  trackerUpdateController.start();
                  try {
                    await appController.trackerUpdate();
                  } catch (e) {
                    showErrorMessage('subscribeFail'.tr);
                  } finally {
                    trackerUpdateController.stop();
                  }
                },
                controller: trackerUpdateController,
                child: Text('update'.tr),
              ),
              Expanded(
                child: SwitchListTile(
                    controlAffinity: ListTileControlAffinity.leading,
                    value: btExtConfig.autoUpdateTrackers,
                    onChanged: (bool value) {
                      downloaderCfg.update((val) {
                        val!.extra.bt.autoUpdateTrackers = value;
                      });
                      debounceSave();
                    },
                    title: Text('updateDaily'.tr)),
              ),
            ],
          ),
          Text('lastUpdate'.trParams({
            'time': btExtConfig.lastTrackerUpdateTime != null
                ? DateFormat('yyyy-MM-dd HH:mm:ss')
                    .format(btExtConfig.lastTrackerUpdateTime!)
                : ''
          })),
        ],
      );
    });
    final buildBtTrackers = _buildConfigItem(
        'addTracker',
        () => 'items'
            .trParams({'count': btExtConfig.customTrackers.length.toString()}),
        (Key key) {
      final trackersController = TextEditingController(
          text: btExtConfig.customTrackers.join('\r\n').toString());
      return TextField(
        key: key,
        focusNode: FocusNode(),
        controller: trackersController,
        keyboardType: TextInputType.multiline,
        maxLines: 5,
        decoration: InputDecoration(
          hintText: 'addTrackerHit'.tr,
        ),
        onChanged: (value) async {
          btExtConfig.customTrackers = Util.textToLines(value);
          appController.refreshTrackers();

          await debounceSave();
        },
      );
    });
    final buildBtSeedConfig = _buildConfigItem('seedConfig',
        () => '${'seedKeep'.tr}(${btConfig.seedKeep ? 'on'.tr : 'off'.tr})',
        (Key key) {
      final seedRatioController =
          TextEditingController(text: btConfig.seedRatio.toString());
      seedRatioController.addListener(() {
        if (seedRatioController.text.isNotEmpty) {
          btConfig.seedRatio = double.parse(seedRatioController.text);
          debounceSave();
        }
      });
      final seedTimeController =
          TextEditingController(text: (btConfig.seedTime ~/ 60).toString());
      seedTimeController.addListener(() {
        if (seedTimeController.text.isNotEmpty) {
          btConfig.seedTime = int.parse(seedTimeController.text) * 60;
          debounceSave();
        }
      });
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              value: btConfig.seedKeep,
              onChanged: (bool value) {
                downloaderCfg.update((val) {
                  val!.protocolConfig.bt.seedKeep = value;
                });
                debounceSave();
              },
              title: Text('seedKeep'.tr)),
          btConfig.seedKeep
              ? null
              : TextField(
                  controller: seedRatioController,
                  decoration: InputDecoration(
                    labelText: 'seedRatio'.tr,
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                        RegExp(r'^\d+\.?\d{0,2}')),
                  ],
                ),
          btConfig.seedKeep
              ? null
              : TextField(
                  controller: seedTimeController,
                  decoration: InputDecoration(
                    labelText: 'seedTime'.tr,
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    NumericalRangeFormatter(min: 0, max: 100000000),
                  ],
                ),
        ].where((e) => e != null).map((e) => e!).toList(),
      );
    });
    final buildBtDefaultClientConfig = !Util.isWindows()
        ? () => null
        : _buildConfigItem('setAsDefaultBtClient', () {
            return appController.downloaderConfig.value.extra.defaultBtClient
                ? 'on'.tr
                : 'off'.tr;
          }, (Key key) {
            return Container(
              alignment: Alignment.centerLeft,
              child: Switch(
                value:
                    appController.downloaderConfig.value.extra.defaultBtClient,
                onChanged: (bool value) async {
                  try {
                    if (value) {
                      registerDefaultTorrentClient();
                    } else {
                      unregisterDefaultTorrentClient();
                    }
                    appController.downloaderConfig.update((val) {
                      val!.extra.defaultBtClient = value;
                    });
                    await debounceSave();
                  } catch (e) {
                    showErrorMessage(e);
                    logger.e('register default torrent client fail', e);
                  }
                },
              ),
            );
          });

    // ui config items start
    final buildTheme = _buildConfigItem(
        'theme',
        () => _getThemeName(downloaderCfg.value.extra.themeMode),
        (Key key) => DropdownButton<String>(
              key: key,
              value: downloaderCfg.value.extra.themeMode,
              onChanged: (value) async {
                downloaderCfg.update((val) {
                  val?.extra.themeMode = value!;
                });
                Get.changeThemeMode(ThemeMode.values.byName(value!));
                controller.clearTap();

                await debounceSave();
              },
              items: ThemeMode.values
                  .map((e) => DropdownMenuItem<String>(
                        value: e.name,
                        child: Text(_getThemeName(e.name)),
                      ))
                  .toList(),
            ));
    final buildLocale = _buildConfigItem(
        'locale',
        () => messages.keys[downloaderCfg.value.extra.locale]!['label']!,
        (Key key) => DropdownButton<String>(
              key: key,
              value: downloaderCfg.value.extra.locale,
              isDense: true,
              onChanged: (value) async {
                downloaderCfg.update((val) {
                  val!.extra.locale = value!;
                });
                Get.updateLocale(toLocale(value!));
                controller.clearTap();

                await debounceSave();
              },
              items: messages.keys.keys
                  .map((e) => DropdownMenuItem<String>(
                        value: e,
                        child: Text(messages.keys[e]!['label']!),
                      ))
                  .toList(),
            ));

    // about config items start
    buildHomepage() {
      const homePage = 'https://gopeed.com';
      return ListTile(
        title: Text('homepage'.tr),
        subtitle: const Text(homePage),
        onTap: () {
          launchUrl(Uri.parse(homePage), mode: LaunchMode.externalApplication);
        },
      );
    }

    buildVersion() {
      var hasNewVersion = controller.latestVersion.value != null;
      return ListTile(
        title: hasNewVersion
            ? badges.Badge(
                position: badges.BadgePosition.topStart(start: 36),
                child: Text('version'.tr))
            : Text('version'.tr),
        subtitle: Text(packageInfo.version),
        onTap: () {
          if (hasNewVersion) {
            showUpdateDialog(context, controller.latestVersion.value!);
          }
        },
      );
    }

    buildThanks() {
      const thankPage =
          'https://github.com/GopeedLab/gopeed/graphs/contributors';
      return ListTile(
        title: Text('thanks'.tr),
        subtitle: Text('thanksDesc'.tr),
        onTap: () {
          launchUrl(Uri.parse(thankPage), mode: LaunchMode.externalApplication);
        },
      );
    }

    // advanced config proxy items start
    final proxy = downloaderCfg.value.proxy;
    final buildProxy = _buildConfigItem(
      'proxy',
      () {
        switch (proxy.proxyMode) {
          case ProxyModeEnum.noProxy:
            return 'noProxy'.tr;
          case ProxyModeEnum.systemProxy:
            return 'systemProxy'.tr;
          case ProxyModeEnum.customProxy:
            return '${downloaderCfg.value.proxy.scheme}://${downloaderCfg.value.proxy.host}';
        }
      },
      (Key key) {
        final mode = SizedBox(
          width: 150,
          child: DropdownButtonFormField<ProxyModeEnum>(
            value: proxy.proxyMode,
            onChanged: (value) async {
              if (value != null && value != proxy.proxyMode) {
                proxy.proxyMode = value;
                downloaderCfg.update((val) {
                  val!.proxy = proxy;
                });

                await debounceSave();
              }
            },
            items: [
              DropdownMenuItem<ProxyModeEnum>(
                value: ProxyModeEnum.noProxy,
                child: Text('noProxy'.tr),
              ),
              DropdownMenuItem<ProxyModeEnum>(
                value: ProxyModeEnum.systemProxy,
                child: Text('systemProxy'.tr),
              ),
              DropdownMenuItem<ProxyModeEnum>(
                value: ProxyModeEnum.customProxy,
                child: Text('customProxy'.tr),
              ),
            ],
          ),
        );

        final scheme = SizedBox(
          width: 150,
          child: DropdownButtonFormField<String>(
            value: proxy.scheme,
            onChanged: (value) async {
              if (value != null && value != proxy.scheme) {
                proxy.scheme = value;

                await debounceSave();
              }
            },
            items: const [
              DropdownMenuItem<String>(
                value: 'http',
                child: Text('HTTP'),
              ),
              DropdownMenuItem<String>(
                value: 'https',
                child: Text('HTTPS'),
              ),
              DropdownMenuItem<String>(
                value: 'socks5',
                child: Text('SOCKS5'),
              ),
            ],
          ),
        );

        final arr = proxy.host.split(':');
        var host = '';
        var port = '';
        if (arr.length > 1) {
          host = arr[0];
          port = arr[1];
        }

        final ipController = TextEditingController(text: host);
        final portController = TextEditingController(text: port);
        updateAddress() async {
          final newAddress = '${ipController.text}:${portController.text}';
          if (newAddress != startCfg.value.address) {
            proxy.host = newAddress;

            await debounceSave();
          }
        }

        ipController.addListener(updateAddress);
        portController.addListener(updateAddress);
        final server = Row(children: [
          Flexible(
            child: TextFormField(
              controller: ipController,
              decoration: InputDecoration(
                labelText: 'server'.tr,
                contentPadding: const EdgeInsets.all(0.0),
              ),
            ),
          ),
          const Padding(padding: EdgeInsets.only(left: 10)),
          Flexible(
            child: TextFormField(
              controller: portController,
              decoration: InputDecoration(
                labelText: 'port'.tr,
                contentPadding: const EdgeInsets.all(0.0),
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                NumericalRangeFormatter(min: 0, max: 65535),
              ],
            ),
          ),
        ]);

        final usrController = TextEditingController(text: proxy.usr);
        final pwdController = TextEditingController(text: proxy.pwd);

        final auth = Row(children: [
          Flexible(
            child: TextFormField(
              controller: usrController,
              decoration: InputDecoration(
                labelText: 'username'.tr,
                contentPadding: const EdgeInsets.all(0.0),
              ),
            ),
          ),
          const Padding(padding: EdgeInsets.only(left: 10)),
          Flexible(
            child: TextFormField(
              controller: pwdController,
              decoration: InputDecoration(
                labelText: 'password'.tr,
                contentPadding: const EdgeInsets.all(0.0),
              ),
            ),
          ),
        ]);

        List<Widget> customView() {
          if (proxy.proxyMode != ProxyModeEnum.customProxy) {
            return [];
          }
          return [scheme, server, auth];
        }

        return Form(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: _addPadding([
              mode,
              ...customView(),
            ]),
          ),
        );
      },
    );

    // advanced config API items start
    final buildApiProtocol = _buildConfigItem(
      'protocol',
      () => startCfg.value.network == 'tcp'
          ? 'TCP ${startCfg.value.address}'
          : 'Unix',
      (Key key) {
        final items = <Widget>[
          SizedBox(
            width: 80,
            child: DropdownButtonFormField<String>(
              value: startCfg.value.network,
              onChanged: Util.isDesktop() || Util.isAndroid()
                  ? (value) async {
                      startCfg.update((val) {
                        val!.network = value!;
                      });

                      await debounceSave(needRestart: true);
                    }
                  : null,
              items: [
                const DropdownMenuItem<String>(
                  value: 'tcp',
                  child: Text('TCP'),
                ),
                Util.supportUnixSocket()
                    ? const DropdownMenuItem<String>(
                        value: 'unix',
                        child: Text('Unix'),
                      )
                    : null,
              ].where((e) => e != null).map((e) => e!).toList(),
            ),
          )
        ];
        if ((Util.isDesktop() || Util.isAndroid()) &&
            startCfg.value.network == 'tcp') {
          final arr = startCfg.value.address.split(':');
          var ip = '127.0.0.1';
          var port = '0';
          if (arr.length > 1) {
            ip = arr[0];
            port = arr[1];
          }

          final ipController = TextEditingController(text: ip);
          final portController = TextEditingController(text: port);
          updateAddress() async {
            if (ipController.text.isEmpty || portController.text.isEmpty) {
              return;
            }
            final newAddress = '${ipController.text}:${portController.text}';
            if (newAddress != startCfg.value.address) {
              startCfg.value.address = newAddress;

              final saved = await debounceSave(
                  check: () async {
                    // Check if address already in use
                    final configIp = ipController.text;
                    final configPort = int.parse(portController.text);
                    if (configPort == 0) {
                      return '';
                    }
                    try {
                      final socket = await Socket.connect(configIp, configPort,
                          timeout: const Duration(seconds: 3));
                      socket.close();
                      return 'portInUse'
                          .trParams({'port': configPort.toString()});
                    } catch (e) {
                      return '';
                    }
                  },
                  needRestart: true);

              // If save failed, restore the old address
              if (!saved) {
                final oldAddress =
                    (await appController.loadStartConfig()).address;
                startCfg.update((val) async {
                  val!.address = oldAddress;
                });
              }
            }
          }

          ipController.addListener(updateAddress);
          portController.addListener(updateAddress);
          items.addAll([
            const Padding(padding: EdgeInsets.only(left: 20)),
            Flexible(
              child: TextFormField(
                controller: ipController,
                decoration: const InputDecoration(
                  labelText: 'IP',
                  contentPadding: EdgeInsets.all(0.0),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp('[0-9.]')),
                ],
              ),
            ),
            const Padding(padding: EdgeInsets.only(left: 10)),
            Flexible(
              child: TextFormField(
                controller: portController,
                decoration: InputDecoration(
                  labelText: 'port'.tr,
                  contentPadding: const EdgeInsets.all(0.0),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  NumericalRangeFormatter(min: 0, max: 65535),
                ],
              ),
            ),
          ]);
        }

        return Form(
          child: Row(
            children: items,
          ),
        );
      },
    );
    final buildApiToken = _buildConfigItem('apiToken',
        () => startCfg.value.apiToken.isEmpty ? 'notSet'.tr : 'set'.tr,
        (Key key) {
      final apiTokenController =
          TextEditingController(text: startCfg.value.apiToken);
      apiTokenController.addListener(() async {
        if (apiTokenController.text != startCfg.value.apiToken) {
          startCfg.value.apiToken = apiTokenController.text;

          await debounceSave(needRestart: true);
        }
      });
      return TextField(
        key: key,
        obscureText: true,
        controller: apiTokenController,
        focusNode: FocusNode(),
      );
    });

    // advanced config log items start
    buildLogsDir() {
      return ListTile(
          title: Text("logDirectory".tr),
          subtitle: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: TextEditingController(text: logsDir()),
                  enabled: false,
                  readOnly: true,
                ),
              ),
              Util.isDesktop()
                  ? IconButton(
                      icon: const Icon(Icons.folder_open),
                      onPressed: () {
                        launchUrl(Uri.file(logsDir()));
                      },
                    )
                  : CopyButton(logsDir()),
            ],
          ));
    }

    return Obx(() {
      return GestureDetector(
        onTap: () {
          controller.clearTap();
        },
        child: DefaultTabController(
          length: 2,
          child: Scaffold(
              appBar: PreferredSize(
                  preferredSize: const Size.fromHeight(56),
                  child: AppBar(
                    bottom: TabBar(
                      tabs: [
                        Tab(
                          text: 'basic'.tr,
                        ),
                        Tab(
                          text: 'advanced'.tr,
                        ),
                      ],
                    ),
                  )),
              body: TabBarView(
                children: [
                  SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: _addPadding([
                        Text('general'.tr),
                        Card(
                            child: Column(
                          children: _addDivider([
                            buildDownloadDir(),
                            buildMaxRunning(),
                            buildDefaultDirectDownload(),
                            buildBrowserExtension(),
                            buildAutoStartup(),
                          ]),
                        )),
                        const Text('HTTP'),
                        Card(
                            child: Column(
                          children: _addDivider([
                            buildHttpUa(),
                            buildHttpConnections(),
                            buildHttpUseServerCtime(),
                          ]),
                        )),
                        const Text('BitTorrent'),
                        Card(
                            child: Column(
                          children: _addDivider([
                            buildBtListenPort(),
                            buildBtTrackerSubscribeUrls(),
                            buildBtTrackers(),
                            buildBtSeedConfig(),
                            buildBtDefaultClientConfig(),
                          ]),
                        )),
                        Text('ui'.tr),
                        Card(
                            child: Column(
                          children: _addDivider([
                            buildTheme(),
                            buildLocale(),
                          ]),
                        )),
                        Text('about'.tr),
                        Card(
                            child: Column(
                          children: _addDivider([
                            buildHomepage(),
                            buildVersion(),
                            buildThanks(),
                          ]),
                        )),
                      ]),
                    ),
                  ),
                  // Column(
                  //   children: [
                  //     Card(
                  //         child: Column(
                  //       children: [
                  //         ..._addDivider([
                  //           buildApiProtocol(),
                  //           Util.isDesktop() && startCfg.value.network == 'tcp'
                  //               ? buildApiToken()
                  //               : null,
                  //         ]),
                  //       ],
                  //     )),
                  //   ],
                  // ),
                  SingleChildScrollView(
                      child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _addPadding([
                      Text('network'.tr),
                      Card(
                          child: Column(
                        children: _addDivider([buildProxy()]),
                      )),
                      const Text('API'),
                      Card(
                          child: Column(
                        children: _addDivider([
                          buildApiProtocol(),
                          Util.isDesktop() && startCfg.value.network == 'tcp'
                              ? buildApiToken()
                              : null,
                        ]),
                      )),
                      Text('developer'.tr),
                      Card(
                          child: Column(
                        children: _addDivider([
                          buildLogsDir(),
                        ]),
                      )),
                    ]),
                  ))
                ],
              ).paddingOnly(left: 16, right: 16, top: 16, bottom: 16)),
        ),
      );
    });
  }

  void _tapInputWidget(GlobalKey key) {
    if (key.currentContext == null) {
      return;
    }

    if (key.currentContext?.widget is TextField) {
      final textField = key.currentContext?.widget as TextField;
      textField.focusNode?.requestFocus();
      return;
    }

    /* GestureDetector? detector;
    void searchForGestureDetector(BuildContext? element) {
      element?.visitChildElements((element) {
        if (element.widget is GestureDetector) {
          detector = element.widget as GestureDetector?;
        } else {
          searchForGestureDetector(element);
        }
      });
    }

    searchForGestureDetector(key.currentContext);
    detector?.onTap?.call(); */
  }

  Widget Function() _buildConfigItem(
      String label, String Function() text, Widget Function(Key key) input) {
    final tapStatues = controller.tapStatues;
    final inputKey = GlobalKey();
    return () => ListTile(
        title: Text(label.tr),
        subtitle: tapStatues[label] ?? false ? input(inputKey) : Text(text()),
        onTap: () {
          controller.onTap(label);
          WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
            _tapInputWidget(inputKey);
          });
        });
  }

  List<Widget> _addPadding(List<Widget> widgets) {
    final result = <Widget>[];
    for (var i = 0; i < widgets.length; i++) {
      result.add(widgets[i]);
      result.add(_padding);
    }
    return result;
  }

  List<Widget> _addDivider(List<Widget?> widgets) {
    final result = <Widget>[];
    final newArr = widgets.where((e) => e != null).map((e) => e!).toList();
    for (var i = 0; i < newArr.length; i++) {
      result.add(newArr[i]);
      if (i != newArr.length - 1) {
        result.add(_divider);
      }
    }
    return result;
  }

  String _getThemeName(String? themeMode) {
    switch (ThemeMode.values.byName(themeMode ?? ThemeMode.system.name)) {
      case ThemeMode.light:
        return 'themeLight'.tr;
      case ThemeMode.dark:
        return 'themeDark'.tr;
      default:
        return 'themeSystem'.tr;
    }
  }
}

enum ProxyModeEnum {
  noProxy,
  systemProxy,
  customProxy,
}

extension ProxyMode on ProxyConfig {
  ProxyModeEnum get proxyMode {
    if (!enable) {
      return ProxyModeEnum.noProxy;
    }
    if (system) {
      return ProxyModeEnum.systemProxy;
    }
    return ProxyModeEnum.customProxy;
  }

  set proxyMode(ProxyModeEnum value) {
    switch (value) {
      case ProxyModeEnum.noProxy:
        enable = false;
        break;
      case ProxyModeEnum.systemProxy:
        enable = true;
        system = true;
        break;
      case ProxyModeEnum.customProxy:
        enable = true;
        system = false;
        break;
    }
  }
}
