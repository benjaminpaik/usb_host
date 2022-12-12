import 'dart:async';
import 'dart:isolate';
import 'package:usb_host/definitions.dart';
import 'package:usb_host/misc/config_data.dart';
import 'package:flutter/material.dart';
import 'package:usb_host/widgets/oscilloscope_widget.dart';

import '../misc/file_utilities.dart';
import '../misc/parameter.dart';
import '../protocol/serial_parse.dart';
import '../protocol/serial_protocol.dart';

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
  bool saveByteFile = false;
  int _startTime = 0,
      _graphUpdateCount = 0,
      _textUpdateCount = 0,
      _hostCommand = 0;

  final serial = SerialApi();
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
        configData.telemetry[i].setBitValue(SerialParse.getData32(serial, i));
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

  Future<bool> serialConnect() async {
    bool connected = false;
    if (!serial.isRunning) {
      await serial.connect();
      connected = await getParametersUserSequence();
      if (connected) {
        for (var parameter in configData.parameter) {
          parameter.connectedValue = parameter.currentValue;
        }
        _userMessage = Message.info.connected;
      }
    } else {
      serial.closePort();
      _userMessage = Message.info.disconnected;
    }
    return connected;
  }

  int get command {
    return _hostCommand;
  }

  set command(int value) {
    _hostCommand = value;
    SerialParse.setData32(serial, _hostCommand, SerialParse.commandValueIndex);
    serial.sendPacket();
    notifyListeners();
  }

  int get mode {
    return SerialParse.getCommandMode(serial);
  }

  set mode(int value) {
    SerialParse.setCommandMode(serial, value);
    serial.sendPacket();
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
    if (serial.isRunning) {
      _haltTelemetry = true;

      SerialParse.setCommandMode(serial, SerialParse.readParameters);
      SerialParse.setData32(serial, 0, SerialParse.parameterTableIndex);
      serial.sendPacket();
      serial.startWatchdog(parameterTimeout);

      while (!serial.watchdogTripped) {
        if ((SerialParse.getCommandMode(serial) == SerialParse.readParameters &&
            SerialParse.getData32(serial, SerialParse.parameterTableIndex) ==
                0)) {
          deviceParameterLength = SerialParse.getData32(serial, 1);
          break;
        }
        await Future.delayed(const Duration(milliseconds: 1));
      }

      SerialParse.setCommandMode(serial, SerialParse.nullMode);
      serial.sendPacket();
      _haltTelemetry = false;
    }
    return deviceParameterLength;
  }

  Future<bool> getParameters() async {
    bool success = false;
    if (serial.isRunning) {
      _haltTelemetry = true;
      final parameters = configData.parameter;
      final returnBuffer = List<int>.filled(parameters.length, 0);
      int parametersPerRx = SerialParse.maxStates - 1;
      int totalTransfers = (returnBuffer.length / parametersPerRx).ceil();

      for (int transfer = 0; transfer < totalTransfers; transfer++) {
        SerialParse.setCommandMode(serial, SerialParse.readParameters);
        SerialParse.setData32(
            serial, transfer, SerialParse.parameterTableIndex);
        serial.sendPacket();
        serial.startWatchdog(parameterTimeout);

        while (!serial.watchdogTripped) {
          if ((SerialParse.getCommandMode(serial) ==
                  SerialParse.readParameters &&
              SerialParse.getData32(serial, SerialParse.parameterTableIndex) ==
                  transfer)) {
            for (int i = 0; i < parametersPerRx; i++) {
              int parameterIndex = i + (transfer * parametersPerRx);
              if (parameterIndex >= parameters.length) {
                success = true;
                break;
              }
              parameters[parameterIndex].deviceValue =
                  SerialParse.getData32(serial, i + 1);
            }
            break;
          }
          await Future.delayed(const Duration(milliseconds: 1));
        }
      }
      SerialParse.setCommandMode(serial, SerialParse.nullMode);
      serial.sendPacket();
      _haltTelemetry = false;
    }
    return success;
  }

  Future<bool> sendParameters() async {
    bool success = false;
    _userMessage = Message.error.parameterWrite;
    if (serial.isRunning) {
      _haltTelemetry = true;
      final parameters = configData.parameter;
      int parametersPerTx = SerialParse.maxStates - 1;
      int totalTransfers = (parameters.length / parametersPerTx).ceil();

      for (int transfer = 0; transfer < totalTransfers; transfer++) {
        SerialParse.setCommandMode(serial, SerialParse.writeParameters);
        SerialParse.setData32(
            serial, transfer, SerialParse.parameterTableIndex);
        for (int i = 0; i < parametersPerTx; i++) {
          int parameterIndex = i + (transfer * parametersPerTx);
          if (parameterIndex >= parameters.length) break;
          SerialParse.setData32(serial,
              parameters[parameterIndex].currentValue?.toInt() ?? 0, i + 1);
        }

        serial.sendPacket();
        serial.startWatchdog(parameterTimeout);
        while (!serial.watchdogTripped) {
          if ((SerialParse.getCommandMode(serial) ==
                  SerialParse.writeParameters &&
              SerialParse.getData32(serial, SerialParse.parameterTableIndex) ==
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
    if (serial.isRunning) {
      _haltTelemetry = true;
      SerialParse.setCommandMode(serial, SerialParse.nullMode);
      serial.sendPacket();
      serial.startWatchdog(parameterTimeout);

      while (!serial.watchdogTripped) {
        if (SerialParse.getCommandMode(serial) == SerialParse.nullMode) {
          nullComplete = true;
          break;
        }
        await Future.delayed(const Duration(milliseconds: 1));
      }

      if (nullComplete) {
        SerialParse.setCommandMode(serial, SerialParse.flashParameters);
        serial.sendPacket();
        serial.startWatchdog(parameterTimeout);

        while (!serial.watchdogTripped) {
          if (SerialParse.getCommandMode(serial) ==
              SerialParse.flashParameters) {
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

      SerialParse.setCommandMode(serial, SerialParse.nullMode);
      serial.sendPacket();
      _haltTelemetry = false;
    }
    return success;
  }

  Future<bool> initBootloader() async {
    _userMessage = null;
    bool success = false, nullComplete = false;
    if (serial.isRunning) {
      _haltTelemetry = true;
      SerialParse.setCommandMode(serial, SerialParse.nullMode);
      serial.sendPacket();
      serial.startWatchdog(parameterTimeout);

      while (!serial.watchdogTripped) {
        if (SerialParse.getCommandMode(serial) == SerialParse.nullMode) {
          nullComplete = true;
          break;
        }
        await Future.delayed(const Duration(milliseconds: 1));
      }

      if (nullComplete) {
        SerialParse.setCommandMode(serial, SerialParse.reprogramBootMode);
        serial.sendPacket();
        serial.startWatchdog(parameterTimeout);

        while (!serial.watchdogTripped) {
          if (SerialParse.getCommandMode(serial) ==
              SerialParse.reprogramBootMode) {
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
    switch (serial.recordState) {
      case (RecordState.fileReady):
        serial.recordState = RecordState.inProgress;
        break;

      case (RecordState.inProgress):
        serial.recordState = RecordState.disabled;
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
          serial.dataFile = message;
          serial.recordState = RecordState.fileReady;
        } else {
          serial.recordState = RecordState.disabled;
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
    sendPort.send(fileSelection ? "" : serial.dataFile);
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
