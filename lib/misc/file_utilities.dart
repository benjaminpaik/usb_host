import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:usb_host/misc/config_data.dart';
import 'package:usb_host/misc/parameter.dart';
import 'package:usb_host/misc/telemetry.dart';
import 'package:usb_host/protocol/usb_parse.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

const newline = "\n";
const indent = "  ";

enum RecordState {
  disabled(Icon(Icons.videocam_off_outlined)),
  fileReady(Icon(Icons.video_call_rounded)),
  inProgress(Icon(Icons.stop_circle));

  final Icon icon;
  const RecordState(this.icon);
}

Future<void> saveFile(String text) async {
  final selectedFile =
  await FilePicker.platform.saveFile(dialogTitle: 'save config');

  if (selectedFile != null) {
    final file = File(selectedFile);
    file.writeAsString(text);
  }
}

Future<void> createDataFileIsolate(SendPort sendPort) async {
  final fileName =
      await FilePicker.platform.saveFile(dialogTitle: 'create data file');
  sendPort.send(fileName ?? false);
}

Future<void> parseDataFileIsolate(SendPort sendPort) async {
  String userMessage = "";
  String rawDataFile = "";
  bool configReceived = false, saveByteFile = false;
  ConfigData configData = ConfigData();
  final receivePort = ReceivePort();
  sendPort.send(receivePort.sendPort);

  receivePort.listen((data) {
    if (data is String) {
      rawDataFile = data;
    } else if (data is bool) {
      saveByteFile = data;
    } else if (data is Map) {
      try {
        configData = ConfigData.fromMap(data);
      } catch(e) {
        userMessage = e.toString();
      }
      configReceived = true;
    }
  });

  while (!configReceived) {
    // yield to the listener
    await Future.delayed(Duration.zero);
  }

  if(userMessage.isEmpty) {
    if (rawDataFile.isEmpty) {
      final selectedFile =
      await FilePicker.platform.pickFiles(dialogTitle: 'open data file');
      rawDataFile = selectedFile?.files.single.path ?? "";
    }
    if (rawDataFile.isNotEmpty) {
      try {
        await convertDataFile(configData, rawDataFile, saveByteFile);
      } on Exception catch (e, _) {
        userMessage = e.toString();
      }
    }
  }
  sendPort.send(userMessage);
  receivePort.close();
}

String generateConfigFile(ConfigData configData) {
  String inputText = "--- ${newline * 2}";
  inputText += "# ${DateTime.now().toString()}${newline * 2}";

  // add command data
  inputText += "${ConfigKeys.command.name}: $newline";
  inputText +=
      "$indent${ConfigCommandKeys.max.name}: ${configData.commandMax} $newline";
  inputText +=
      "$indent${ConfigCommandKeys.min.name}: ${configData.commandMin} $newline";
  inputText += "$indent${ConfigCommandKeys.modes.name}: $newline";

  for (int i = 0; i < configData.modes.length; i++) {
    inputText += "$indent- ${configData.modes[i]} $newline";
  }
  inputText += newline;

  // add telemetry data
  inputText += "${ConfigKeys.telemetry.name}: $newline";
  for (int i = 0; i < configData.telemetry.length; i++) {
    inputText += "$indent- # $i $newline";
    inputText +=
        "${indent * 2}${TelemetryKeys.name.name}: ${configData.telemetry[i].name}$newline";
    inputText +=
        "${indent * 2}${TelemetryKeys.max.name}: ${configData.telemetry[i].max}$newline";
    inputText +=
        "${indent * 2}${TelemetryKeys.min.name}: ${configData.telemetry[i].min}$newline";
    inputText +=
        "${indent * 2}${TelemetryKeys.type.name}: ${configData.telemetry[i].typeString.toString()}$newline";
    inputText +=
        "${indent * 2}${TelemetryKeys.scale.name}: ${configData.telemetry[i].scale}$newline";
    inputText +=
        "${indent * 2}${TelemetryKeys.color.name}: ${configData.telemetry[i].colorString}$newline";
    inputText +=
        "${indent * 2}${TelemetryKeys.display.name}: ${configData.telemetry[i].display}$newline";
  }
  inputText += newline;

  // add status data
  inputText += "${ConfigKeys.status.name}: $newline";
  inputText +=
      "$indent${StatusBitKeys.state.name}: ${configData.status.stateName} $newline";
  inputText += "$indent${StatusBitKeys.fields.name}: $newline";
  for (int i = 0; i < configData.status.numFields; i++) {
    inputText += "${indent * 2}- # $i $newline";
    inputText +=
        "${indent * 3}${StatusFieldKeys.name.name}: ${configData.status.fieldName(i)} $newline";
    inputText +=
        "${indent * 3}${StatusFieldKeys.bits.name}: ${configData.status.numBits(i)} $newline";
  }
  inputText += newline;

  // add parameter data
  inputText += "${ConfigKeys.parameters.name}: $newline";
  for (int i = 0; i < configData.parameter.length; i++) {
    final parameter = configData.parameter[i];
    inputText += "$indent- # $i $newline";
    inputText +=
        "${indent * 2}${ParameterKeys.name.name}: ${parameter.name} $newline";
    inputText +=
        "${indent * 2}${ParameterKeys.type.name}: ${parameter.type.name} $newline";
    inputText +=
        "${indent * 2}${ParameterKeys.value.name}: ${parameter.currentString} $newline";
  }

  return inputText;
}

String addField(String name, int characters) {
  int spaces = characters - name.length;
  if (spaces < 0) spaces = 0;
  return "$name${(" " * spaces)}";
}

Future<Object> convertDataFile(
    ConfigData configData, String rawDataFileName, bool saveByteFile) async {
  final rawDataFile = File(rawDataFileName);
  final dataLines = await rawDataFile.readAsLines();

  final fileNameIndex = rawDataFileName.lastIndexOf(RegExp(r'/|\\'));
  final extensionIndex = rawDataFileName.lastIndexOf('.');
  final dataFileName = extensionIndex > fileNameIndex
      ? rawDataFileName.substring(0, extensionIndex)
      : rawDataFileName.substring(fileNameIndex + 1);

  final writer = File("$dataFileName.csv").openWrite();
  writer.write(parseDataHeaders(configData));
  await writer.flush();
  writer.writeAll(DataRowIterable(configData, true, dataLines));
  await writer.close();
  if (!saveByteFile) {
    await rawDataFile.delete();
  }
  return Object();
}

class DataRowIterable extends Iterable<String> {
  final List<String> dataLines;
  final ConfigData configData;
  final bool parseStatus;

  DataRowIterable(this.configData, this.parseStatus, this.dataLines);

  @override
  Iterator<String> get iterator =>
      DataRowIterator(configData, parseStatus, dataLines);
}

class DataRowIterator implements Iterator<String> {
  final List<String> dataLines;
  final ConfigData configData;
  final bool parseStatus;

  DataRowIterator(this.configData, this.parseStatus, this.dataLines);

  int _index = 0, _timePrevious = 0, _timeStamp = 0;
  String _current = "";

  @override
  String get current => _current;

  @override
  bool moveNext() {
    if (_index >= dataLines.length) {
      _current = "";
      return false;
    } else {
      String rawDataRow = dataLines[_index++];
      if (rawDataRow.isNotEmpty) {
        rawDataRow = rawDataRow.substring(1, rawDataRow.length - 1);
        final bytes = rawDataRow.split(',').map((e) => int.parse(e)).toList();
        final timeCurrent = bytes[UsbParse.timestampIndex];
        final timeDiff = parseTimeDiff(timeCurrent, _timePrevious);
        _timePrevious = timeCurrent;
        _timeStamp += timeDiff;
        _current = parseDataRow(configData, parseStatus, _timeStamp, bytes);
      }
    }
    return true;
  }
}

String parseDataHeaders(ConfigData configData) {
  String headerData = "time(ms), mode, ";
  for (int i = 0; i < configData.telemetry.length; i++) {
    headerData += "${configData.telemetry[i].name}, ";
  }
  for (int i = 0; i < configData.status.numFields; i++) {
    headerData += "${configData.status.fieldName(i)}, ";
  }
  headerData += newline;
  return headerData;
}

int parseTimeDiff(int timeCurrent, int timePrevious) {
  int timeDiff = 0;
  if (timeCurrent >= timePrevious) {
    timeDiff = timeCurrent - timePrevious;
  } else {
    timeDiff = timeCurrent + (UsbParse.timestampRollover - timePrevious);
  }
  return timeDiff;
}

String parseDataRow(
    ConfigData configData, bool parseStatus, int timeStamp, List<int> bytes) {
  String rowText = "";

  int stateIndex = 0;
  final stateValues = List.filled(configData.telemetry.length, 0.0);
  final byteData = ByteData(4);

  // convert a row of bytes into 32-bit integers
  for (int i = 0; i < configData.telemetry.length; i++) {
    int startIndex = UsbParse.dataStartIndex + (4 * stateIndex);
    byteData.setUint8(0, bytes[startIndex]);
    byteData.setUint8(1, bytes[startIndex + 1]);
    byteData.setUint8(2, bytes[startIndex] + 2);
    byteData.setUint8(3, bytes[startIndex] + 3);
    if (configData.telemetry[i].type == TelemetryType.float) {
      stateValues[i] = byteData.getFloat32(0) * configData.telemetry[i].scale;
    } else {
      stateValues[i] =
          byteData.getInt32(0).toDouble() * configData.telemetry[i].scale;
    }
    ++stateIndex;
  }
  // add the timestamp and command mode
  rowText = "$timeStamp, ${bytes[UsbParse.commandModeIndex]}, ";

  for (int i = 0; i < configData.telemetry.length; i++) {
    rowText += "${stateValues[i]}, ";
  }

  if (parseStatus) {
    configData.status.value = stateValues[configData.status.stateIndex].toInt();
    for (int i = 0; i < configData.status.numFields; i++) {
      rowText += "${configData.status.fieldValue(i)}, ";
    }
  }
  rowText += newline;
  return rowText;
}

String generateHeaderFile(ConfigData configData) {
  String inputText = "#ifndef PARAMETERS_H_$newline";
  inputText += "#define PARAMETERS_H_$newline$newline";
  inputText +=
      "#define NUM_PARAMETERS ${configData.parameter.length}$newline$newline";
  inputText += "typedef struct {$newline";

  int index = 0;
  for (final parameter in configData.parameter) {
    final type = (parameter.type == ParameterType.int) ? "long" : "float";
    inputText += "  /*${index++}*/ $type ${parameter.name};$newline";
  }

  inputText += "} PARAMETER;$newline$newline";
  inputText += "extern PARAMETER P;$newline$newline";
  inputText += "#endif /* PARAMETERS_H_ */$newline";

  return inputText;
}
