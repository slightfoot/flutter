// Copyright 2018 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'package:meta/meta.dart';
import 'package:path/path.dart' as path;

import '../application_package.dart';
import '../artifacts.dart';
import '../base/common.dart';
import '../base/file_system.dart';
import '../base/io.dart';
import '../base/process_manager.dart';
import '../build_info.dart';
import '../bundle.dart' as bundle;
import '../dart/package_map.dart';
import '../device.dart';
import '../globals.dart';
import '../protocol_discovery.dart';
import '../version.dart';
import '../base/platform.dart';



String getSimulatorPath() {
  return platform.environment['FLUTTER_DART_SIMULATOR'];
}

/*
class DesktopEmulators extends EmulatorDiscovery {
  @override
  bool get supportsPlatform => platform.isWindows
      || platform.isMacOS || platform.isLinux;

  @override
  bool get canListAnything => true;

  @override
  Future<List<Emulator>> get emulators => getEmulators();
}

/// Return the list of Desktop Simulators
Future<List<DesktopEmulator>> getEmulators() async {
  print("Reading JSON ..............");
  final String simulatorConfigsPath = '${getSimulatorPath()}${platform.pathSeparator}simulator-configs.json';

  final File simulatorConfigsFile = io.File(simulatorConfigsPath);

  if(!simulatorConfigsFile.existsSync()) {
    return <DesktopEmulator>[];
  }

  final Map<String, dynamic> simulatorConfigMap = jsonDecode(await simulatorConfigsFile.readAsString());

  if(simulatorConfigMap == null || !simulatorConfigMap.containsKey('devices')) {
    return <DesktopEmulator>[];
  }

  final List<Map<String, dynamic>> simulatorConfigs = simulatorConfigMap['devices'];


  return simulatorConfigs.map((Map<String, dynamic> config) {
    final String name = config['name'];
    return DesktopEmulator(name, name, config['width'], config['height']);
  }).toList();

}

class DesktopEmulator extends Emulator {
  DesktopEmulator(String id, this.simulatorName, this.width, this.height) : super(id, true);


  final String simulatorName;

  final int width;
  final int height;

  @override
  String get name => 'Desktop Simulator: $simulatorName';

  @override
  String get manufacturer => 'Flutter';

  @override
  String get label => '[label]';

  @override
  Future<void> launch() async {
    return processManager.run(<String>[getSimulatorPath(), '-avd', id]).then((ProcessResult runResult) {
      if (runResult.exitCode != 0) {
        throw '${runResult.stdout}\n${runResult.stderr}'.trimRight();
      }
    });
  }
}*/


class FlutterDesktopApp extends ApplicationPackage {
  factory FlutterDesktopApp.fromCurrentDirectory() {
    return FlutterDesktopApp._(fs.currentDirectory);
  }

  FlutterDesktopApp._(Directory directory)
      : _directory = directory,
        super(id: directory.path);

  final Directory _directory;

  @override
  String get name => _directory.basename;

  @override
  File get packagesFile => _directory.childFile('.packages');
}


class FlutterDesktopSimulatorDevice extends Device {
  FlutterDesktopSimulatorDevice(String deviceId, this.simulatorName,  this.width, this.height) : super(deviceId);

  Process _process;
  final DevicePortForwarder _portForwarder = _NoopPortForwarder();

  @override
  Future<bool> get isLocalEmulator async => false;

  final String simulatorName;


  @override
  String get name => 'Desktop Simulator: $simulatorName';

  @override
  DevicePortForwarder get portForwarder => _portForwarder;

  @override
  Future<String> get sdkNameAndVersion async {
    final FlutterVersion flutterVersion = FlutterVersion.instance;
    return 'Flutter ${flutterVersion.frameworkRevisionShort}';
  }

  @override
  Future<TargetPlatform> get targetPlatform async => TargetPlatform.tester;

  @override
  void clearLogs() {}

  final _FlutterTesterDeviceLogReader _logReader =
      _FlutterTesterDeviceLogReader();

  @override
  DeviceLogReader getLogReader({ApplicationPackage app}) => _logReader;

  @override
  Future<bool> installApp(ApplicationPackage app) async => true;

  @override
  Future<bool> isAppInstalled(ApplicationPackage app) async => false;

  @override
  Future<bool> isLatestBuildInstalled(ApplicationPackage app) async => false;

  @override
  bool isSupported() => true;

  bool _isRunning = false;
  bool get isRunning => _isRunning;


  final int width;
  final int height;


  @override
  Future<LaunchResult> startApp(
    ApplicationPackage package, {
    @required String mainPath,
    String route,
    @required DebuggingOptions debuggingOptions,
    Map<String, dynamic> platformArgs,
    bool prebuiltApplication = false,
    bool applicationNeedsRebuild = false,
    bool usesTerminalUi = true,
    bool ipv6 = false,
  }) async {
    final BuildInfo buildInfo = debuggingOptions.buildInfo;


    if(width == null || height == null) {
      throwToolExit('Width: $width and height: $height is not a valid configuration');
    }



    // New dart variant
    // TODO AOT compile the simulator later

    // TODO .exe is windows only
//    final String shellPath = '${artifacts.getArtifactPath(Artifact.engineDartBinary)}.exe';
    final String shellPath = path.join(platform.environment['DART_SDK'], 'bin', 'dart.exe');

    if (!fs.isFileSync(shellPath))
      throwToolExit('Cannot find Flutter-Desktop shell at $shellPath');

    // Prepare launch arguments.
    final List<String> args = <String>[
      shellPath,
      '${getSimulatorPath()}\\bin\\main.dart'
    ];

    // Build assets and perform initial compilation.

    final String assetDirPath = path.join(path.current, 'build', 'flutter_assets');


    print('AssetDirPath is $assetDirPath and getBuildDirectory ${getBuildDirectory()}');
    print("HEREI S THE MAIN PATH $mainPath");
    final String applicationKernelFilePath = bundle.getKernelPathForTransformerOptions(
      fs.path.join(getBuildDirectory(), 'flutter-tester-app.dill'),
      trackWidgetCreation: buildInfo.trackWidgetCreation,
    );
    if(!prebuiltApplication || applicationNeedsRebuild) {
      await bundle.build(
        mainPath: mainPath,
        assetDirPath: assetDirPath,
        applicationKernelFilePath: applicationKernelFilePath,
        precompiledSnapshot: false,
        trackWidgetCreation: buildInfo.trackWidgetCreation,
      );
    }

    args.add('--width=$width');
    args.add('--height=$height');
    args.add('--assetsPath=$assetDirPath');

    args.add('--dart-main');

    args.add('--enable-dart-profiling');

    if (debuggingOptions.debuggingEnabled) {
      if (debuggingOptions.buildInfo.isDebug)
        args.add('--enable-checked-mode');
      if (debuggingOptions.startPaused)
        args.add('--start-paused');
      if (debuggingOptions.skiaDeterministicRendering)
        args.add('--skia-deterministic-rendering');
      if (debuggingOptions.useTestFonts)
        args.add('--use-test-fonts');
      final int observatoryPort = debuggingOptions.observatoryPort ?? 0;
      args.add('--observatory-port=$observatoryPort');
    }

    args.add(applicationKernelFilePath);

    try {
      printTrace(args.join(' '));

      _isRunning = true;
      print('Starting process with ${args.toString()}');
      print('switching working directory to ${getSimulatorPath()}');
      _process = await processManager.start(args,
        workingDirectory: getSimulatorPath(),
        /*environment: <String, String>{
          'FLUTTER_LAUNCH_FROM_TOOLING': 'true',
        },*/
      );
      // Setting a bool can't fail in the callback.
      _process.exitCode.then<void>((_) => _isRunning = false); // ignore: unawaited_futures
      _process.stdout
          .transform<String>(utf8.decoder)
          .transform<String>(const LineSplitter())
          .listen((String line) {
        _logReader.addLine(line);
      });
      _process.stderr
          .transform<String>(utf8.decoder)
          .transform<String>(const LineSplitter())
          .listen((String line) {
        _logReader.addLine(line);
      });

      if (!debuggingOptions.debuggingEnabled)
        return LaunchResult.succeeded();

    final ProtocolDiscovery observatoryDiscovery = ProtocolDiscovery.observatory(
      getLogReader(app: package),
      portForwarder: portForwarder,
       hostPort: debuggingOptions.observatoryPort,
      ipv6: ipv6,
    );

      final Uri observatoryUri = await observatoryDiscovery.uri;
      return LaunchResult.succeeded(observatoryUri: observatoryUri);
    } catch (error) {
      printError('Failed to launch $package: $error');
      return LaunchResult.failed();
    }
  }


  @override
  Future<bool> stopApp(ApplicationPackage app) async {
    _process?.kill();
    _process = null;
    return true;
  }

  @override
  Future<bool> uninstallApp(ApplicationPackage app) async => true;
}

class FlutterDesktopDevices extends PollingDeviceDiscovery {
  FlutterDesktopDevices() : super('Flutter tester');

 // static const String kSimulatorDeviceId = 'flutter-desktop';


 /* final FlutterDesktopSimulatorDevice _simulatorDevice =
      FlutterDesktopSimulatorDevice(kSimulatorDeviceId);
*/
  @override
  bool get canListAnything => true;

  @override
  bool get supportsPlatform => true;

  @override
  Future<List<Device>> pollingGetDevices() async {
    final String simulatorConfigsPath = '${getSimulatorPath()}${platform.pathSeparator}simulator-configs.json';

    final io.File simulatorConfigsFile = io.File(simulatorConfigsPath);

    if(!simulatorConfigsFile.existsSync()) {
      return <FlutterDesktopSimulatorDevice>[];
    }

    final Map<String, dynamic> simulatorConfigMap = jsonDecode(await simulatorConfigsFile.readAsString());

    if(simulatorConfigMap == null || !simulatorConfigMap.containsKey('devices')) {
      return <FlutterDesktopSimulatorDevice>[];
    }

    final List<dynamic> simulatorConfigs = simulatorConfigMap['devices'];

    return simulatorConfigs.map((dynamic config) {
      final String name = config['name'];
      return FlutterDesktopSimulatorDevice(name, name, config['width'], config['height']);
    }).toList();

  }
}

class _FlutterTesterDeviceLogReader extends DeviceLogReader {
  final StreamController<String> _logLinesController =
      StreamController<String>.broadcast();

  @override
  int get appPid => 0;

  @override
  Stream<String> get logLines => _logLinesController.stream;

  @override
  String get name => 'flutter tester log reader';

  void addLine(String line) => _logLinesController.add(line);
}

/// A fake port forwarder that doesn't do anything. Used by flutter tester
/// where the VM is running on the same machine and does not need ports forwarding.
class _NoopPortForwarder extends DevicePortForwarder {
  @override
  Future<int> forward(int devicePort, {int hostPort}) {
    if (hostPort != null && hostPort != devicePort)
      throw 'Forwarding to a different port is not supported by flutter tester';
    return Future<int>.value(devicePort);
  }

  @override
  List<ForwardedPort> get forwardedPorts => <ForwardedPort>[];

  @override
  Future<void> unforward(ForwardedPort forwardedPort) async { }
}
