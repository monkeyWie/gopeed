import 'dart:async';

import 'package:badges/badges.dart' as badges;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../i18n/message.dart';
import '../../../../util/input_formatter.dart';
import '../../../../util/locale_manager.dart';
import '../../../../util/message.dart';
import '../../../../util/package_info.dart';
import '../../../../util/util.dart';
import '../../../views/check_list_view.dart';
import '../../../views/directory_selector.dart';
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
    debounceSave({bool needRestart = false}) {
      var completer = Completer<void>();
      timer?.cancel();
      timer = Timer(const Duration(milliseconds: 1000), () {
        appController
            .saveConfig()
            .then(completer.complete)
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
        'useServerCtime'.tr, () => httpConfig.useServerCtime.toString(),
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
      bool isNewVersion(String current, String latest) {
        if (latest == "") {
          return false;
        }

        final v1Parts = current.split('.');
        final v2Parts = latest.split('.');

        for (var i = 0; i < 3; i++) {
          final v1Part = int.parse(v1Parts[i]);
          final v2Part = int.parse(v2Parts[i]);

          if (v1Part < v2Part) {
            return true;
          } else if (v1Part > v2Part) {
            return false;
          }
        }
        return false;
      }

      var hasNewVersion =
          isNewVersion(packageInfo.version, controller.latestVersion.value);
      return ListTile(
        title: hasNewVersion
            ? badges.Badge(
                position: badges.BadgePosition.topStart(start: 36),
                child: Text('version'.tr))
            : Text('version'.tr),
        subtitle: Text(packageInfo.version),
        onTap: () {
          if (hasNewVersion) {
            showDialog(
                context: context,
                builder: (context) => AlertDialog(
                      content: Text('newVersionTitle'.trParams(
                          {'version': controller.latestVersion.value})),
                      actions: [
                        TextButton(
                          onPressed: () {
                            Get.back();
                          },
                          child: Text('newVersionLater'.tr),
                        ),
                        TextButton(
                          onPressed: () {
                            launchUrl(Uri.parse('https://gopeed.com'),
                                mode: LaunchMode.externalApplication);
                          },
                          child: Text('newVersionUpdate'.tr),
                        ),
                      ],
                    ));
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
    final buildProxy = _buildConfigItem(
      'proxy',
      () => downloaderCfg.value.proxy.enable
          ? '${downloaderCfg.value.proxy.scheme}://${downloaderCfg.value.proxy.host}'
          : 'notSet'.tr,
      (Key key) {
        final proxy = downloaderCfg.value.proxy;

        final switcher = Switch(
          value: proxy.enable,
          onChanged: (bool value) async {
            if (value != proxy.enable) {
              downloaderCfg.update((val) {
                val!.proxy.enable = value;
              });

              await debounceSave();
            }
          },
        );

        final scheme = SizedBox(
          width: 100,
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
        final server = [
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
        ];

        final usrController = TextEditingController(text: proxy.usr);
        final pwdController = TextEditingController(text: proxy.pwd);

        final auth = [
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
        ];

        return Form(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: _addPadding([
              switcher,
              scheme,
              Row(
                children: server,
              ),
              Row(
                children: auth,
              ),
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
              onChanged: Util.isDesktop()
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
        if (Util.isDesktop() && startCfg.value.network == 'tcp') {
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
            final newAddress = '${ipController.text}:${portController.text}';
            if (newAddress != startCfg.value.address) {
              startCfg.value.address = newAddress;

              await debounceSave(needRestart: true);
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
                          children: _addDivider(
                              [buildDownloadDir(), buildMaxRunning()]),
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
