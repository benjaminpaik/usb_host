import 'package:flutter/material.dart';
import 'dart:async';
import 'package:usb_host/definitions.dart';
import 'package:usb_host/protocol/usb_parse.dart';
import 'package:usb_host/protocol/usb_protocol.dart';

import '../misc/config_data.dart';
import '../misc/parameter.dart';

class UsbModel extends ChangeNotifier {

  String _userMessage = "";
  final UsbApi _usb;
  final ConfigData _configData;
  int _command = 0;

  UsbModel(this._usb, this._configData);

  Future<bool> usbConnect() async {
    bool connected = false;
    if (!_usb.isRunning) {
      await _usb.connect();
      connected = await getParametersUserSequence();
      if (connected) {
        for (var parameter in _configData.parameter) {
          parameter.connectedValue = parameter.currentValue;
        }
        _userMessage = Message.info.connected;
      } else {
        _usb.closePort();
      }
    } else {
      _usb.closePort();
      _userMessage = Message.info.disconnected;
    }
    notifyListeners();
    return connected;
  }

  bool get isRunning {
    return _usb.isRunning;
  }

  int get command {
    return _command;
  }

  int get commandMax {
    return _configData.commandMax;
  }

  int get commandMin {
    return _configData.commandMin;
  }

  set command(int value) {
    _command = value;
    UsbParse.setData32(_usb, _command, UsbParse.commandValueIndex);
    _usb.sendPacket();
    notifyListeners();
  }

  int get mode {
    return UsbParse.getCommandMode(_usb);
  }

  set mode(int value) {
    UsbParse.setCommandMode(_usb, value);
    _usb.sendPacket();
  }

  Future<bool> getParametersUserSequence() async {
    _userMessage = "";
    bool success = false;
    await getNumParameters().then((numDeviceParameters) async {
      if (numDeviceParameters >= 0) {
        if (_configData.parameter.isNotEmpty &&
            numDeviceParameters != _configData.parameter.length) {
          _userMessage = Message.error.parameterLengthMatch;
        } else {
          if (_configData.parameter.isEmpty) {
            for (int i = 0; i < numDeviceParameters; i++) {
              _configData.parameter.add(Parameter());
            }
          }

          await getParameters().then((getParameterSuccess) {
            if (getParameterSuccess) {
              for (var parameter in _configData.parameter) {
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
    if (_usb.isRunning) {

      UsbParse.setCommandMode(_usb, UsbParse.readParameters);
      UsbParse.setData32(_usb, 0, UsbParse.parameterTableIndex);
      _usb.sendPacket();
      _usb.startWatchdog(parameterTimeout);

      while (!_usb.watchdogTripped) {
        if ((UsbParse.getCommandMode(_usb) == UsbParse.readParameters &&
            UsbParse.getData32(_usb, UsbParse.parameterTableIndex) == 0)) {
          deviceParameterLength = UsbParse.getData32(_usb, 1);
          break;
        }
        await Future.delayed(const Duration(milliseconds: 1));
      }

      UsbParse.setCommandMode(_usb, UsbParse.nullMode);
      _usb.sendPacket();
    }
    return deviceParameterLength;
  }

  Future<bool> getParameters() async {
    bool success = false;
    if (_usb.isRunning) {
      final parameters = _configData.parameter;
      int parametersPerRx = UsbParse.maxStates - 1;
      int totalTransfers = (parameters.length / parametersPerRx).ceil();

      for (int transfer = 0; transfer < totalTransfers; transfer++) {
        UsbParse.setCommandMode(_usb, UsbParse.readParameters);
        UsbParse.setData32(_usb, transfer, UsbParse.parameterTableIndex);
        _usb.sendPacket();
        _usb.startWatchdog(parameterTimeout);

        while (!_usb.watchdogTripped) {
          if ((UsbParse.getCommandMode(_usb) == UsbParse.readParameters &&
              UsbParse.getData32(_usb, UsbParse.parameterTableIndex) ==
                  transfer)) {
            for (int i = 0; i < parametersPerRx; i++) {
              int parameterIndex = i + (transfer * parametersPerRx);
              if (parameterIndex >= parameters.length) {
                success = true;
                break;
              }
              parameters[parameterIndex].deviceValue =
                  UsbParse.getData32(_usb, i + 1);
            }
            break;
          }
          await Future.delayed(const Duration(milliseconds: 1));
        }
      }
      UsbParse.setCommandMode(_usb, UsbParse.nullMode);
      _usb.sendPacket();
    }
    return success;
  }

  Future<bool> sendParameters() async {
    bool success = false;
    _userMessage = Message.error.parameterWrite;
    if (_usb.isRunning) {
      final parameters = _configData.parameter;
      int parametersPerTx = UsbParse.maxStates - 1;
      int totalTransfers = (parameters.length / parametersPerTx).ceil();

      for (int transfer = 0; transfer < totalTransfers; transfer++) {
        UsbParse.setCommandMode(_usb, UsbParse.writeParameters);
        UsbParse.setData32(_usb, transfer, UsbParse.parameterTableIndex);
        for (int i = 0; i < parametersPerTx; i++) {
          int parameterIndex = i + (transfer * parametersPerTx);
          if (parameterIndex >= parameters.length) break;
          UsbParse.setData32(_usb,
              parameters[parameterIndex].currentValue?.toInt() ?? 0, i + 1);
        }

        _usb.sendPacket();
        _usb.startWatchdog(parameterTimeout);
        while (!_usb.watchdogTripped) {
          if ((UsbParse.getCommandMode(_usb) == UsbParse.writeParameters &&
              UsbParse.getData32(_usb, UsbParse.parameterTableIndex) ==
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
      });
    }
    return success;
  }

  Future<bool> flashParameters() async {
    bool success = false, nullComplete = false;
    _userMessage = Message.error.parameterFlash;
    if (_usb.isRunning) {
      UsbParse.setCommandMode(_usb, UsbParse.nullMode);
      _usb.sendPacket();
      _usb.startWatchdog(parameterTimeout);

      while (!_usb.watchdogTripped) {
        if (UsbParse.getCommandMode(_usb) == UsbParse.nullMode) {
          nullComplete = true;
          break;
        }
        await Future.delayed(const Duration(milliseconds: 1));
      }

      if (nullComplete) {
        UsbParse.setCommandMode(_usb, UsbParse.flashParameters);
        _usb.sendPacket();
        _usb.startWatchdog(parameterTimeout);

        while (!_usb.watchdogTripped) {
          if (UsbParse.getCommandMode(_usb) == UsbParse.flashParameters) {
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

      UsbParse.setCommandMode(_usb, UsbParse.nullMode);
      _usb.sendPacket();
    }
    return success;
  }

  Future<bool> initBootloader() async {
    _userMessage = "";
    bool success = false, nullComplete = false;
    if (_usb.isRunning) {
      UsbParse.setCommandMode(_usb, UsbParse.nullMode);
      _usb.sendPacket();
      _usb.startWatchdog(parameterTimeout);

      while (!_usb.watchdogTripped) {
        if (UsbParse.getCommandMode(_usb) == UsbParse.nullMode) {
          nullComplete = true;
          break;
        }
        await Future.delayed(const Duration(milliseconds: 1));
      }

      if (nullComplete) {
        UsbParse.setCommandMode(_usb, UsbParse.reprogramBootMode);
        _usb.sendPacket();
        _usb.startWatchdog(parameterTimeout);

        while (!_usb.watchdogTripped) {
          if (UsbParse.getCommandMode(_usb) == UsbParse.reprogramBootMode) {
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

  String get userMessage {
    return _userMessage;
  }

}
