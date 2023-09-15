import 'dart:async';
import 'dart:isolate';
import 'package:usb_host/definitions.dart';
import 'package:usb_host/misc/config_data.dart';
import 'package:flutter/material.dart';
import 'package:usb_host/widgets/oscilloscope_widget.dart';

import '../misc/file_utilities.dart';
import '../misc/parameter.dart';
import '../protocol/usb_parse.dart';
import '../protocol/usb_protocol.dart';

const hostCommandMax = 1000;
const hostCommandMin = -1000;

const _textUpdateInterval = 250;
const _plotUpdateInterval = 50;
const _timeInterval = 5.0;
const _maxDataPoints = ((_timeInterval * 1000) / _plotUpdateInterval);

class HostDataModel extends ChangeNotifier {
  String? _userMessage;
  double _elapsedTime = 0;
  bool _haltTelemetry = true;
  bool _saveByteFile = false;
  int _startTime = 0,
      _graphUpdateCount = 0,
      _textUpdateCount = 0,
      _hostCommand = 0;

  final usb = UsbApi();
  var configData = ConfigData();

  var plotData = PlotData([],
      maxSamples: _maxDataPoints.toInt(),
      ySegments: 8,
      backgroundColor: Colors.black);

  HostDataModel() {
    // initialize the start time and start the timer
    _startTime = DateTime.now().millisecondsSinceEpoch;
    Timer.periodic(
        const Duration(milliseconds: _plotUpdateInterval), _timerCallback);
  }

  void _timerCallback(Timer t) {
    if (!_haltTelemetry) {
      final currentTime = DateTime.now().millisecondsSinceEpoch;
      _elapsedTime = (currentTime - _startTime).toDouble() / 1000.0;
      for (int i = 0; i < plotData.curves.length; i++) {
        configData.telemetry[i].setBitValue(UsbParse.getData32(usb, i));
        plotData.curves[i].value = configData.telemetry[i].value;
      }
      plotData.updateSamples(_elapsedTime);
      if ((_graphUpdateCount++) % (_textUpdateInterval / _plotUpdateInterval) ==
          0) {
        ++_textUpdateCount;
      }
      notifyListeners();
    }
  }

  void _loadTelemetryTable() {
    ++_textUpdateCount;
    notifyListeners();
  }

  double get elapsedTime {
    return _elapsedTime;
  }

  int get textUpdateCount {
    return _textUpdateCount;
  }

  set saveByteFile(bool save) {
    _saveByteFile = save;
    notifyListeners();
  }

  bool get saveByteFile {
    return _saveByteFile;
  }

  set statusState(String? state) {
    if (state != null) {
      final stateNames = configData.telemetry.map((e) => e.name);
      if (stateNames.contains(state)) {
        configData.status.stateName = state;
      }
      notifyListeners();
    }
  }

  String? get statusState {
    return configData.status.stateName;
  }

  Future<bool> usbConnect() async {
    bool connected = false;
    if (!usb.isRunning) {
      await usb.connect();
      connected = await getParametersUserSequence();
      if (connected) {
        for (var parameter in configData.parameter) {
          parameter.connectedValue = parameter.currentValue;
        }
        _userMessage = Message.info.connected;
      } else {
        usb.closePort();
        _userMessage = Message.error.connect;
      }
    } else {
      usb.closePort();
      _userMessage = Message.info.disconnected;
    }
    notifyListeners();
    return connected;
  }

  int get command {
    return _hostCommand;
  }

  set command(int value) {
    _hostCommand = value;
    UsbParse.setData32(usb, _hostCommand, UsbParse.commandValueIndex);
    usb.sendPacket();
    notifyListeners();
  }

  int get mode {
    return UsbParse.getCommandMode(usb);
  }

  set mode(int value) {
    UsbParse.setCommandMode(usb, value);
    usb.sendPacket();
  }

  Future<bool> getParametersUserSequence() async {
    _userMessage = null;
    bool success = false;
    await getNumParameters().then((numDeviceParameters) async {
      if (numDeviceParameters >= 0) {
        if (configData.parameter.isNotEmpty &&
            numDeviceParameters != configData.parameter.length) {
          _userMessage = Message.error.parameterLengthMatch;
        } else {
          if (configData.parameter.isEmpty) {
            for (int i = 0; i < numDeviceParameters; i++) {
              configData.parameter.add(Parameter());
            }
          }

          await getParameters().then((getParameterSuccess) {
            if (getParameterSuccess) {
              for (var parameter in configData.parameter) {
                parameter.currentValue = parameter.deviceValue;
              }
              _userMessage = Message.info.parameterGet;
              success = true;
            } else {
              _userMessage = Message.error.parameterGet;
            }
          });
        }
      } else {
        _userMessage = Message.error.parameterNum;
      }
    });
    return success;
  }

  Future<int> getNumParameters() async {
    int deviceParameterLength = -1;
    if (usb.isRunning) {
      _haltTelemetry = true;

      UsbParse.setCommandMode(usb, UsbParse.readParameters);
      UsbParse.setData32(usb, 0, UsbParse.parameterTableIndex);
      usb.sendPacket();
      usb.startWatchdog(parameterTimeout);

      while (!usb.watchdogTripped) {
        if ((UsbParse.getCommandMode(usb) == UsbParse.readParameters &&
            UsbParse.getData32(usb, UsbParse.parameterTableIndex) == 0)) {
          deviceParameterLength = UsbParse.getData32(usb, 1);
          break;
        }
        await Future.delayed(const Duration(milliseconds: 1));
      }

      UsbParse.setCommandMode(usb, UsbParse.nullMode);
      usb.sendPacket();
      _haltTelemetry = false;
    }
    return deviceParameterLength;
  }

  Future<bool> getParameters() async {
    bool success = false;
    if (usb.isRunning) {
      _haltTelemetry = true;
      final parameters = configData.parameter;
      int parametersPerRx = UsbParse.maxStates - 1;
      int totalTransfers = (parameters.length / parametersPerRx).ceil();

      for (int transfer = 0; transfer < totalTransfers; transfer++) {
        UsbParse.setCommandMode(usb, UsbParse.readParameters);
        UsbParse.setData32(usb, transfer, UsbParse.parameterTableIndex);
        usb.sendPacket();
        usb.startWatchdog(parameterTimeout);

        while (!usb.watchdogTripped) {
          if ((UsbParse.getCommandMode(usb) == UsbParse.readParameters &&
              UsbParse.getData32(usb, UsbParse.parameterTableIndex) ==
                  transfer)) {
            for (int i = 0; i < parametersPerRx; i++) {
              int parameterIndex = i + (transfer * parametersPerRx);
              if (parameterIndex >= parameters.length) {
                success = true;
                break;
              }
              parameters[parameterIndex].deviceValue =
                  UsbParse.getData32(usb, i + 1);
            }
            break;
          }
          await Future.delayed(const Duration(milliseconds: 1));
        }
      }
      UsbParse.setCommandMode(usb, UsbParse.nullMode);
      usb.sendPacket();
      _haltTelemetry = false;
    }
    return success;
  }

  Future<bool> sendParameters() async {
    bool success = false;
    _userMessage = Message.error.parameterWrite;
    if (usb.isRunning) {
      _haltTelemetry = true;
      final parameters = configData.parameter;
      int parametersPerTx = UsbParse.maxStates - 1;
      int totalTransfers = (parameters.length / parametersPerTx).ceil();

      for (int transfer = 0; transfer < totalTransfers; transfer++) {
        UsbParse.setCommandMode(usb, UsbParse.writeParameters);
        UsbParse.setData32(usb, transfer, UsbParse.parameterTableIndex);
        for (int i = 0; i < parametersPerTx; i++) {
          int parameterIndex = i + (transfer * parametersPerTx);
          if (parameterIndex >= parameters.length) break;
          UsbParse.setData32(usb,
              parameters[parameterIndex].currentValue?.toInt() ?? 0, i + 1);
        }

        usb.sendPacket();
        usb.startWatchdog(parameterTimeout);
        while (!usb.watchdogTripped) {
          if ((UsbParse.getCommandMode(usb) == UsbParse.writeParameters &&
              UsbParse.getData32(usb, UsbParse.parameterTableIndex) ==
                  transfer)) break;
          await Future.delayed(const Duration(milliseconds: 1));
        }
      }

      await getParameters().then((parametersRetrieved) {
        if (parametersRetrieved) {
          final parameterMismatch = parameters
              .where((e) => e.deviceValue != e.currentValue)
              .map((e) => e.name);
          if (parameterMismatch.isEmpty) {
            _userMessage = Message.info.parameterWrite;
            success = true;
          } else {
            _userMessage = Message.error.parameterUpdate(parameterMismatch);
          }
        }
        _haltTelemetry = false;
      });
    }
    return success;
  }

  Future<bool> flashParameters() async {
    _userMessage = null;
    bool success = false, nullComplete = false;
    if (usb.isRunning) {
      _haltTelemetry = true;
      UsbParse.setCommandMode(usb, UsbParse.nullMode);
      usb.sendPacket();
      usb.startWatchdog(parameterTimeout);

      while (!usb.watchdogTripped) {
        if (UsbParse.getCommandMode(usb) == UsbParse.nullMode) {
          nullComplete = true;
          break;
        }
        await Future.delayed(const Duration(milliseconds: 1));
      }

      if (nullComplete) {
        UsbParse.setCommandMode(usb, UsbParse.flashParameters);
        usb.sendPacket();
        usb.startWatchdog(parameterTimeout);

        while (!usb.watchdogTripped) {
          if (UsbParse.getCommandMode(usb) == UsbParse.flashParameters) {
            _userMessage = Message.info.parameterFlash;
            success = true;
            break;
          }
          await Future.delayed(const Duration(milliseconds: 1));
        }
      }

      if (!nullComplete || !success) {
        _userMessage = Message.error.parameterFlash;
      }

      UsbParse.setCommandMode(usb, UsbParse.nullMode);
      usb.sendPacket();
      _haltTelemetry = false;
    }
    return success;
  }

  Future<bool> initBootloader() async {
    _userMessage = null;
    bool success = false, nullComplete = false;
    if (usb.isRunning) {
      _haltTelemetry = true;
      UsbParse.setCommandMode(usb, UsbParse.nullMode);
      usb.sendPacket();
      usb.startWatchdog(parameterTimeout);

      while (!usb.watchdogTripped) {
        if (UsbParse.getCommandMode(usb) == UsbParse.nullMode) {
          nullComplete = true;
          break;
        }
        await Future.delayed(const Duration(milliseconds: 1));
      }

      if (nullComplete) {
        UsbParse.setCommandMode(usb, UsbParse.reprogramBootMode);
        usb.sendPacket();
        usb.startWatchdog(parameterTimeout);

        while (!usb.watchdogTripped) {
          if (UsbParse.getCommandMode(usb) == UsbParse.reprogramBootMode) {
            _userMessage = Message.info.bootloader;
            success = true;
            break;
          }
          await Future.delayed(const Duration(milliseconds: 1));
        }
      }

      if (!nullComplete || !success) {
        _userMessage = Message.error.bootloader;
      }
    }
    return success;
  }

  void updateDisplaySelection() {
    for (int i = 0; i < configData.telemetry.length; i++) {
      plotData.curves[i].displayed = configData.telemetry[i].displayed;
    }
    notifyListeners();
  }

  void recordButtonEvent(void Function() onComplete) {
    switch (usb.recordState) {
      case (RecordState.fileReady):
        usb.recordState = RecordState.inProgress;
        break;

      case (RecordState.inProgress):
        usb.recordState = RecordState.disabled;
        parseDataFile(false, onComplete);
        break;

      default:
        break;
    }
  }

  Future<void> openConfigFile(void Function() onComplete) async {
    final receivePort = ReceivePort();
    await Isolate.spawn(openConfigFileIsolate, receivePort.sendPort);
    _userMessage = null;

    receivePort.listen((message) {
      try {
        final newConfigData = parseConfigFile(message);
        configData = mergeExistingParameters(newConfigData, configData);

        final telemetry = configData.telemetry;
        plotData.curves = List.generate(
            telemetry.length,
            (i) => PlotCurve(
                telemetry[i].name, telemetry[i].max, telemetry[i].min,
                color: telemetry[i].color)
              ..displayed = telemetry[i].displayed);
        // set the selected oscilloscope state to the first state displayed
        plotData.selectedState = plotData.curves
            .firstWhere((element) => element.displayed,
                orElse: () => plotData.curves.first)
            .name;
        configData.initialized = true;
        _loadTelemetryTable();
        onComplete();
      } on Exception catch (e, _) {
        _userMessage = e.toString();
        configData.initialized = false;
        onComplete();
      }
      receivePort.close();
    });
  }

  Future<void> createDataFile() async {
    // create the file here, pass to the comm isolate, and save data there
    final receivePort = ReceivePort();
    receivePort.listen((message) {
      if (message is String) {
        if (message.isNotEmpty) {
          usb.dataFile = message;
          usb.recordState = RecordState.fileReady;
        } else {
          usb.recordState = RecordState.disabled;
        }
        notifyListeners();
      }
      receivePort.close();
    });
    await Isolate.spawn(createDataFileIsolate, receivePort.sendPort);
  }

  Future<void> parseDataFile(
      bool fileSelection, void Function() onComplete) async {
    final completer = Completer<SendPort>();
    final receivePort = ReceivePort();
    _userMessage = null;

    receivePort.listen((message) {
      if (message is SendPort) {
        completer.complete(message);
      } else {
        if (message is String && message.isNotEmpty) {
          _userMessage = message;
        } else {
          _userMessage = Message.info.parseData;
        }
        onComplete();
        receivePort.close();
      }
    });
    await Isolate.spawn(parseDataFileIsolate, receivePort.sendPort);
    SendPort sendPort = await completer.future;
    sendPort.send(fileSelection ? "" : usb.dataFile);
    sendPort.send(saveByteFile);
    sendPort.send(configData.toMap());
  }

  Future<void> saveFile(String text) async {
    final completer = Completer<SendPort>();
    final receivePort = ReceivePort();
    receivePort.listen((message) {
      if (message is SendPort) {
        completer.complete(message);
      }
      receivePort.close();
    });
    await Isolate.spawn(saveFileIsolate, receivePort.sendPort);
    SendPort sendPort = await completer.future;
    sendPort.send(text);
  }

  String? get userMessage {
    return _userMessage;
  }
}
