import 'package:get/get.dart';

import '../../../../util/updater.dart';

class SettingController extends GetxController {
  final tapStatues = <String, bool>{}.obs;
  final latestVersion = Rxn<VersionInfo>();

  @override
  void onInit() {
    super.onInit();
    fetchLatestVersion();
  }

  // set all tap status to false
  void clearTap() {
    tapStatues.updateAll((key, value) => false);
  }

  // set one tap status to true
  void onTap(String key) {
    clearTap();
    tapStatues[key] = true;
  }

  // fetch latest version
  void fetchLatestVersion() async {
    latestVersion.value = await checkUpdate();
  }
}
