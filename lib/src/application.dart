// @license
// Copyright (c) 2019 - 2022 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:async';
import 'dart:io';

import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/material.dart';
import 'package:gg_value/gg_value.dart';

import 'com/tcp/bonjour_service.dart';
import 'com/tcp/mocks/mock_network_interface.dart';
import 'measure/helpers.dart';
import 'measure/measure.dart';
import 'measure/tcp/measure_tcp.dart';
import 'measure/types.dart';
import 'utils/is_test.dart';

// #############################################################################
class ApplicationDeps {
  final networkInterfaceList = NetworkInterface.list;
}

class MockApplicationDeps implements ApplicationDeps {
  @override
  final networkInterfaceList = MockNetworkInterface.list;
}

// #############################################################################
class Application {
  Application() {
    _d = isTest ? MockApplicationDeps() : ApplicationDeps();
    _init();
  }

  // ...........................................................................
  void dispose() {
    for (final d in _dispose) {
      d();
    }
  }

  // ...........................................................................
  Future<void> get waitUntilConnected => _waitUntilConnected.future;

  final measurmentMode = GgValue<MeasurmentMode>(seed: MeasurmentMode.tcp);

  // ...........................................................................
  Measure? _measure;

  // ...........................................................................
  void waitForConnections() async {
    await _waitForFirstConnection();
    _listenToMeasurmentMode();
    _listenForCommands();
  }

  // ...........................................................................
  Future<void> startMeasurements() async {
    if (_measure?.isMeasuring.value == true) {
      return;
    }
    isMeasuring.value = true;

    if (measurmentMode.value == MeasurmentMode.tcp) {
      _measure = MeasureTcp(role: MeasurmentRole.master);
    } else {
      throw UnimplementedError;
    }

    await _measure!.start();
  }

  // ...........................................................................
  Future<void> stopMeasurments() async {
    await _measure?.stop();
  }

  final isMeasuring = GgValue<bool>(seed: false);
  void _initIsMeasuring() {
    _dispose.add(isMeasuring.dispose);
  }

  // ######################
  // Test
  // ######################

  @visibleForTesting
  BonjourService get remoteControlService => _remoteControlService;

  @visibleForTesting
  final int port = randomPort();
  String get ip => _ipAddress;

  // ######################
  // Private
  // ######################

  late ApplicationDeps _d;
  final _isInitialized = Completer();

  final List<Function()> _dispose = [];

  late String _ipAddress;
  bool get isConnected => _remoteControlService.connections.value.isNotEmpty;

  // ...........................................................................
  Future<void> _initIpAddress() async {
    _ipAddress = '127.0.0.1';
    for (var interface in await _d.networkInterfaceList()) {
      for (var addr in interface.addresses) {
        _ipAddress = addr.address;
        break;
      }
    }
  }

  // ...........................................................................
  void _init() async {
    _initIsMeasuring();
    await _initIpAddress();
    await _initRemoteControl();
    _isInitialized.complete();
  }

  // ...........................................................................
  late BonjourService _remoteControlService;
  Future<void> _initRemoteControl() async {
    _remoteControlService = BonjourService(
      mode: NetworkServiceMode.masterAndSlave,
      service: BonsoirService(
        name: 'Mobile Network Evaluator',
        port: port,
        type: '_mobile_network_evaluator._tcp',
      ),
    );

    _remoteControlService.start();
    _dispose.add(_remoteControlService.dispose);
  }

  // ...........................................................................
  final _waitUntilConnected = Completer<void>();

  // ...........................................................................
  Future<void> _waitForFirstConnection() async {
    await _remoteControlService.connections
        .where((p0) {
          return p0.isNotEmpty;
        })
        .map(
          (p0) => null,
        )
        .first;
    _waitUntilConnected.complete();
  }

  // ...........................................................................
  void _sendCommand(String command) {
    _remoteControlService.connections.value.first.sendString(command);
  }

  // ...........................................................................
  void _listenForCommands() {
    _remoteControlService.connections.value.first.receiveData.listen(
      (uint8List) {
        final string = String.fromCharCodes(uint8List);
        if (string.startsWith('setMode:')) {
          final modeStr = string.split(':').last;
          final receivedMode =
              MeasurmentMode.values.firstWhere((e) => e.toString() == modeStr);
          measurmentMode.value = receivedMode;
        }
      },
    );
  }

  // ...........................................................................
  void _listenToMeasurmentMode() {
    measurmentMode.stream.listen(
      (value) {
        _sendCommand('setMode:$value');
      },
    );
  }
}

// #############################################################################
Application exampleApplication() {
  return Application();
}
