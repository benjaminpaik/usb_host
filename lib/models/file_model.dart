import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:file_picker/file_picker.dart';
import 'package:usb_host/definitions.dart';
import 'package:usb_host/misc/config_data.dart';
import 'package:flutter/material.dart';
import 'package:yaml/yaml.dart';

import '../misc/file_utilities.dart';
import '../protocol/usb_protocol.dart';

class FileModel extends ChangeNotifier {

  final UsbApi _usb;
  final ConfigData _configData;

  bool _saveByteFile = false;
  String _userMessage = "";

  FileModel(this._usb, this._configData);

  set saveByteFile(bool save) {
    _saveByteFile = save;
    notifyListeners();
  }

  bool get saveByteFile {
    return _saveByteFile;
  }

  void recordButtonEvent(void Function() onComplete) {
    switch (_usb.recordState) {
      case (RecordState.fileReady):
        _usb.recordState = RecordState.inProgress;
        break;

      case (RecordState.inProgress):
        _usb.recordState = RecordState.disabled;
        parseDataFile(false, onComplete);
        break;

      default:
        break;
    }
    notifyListeners();
  }

  RecordState get recordState {
    return _usb.recordState;
  }

  Future<void> openConfigFile(void Function(bool success) onComplete) async {

    final selectedFile =
    await FilePicker.platform.pickFiles(dialogTitle: 'open config');
    _userMessage = "";

    if(selectedFile != null) {
      try {
        final file = File(selectedFile.files.single.path!);
        final contents = await file.readAsString();
        final configMap = loadYaml(contents) as Map;
        _configData.updateFromNewConfig(ConfigData.fromMap(configMap));
        onComplete(true);
      } on Exception catch (e, _) {
        _userMessage = e.toString();
        onComplete(false);
      }
    }
  }

  void saveConfigFile() {
    if (_configData.telemetry.isNotEmpty) {
      saveFile(generateConfigFile(_configData));
    }
  }

  void saveHeaderFile() {
    saveFile(generateHeaderFile(_configData));
  }

  Future<void> createDataFile() async {
    // create the file here, pass to the comm isolate, and save data there
    final receivePort = ReceivePort();
    receivePort.listen((message) {
      if (message is String) {
        if (message.isNotEmpty) {
          _usb.dataFile = message;
          _usb.recordState = RecordState.fileReady;
        } else {
          _usb.recordState = RecordState.disabled;
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
    _userMessage = "";

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
    sendPort.send(fileSelection ? "" : _usb.dataFile);
    sendPort.send(saveByteFile);
    sendPort.send(_configData.toMap());
  }

  String get userMessage {
    return _userMessage;
  }

}
