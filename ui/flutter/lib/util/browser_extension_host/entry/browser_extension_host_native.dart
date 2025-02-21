import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:win32_registry/win32_registry.dart';

import '../../util.dart';
import '../../win32.dart';
import '../browser_extension_host.dart';

final _hostExecName = 'host${Platform.isWindows ? '.exe' : ''}';

const _hostName = 'com.gopeed.gopeed';
const _chromeExtensionId = 'mijpgljlfcapndmchhjffkpckknofcnd';
const _edgeExtensionId = 'dkajnckekendchdleoaenoophcobooce';
const _firefoxExtensionId = '{c5d69a8f-2ed0-46a7-afa4-b3a00dc58088}';
const _debugExtensionIds = [
  'gjddllnejledbfaeondocjpejpamclkk',
  'goaohdfiokcjapgonhofgljfccoccief'
];

// Windows NativeMessagingHosts registry constants
const _chromeNativeHostsKey = r'Software\Google\Chrome\NativeMessagingHosts';
const _edgeNativeHostsKey = r'Software\Microsoft\Edge\NativeMessagingHosts';
const _firefoxNativeHostsKey = r'Software\Mozilla\NativeMessagingHosts';

/// Install host binary for browser extension
Future<void> doInstallHost() async {
  final hostPath = Util.homePathJoin(_hostExecName);
  await Util.installAsset('assets/exec/$_hostExecName', hostPath,
      executable: true);
}

/// Check if specified browser is installed
Future<bool> doCheckBrowserInstalled(Browser browser) async {
  if (Platform.isWindows) {
    switch (browser) {
      case Browser.chrome:
        return await _checkWindowsRegistry(
                r'SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe') ||
            await _checkWindowsRegistry(
                r'SOFTWARE\WOW6432Node\Google\Chrome') ||
            await _checkWindowsExecutable(browser);
      case Browser.edge:
        return await _checkWindowsRegistry(
                r'SOFTWARE\Microsoft\Edge\BLBeacon') ||
            await _checkWindowsRegistry(
                r'SOFTWARE\WOW6432Node\Microsoft\Edge\BLBeacon') ||
            await _checkWindowsExecutable(browser);
      case Browser.firefox:
        return await _checkWindowsRegistry(r'SOFTWARE\Mozilla\Firefox') ||
            await _checkWindowsRegistry(
                r'SOFTWARE\WOW6432Node\Mozilla\Firefox') ||
            await _checkWindowsExecutable(browser);
    }
  } else {
    return await _checkUnixExecutable(browser);
  }
}

/// Check if browser extension manifest is properly installed
Future<bool> doCheckManifestInstalled(Browser browser) async {
  if (await checkBrowserInstalled(browser) == false) return false;

  final manifestPath = _getManifestPath(browser);
  if (manifestPath == null) return false;

  if (Platform.isWindows) {
    final regKey = _getWindowsRegistryKey(browser);
    if (!checkRegistry('$regKey\\$_hostName', '', manifestPath)) {
      return false;
    }
  }

  if (!await File(manifestPath).exists()) {
    return false;
  }

  final existingContent = await File(manifestPath).readAsString();
  final expectedContent = await _getManifestContent(browser);
  return existingContent == expectedContent;
}

/// Install browser extension manifest
Future<void> doInstallManifest(Browser browser) async {
  if (await checkBrowserInstalled(browser) == false) return;
  if (await checkManifestInstalled(browser)) return;

  final manifestPath = _getManifestPath(browser)!;
  final manifestContent = await _getManifestContent(browser);
  final manifestDir = path.dirname(manifestPath);
  await Directory(manifestDir).create(recursive: true);
  await File(manifestPath).writeAsString(manifestContent);

  if (Platform.isWindows) {
    final regKey = _getWindowsRegistryKey(browser);
    upsertRegistry('$regKey\\$_hostName', '', manifestPath);
  }
}

Future<bool> _checkWindowsExecutable(Browser browser) async {
  final paths = _getWindowsExecutablePaths(browser);
  for (var execPath in paths) {
    if (await File(execPath).exists()) {
      return true;
    }
  }
  return false;
}

List<String> _getWindowsExecutablePaths(Browser browser) {
  final programFiles = Platform.environment['PROGRAMFILES'];
  final programFilesX86 = Platform.environment['PROGRAMFILES(X86)'];
  final localAppData = Platform.environment['LOCALAPPDATA'];

  switch (browser) {
    case Browser.chrome:
      return [
        if (programFiles != null)
          path.join(
              programFiles, 'Google', 'Chrome', 'Application', 'chrome.exe'),
        if (programFilesX86 != null)
          path.join(
              programFilesX86, 'Google', 'Chrome', 'Application', 'chrome.exe'),
        if (localAppData != null)
          path.join(
              localAppData, 'Google', 'Chrome', 'Application', 'chrome.exe'),
      ];
    case Browser.edge:
      return [
        if (programFiles != null)
          path.join(
              programFiles, 'Microsoft', 'Edge', 'Application', 'msedge.exe'),
        if (programFilesX86 != null)
          path.join(programFilesX86, 'Microsoft', 'Edge', 'Application',
              'msedge.exe'),
        if (localAppData != null)
          path.join(
              localAppData, 'Microsoft', 'Edge', 'Application', 'msedge.exe'),
      ];
    case Browser.firefox:
      return [
        if (programFiles != null)
          path.join(programFiles, 'Mozilla Firefox', 'firefox.exe'),
        if (programFilesX86 != null)
          path.join(programFilesX86, 'Mozilla Firefox', 'firefox.exe'),
      ];
  }
}

Future<bool> _checkUnixExecutable(Browser browser) async {
  final paths = _getUnixExecutablePaths(browser);
  for (var execPath in paths) {
    execPath = execPath.replaceAll('~', Platform.environment['HOME'] ?? '');
    if (await Directory(execPath).exists() || await File(execPath).exists()) {
      return true;
    }
  }
  return false;
}

List<String> _getUnixExecutablePaths(Browser browser) {
  if (Platform.isMacOS) {
    switch (browser) {
      case Browser.chrome:
        return [
          '/Applications/Google Chrome.app',
          '~/Applications/Google Chrome.app',
          '/Users/${Platform.environment['USER']}/Applications/Google Chrome.app'
        ];
      case Browser.edge:
        return [
          '/Applications/Microsoft Edge.app',
          '~/Applications/Microsoft Edge.app',
          '/Users/${Platform.environment['USER']}/Applications/Microsoft Edge.app'
        ];
      case Browser.firefox:
        return [
          '/Applications/Firefox.app',
          '~/Applications/Firefox.app',
          '/Users/${Platform.environment['USER']}/Applications/Firefox.app'
        ];
    }
  } else {
    switch (browser) {
      case Browser.chrome:
        return [
          '/usr/bin/google-chrome',
          '/usr/bin/google-chrome-stable',
          '/usr/bin/chrome',
          '/snap/bin/google-chrome',
          '/opt/google/chrome/google-chrome'
        ];
      case Browser.edge:
        return [
          '/usr/bin/microsoft-edge',
          '/usr/bin/microsoft-edge-stable',
          '/snap/bin/microsoft-edge',
          '/opt/microsoft/msedge/msedge'
        ];
      case Browser.firefox:
        return [
          '/usr/bin/firefox',
          '/snap/bin/firefox',
          '/usr/lib/firefox/firefox',
          '/opt/firefox/firefox'
        ];
    }
  }
}

String? _getManifestPath(Browser browser) {
  final manifestName =
      browser == Browser.firefox ? '$_hostName.moz.json' : '$_hostName.json';
  if (Platform.isWindows) {
    return Util.homePathJoin(manifestName);
  }

  final home =
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
  if (home == null) return null;

  if (Platform.isMacOS) {
    switch (browser) {
      case Browser.chrome:
        return path.join(home, 'Library', 'Application Support', 'Google',
            'Chrome', 'NativeMessagingHosts', manifestName);
      case Browser.edge:
        return path.join(home, 'Library', 'Application Support',
            'Microsoft Edge', 'NativeMessagingHosts', manifestName);
      case Browser.firefox:
        return path.join(home, 'Library', 'Application Support', 'Mozilla',
            'NativeMessagingHosts', manifestName);
    }
  } else if (Platform.isLinux) {
    switch (browser) {
      case Browser.chrome:
        return path.join(home, '.config', 'google-chrome',
            'NativeMessagingHosts', manifestName);
      case Browser.edge:
        return path.join(home, '.config', 'microsoft-edge',
            'NativeMessagingHosts', manifestName);
      case Browser.firefox:
        return path.join(
            home, '.mozilla', 'native-messaging-hosts', manifestName);
    }
  }
  return null;
}

Future<bool> _checkWindowsRegistry(String keyPath) async {
  try {
    final key = Registry.openPath(RegistryHive.localMachine, path: keyPath);
    key.close();
    return true;
  } catch (e) {
    return false;
  }
}

Future<String> _getManifestContent(Browser browser) async {
  final hostPath = Util.homePathJoin(_hostExecName);
  final manifest = {
    'name': _hostName,
    'description': 'Gopeed browser extension host',
    'path': hostPath,
    'type': 'stdio',
    if (browser != Browser.firefox)
      'allowed_origins': [
        'chrome-extension://$_chromeExtensionId/',
        'chrome-extension://$_edgeExtensionId/',
        ..._debugExtensionIds.map((id) => 'chrome-extension://$id/'),
      ],
    if (browser == Browser.firefox) 'allowed_extensions': [_firefoxExtensionId],
  };
  return const JsonEncoder.withIndent('  ').convert(manifest);
}

String _getWindowsRegistryKey(Browser browser) {
  switch (browser) {
    case Browser.chrome:
      return _chromeNativeHostsKey;
    case Browser.edge:
      return _edgeNativeHostsKey;
    case Browser.firefox:
      return _firefoxNativeHostsKey;
  }
}
