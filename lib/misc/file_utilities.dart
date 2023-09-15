import 'dart:convert';
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
const _configDelimiter = "||";

const _colorMap = {
  "red": Colors.red,
  "black": Colors.black,
  "grey": Colors.grey,
  "green": Colors.green,
  "pink": Colors.pink,
  "blue": Colors.blue,
  "white": Colors.white,
  "yellow": Colors.yellow,
  "orange": Colors.orange,
  "purple": Colors.purple,
  "magenta": Colors.pinkAccent,
  "cyan": Colors.cyan,
};

const _telemetryFields = 7;
const _telemetryNameIndex = 1;
const _telemetryStateMaxIndex = 2;
const _telemetryStateMinIndex = 3;
const _telemetryDisplayIndex = 4;
const _telemetryColorIndex = 5;
const _telemetryRatioIndex = 6;

const _statusFields = 3;
const _statusNameIndex = 1;
const _statusBitsIndex = 2;

const _parameterFields = 4;
const _parameterNameIndex = 1;
const _parameterTypeIndex = 2;
const _parameterValueIndex = 3;

enum RecordState {
  disabled(Icon(Icons.videocam_off_outlined)),
  fileReady(Icon(Icons.video_call_rounded)),
  inProgress(Icon(Icons.stop_circle));

  final Icon icon;
  const RecordState(this.icon);
}

void openConfigFileIsolate(SendPort sendPort) async {
  final selectedFile =
      await FilePicker.platform.pickFiles(dialogTitle: 'open config');

  if (selectedFile != null) {
    final file = File(selectedFile.files.single.path!);
    final contents = await file.readAsString();
    sendPort.send(contents);
  }
}

Future<void> saveFileIsolate(SendPort sendPort) async {
  String receivedData = "";
  final receivePort = ReceivePort();
  sendPort.send(receivePort.sendPort);

  receivePort.listen((data) {
    if (data is String) {
      receivedData = data;
    }
  });

  final selectedFile =
      await FilePicker.platform.saveFile(dialogTitle: 'save config');

  while (receivedData.isEmpty) {
    // yield to the listener
    await Future.delayed(Duration.zero);
  }

  if (selectedFile != null) {
    final file = File(selectedFile);
    file.writeAsString(receivedData);
  }
  receivePort.close();
}

Future<void> createDataFileIsolate(SendPort sendPort) async {
  final fileName =
      await FilePicker.platform.saveFile(dialogTitle: 'create data file');
  sendPort.send(fileName ?? false);
}

Future<void> parseDataFileIsolate(SendPort sendPort) async {
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
    } else if (data is Map<ConfigDataKeys, dynamic>) {
      configData = ConfigData.fromMap(data);
      configReceived = true;
    }
  });

  while (!configReceived) {
    // yield to the listener
    await Future.delayed(Duration.zero);
  }

  if (rawDataFile.isEmpty) {
    final selectedFile =
        await FilePicker.platform.pickFiles(dialogTitle: 'open data file');
    rawDataFile = selectedFile?.files.single.path ?? "";
  }

  if (rawDataFile.isNotEmpty) {
    try {
      await convertDataFile(configData, rawDataFile, saveByteFile);
      sendPort.send("");
    } on Exception catch (e, _) {
      sendPort.send(e.toString());
    }
  }
  receivePort.close();
}

String generateConfigFile(ConfigData configData) {
  String inputText = "// ${DateTime.now().toString()}${newline * 2}";
  inputText +=
      "=> command range: ${configData.commandMax}, ${configData.commandMin}, $newline";
  inputText += "=> button text:";

  for (var element in configData.modes) {
    inputText += " $element,";
  }
  inputText += (newline * 2);

  // add state settings to the string for telemetry
  inputText +=
      "index || state name           || state max       || state min       || display || color    || ratio$newline${"-" * 100}$newline";

  // for loop creates 15 lines representing the 15 states
  for (int i = 0; i < configData.telemetry.length; i++) {
    inputText += " ${addField(i.toString(), 5)}||";
    inputText += " ${addField(configData.telemetry[i].name, 21)}||";
    inputText += " ${addField(configData.telemetry[i].max.toString(), 16)}||";
    inputText += " ${addField(configData.telemetry[i].min.toString(), 16)}||";
    inputText +=
        " ${addField(configData.telemetry[i].displayed.toString(), 8)}||";
    inputText +=
        " ${addField(_colorMap.keys.firstWhere((key) => _colorMap[key].toString() == configData.telemetry[i].color.toString()), 9)}||";
    inputText += " ${configData.telemetry[i].ratio.toString()}";
    inputText += newline;
  }

  // add status bitfield to the string
  inputText +=
      "${newline * 2}index || bit name (${configData.status.stateName})${" " * (19 - configData.status.stateName.length)}|| bits$newline${"-" * 47}$newline";

  for (int i = 0; i < configData.status.numFields; i++) {
    inputText += " ${addField(i.toString(), 5)}||";
    inputText += " ${addField(configData.status.fieldName(i), 30)}||";
    inputText += " ${configData.status.numBits(i)}";
    inputText += newline;
  }

  // add in parameter settings to the string
  inputText +=
      "${newline * 2}index || parameter name                   || type  || value$newline${"-" * 60}$newline";

  // for loop creates a line for each unique parameter
  for (int i = 0; i < configData.parameter.length; i++) {
    final parameter = configData.parameter[i];
    final type = parameter.type
        .toString()
        .substring(parameter.type.toString().indexOf(".") + 1)
        .trim();
    inputText += " ${addField(i.toString(), 5)}||";
    inputText += " ${addField(parameter.name, 33)}||";
    inputText += " ${addField(type, 6)}||";
    inputText += " ${parameter.currentString}$newline";
  }
  return inputText;
}

ConfigData parseConfigFile(String configText) {
  final configData = ConfigData();
  const lineSplitter = LineSplitter();
  final lines = lineSplitter.convert(configText);
  int index = -1;

  for (var line in lines) {
    // host settings
    if (line.contains("=>")) {
      index = line.indexOf(":") + 1;
      if (index == -1) {
        throw const FormatException("invalid host settings");
      }
      final fieldText = line.substring(index).trim();

      if (line.contains("command range")) {
        try {
          final range = fieldText.split(",");
          final max = int.parse(range[0].trim());
          final min = int.parse(range[1].trim());
          configData.setRange(max, min);
        } catch (e) {
          throw const FormatException("invalid command range");
        }
      } else if (line.contains("button text")) {
        configData.modes = fieldText
            .split(",")
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
      }
    }
    // settings tables
    else {
      String errorMessage = "invalid ";
      final fields = line.split("||");
      try {
        switch (fields.length) {
          case (_telemetryFields):
            if (line.startsWith("index") == false) {
              errorMessage += "telemetry ${fields.first}";
              configData.telemetry.add(parseTelemetry(line));
            }
            break;

          case (_statusFields):
            if (line.startsWith("index") == false) {
              errorMessage += "status ${fields.first}";
              final statusFields = parseStatus(line);
              configData.status.createField(statusFields[0], statusFields[1]);
            } else if (fields[1].contains("bit name (")) {
              final startIndex = fields[1].indexOf("(") + 1;
              final endIndex = fields[1].indexOf(")");
              configData.status.stateName =
                  fields[1].substring(startIndex, endIndex).trim();

              for (int i = 0; i < configData.telemetry.length; i++) {
                if (configData.telemetry[i].name ==
                    configData.status.stateName) {
                  configData.status.stateIndex = i;
                  break;
                }
              }
            }
            break;

          case (_parameterFields):
            if (line.startsWith("index") == false) {
              errorMessage += "parameter ${fields.first}";
              configData.parameter.add(parseParameter(line));
            }
            break;

          default:
            break;
        }
      } catch (e) {
        throw FormatException(errorMessage);
      }
    }
  }

  for (var element in configData.parameter) {
    element.currentValue = element.fileValue;
  }
  return configData;
}

ConfigData mergeExistingParameters(ConfigData newConfig, ConfigData oldConfig) {
  if (newConfig.parameter.isNotEmpty &&
      newConfig.parameter.length == oldConfig.parameter.length) {
    for (int i = 0; i < newConfig.parameter.length; i++) {
      newConfig.parameter[i].deviceValue = oldConfig.parameter[i].deviceValue;
      newConfig.parameter[i].connectedValue =
          oldConfig.parameter[i].connectedValue;
    }
  }
  return newConfig;
}

Telemetry parseTelemetry(String line) {
  final fields = parseFields(line);
  final telemetry = Telemetry(
    fields[_telemetryNameIndex],
    double.parse(fields[_telemetryStateMaxIndex]),
    double.parse(fields[_telemetryStateMinIndex]),
    double.parse(fields[_telemetryRatioIndex]),
    _colorMap[fields[_telemetryColorIndex]] ??
        (throw const FormatException("invalid color")),
    fields[_telemetryDisplayIndex].contains(true.toString()),
  );
  return telemetry;
}

List parseStatus(String line) {
  final fields = parseFields(line);
  return [fields[_statusNameIndex], int.parse(fields[_statusBitsIndex])];
}

Parameter parseParameter(String line) {
  final byteData = ByteData(4);
  final parameter = Parameter();
  final fields = parseFields(line);
  final fieldType = "ParameterType.${fields[_parameterTypeIndex]}";

  parameter.name = fields[_parameterNameIndex];
  if (fieldType == ParameterType.long.toString()) {
    parameter.type = ParameterType.long;
    byteData.setInt32(0, int.parse(fields[_parameterValueIndex]));
    parameter.fileValue = byteData.getInt32(0);
  } else if (fieldType == ParameterType.float.toString()) {
    parameter.type = ParameterType.float;
    byteData.setFloat32(0, double.parse(fields[_parameterValueIndex]));
    parameter.fileValue = byteData.getInt32(0);
  } else {
    throw const FormatException("invalid type");
  }
  return parameter;
}

List<String> parseFields(String line) {
  int lineIndex;
  final List<String> fields = List.empty(growable: true);
  while (true) {
    lineIndex = line.indexOf(_configDelimiter);
    if (lineIndex > 0) {
      fields.add(line.substring(0, lineIndex).trim());
      line = line.substring(lineIndex + _configDelimiter.length);
    } else {
      fields.add(line.trim());
      break;
    }
  }
  return fields;
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
  writer.write(parseDataHeaders(configData, UsbParse.stateRequest));
  await writer.flush();
  writer.writeAll(
      DataRowIterable(configData, UsbParse.stateRequest, true, dataLines));
  await writer.close();
  if (!saveByteFile) {
    await rawDataFile.delete();
  }
  return Object();
}

class DataRowIterable extends Iterable<String> {
  final List<String> dataLines;
  final ConfigData configData;
  final int requestedStates;
  final bool parseStatus;

  DataRowIterable(
      this.configData, this.requestedStates, this.parseStatus, this.dataLines);

  @override
  Iterator<String> get iterator =>
      DataRowIterator(configData, requestedStates, parseStatus, dataLines);
}

class DataRowIterator implements Iterator<String> {
  final List<String> dataLines;
  final ConfigData configData;
  final int requestedStates;
  final bool parseStatus;

  DataRowIterator(
      this.configData, this.requestedStates, this.parseStatus, this.dataLines);

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
        final timeDiff = parseTimeDiff(configData, timeCurrent, _timePrevious);
        _timePrevious = timeCurrent;
        _timeStamp += timeDiff;
        _current = parseDataRow(
            configData, requestedStates, parseStatus, _timeStamp, bytes);
      }
    }
    return true;
  }
}

String parseDataHeaders(ConfigData configData, int requestedStates) {
  String headerData = "time(ms), mode, ";
  for (int i = 0; i < configData.telemetry.length; i++) {
    if ((requestedStates & (1 << i)) != 0) {
      headerData += "${configData.telemetry[i].name}, ";
    }
  }
  // the status object is initialized and the corresponding state is selected
  if (configData.status.numFields > 0 &&
      (requestedStates & (1 << configData.status.stateIndex) != 0)) {
    for (int i = 0; i < configData.status.numFields; i++) {
      headerData += "${configData.status.fieldName(i)}, ";
    }
  }
  headerData += newline;
  return headerData;
}

int parseTimeDiff(ConfigData configData, int timeCurrent, int timePrevious) {
  int timeDiff = 0;
  if (timeCurrent >= timePrevious) {
    timeDiff = timeCurrent - timePrevious;
  } else {
    timeDiff = timeCurrent + (UsbParse.timestampRollover - timePrevious);
  }
  return timeDiff;
}

String parseDataRow(ConfigData configData, int requestedStates,
    bool parseStatus, int timeStamp, List<int> bytes) {
  String rowText = "";

  int stateIndex = 0;
  final stateValues = List.filled(configData.telemetry.length, 0.0);
  final byteData = ByteData(4);

  // convert a row of bytes into 32-bit integers
  for (int i = 0; i < configData.telemetry.length; i++) {
    int startIndex = UsbParse.dataStartIndex + (4 * stateIndex);
    // if the specific state is being requested
    if ((requestedStates & (1 << i)) != 0) {
      byteData.setUint8(0, bytes[startIndex]);
      byteData.setUint8(1, bytes[startIndex + 1]);
      byteData.setUint8(2, bytes[startIndex] + 2);
      byteData.setUint8(3, bytes[startIndex] + 3);
      if (configData.telemetry[i].ratio == 0) {
        stateValues[i] = byteData.getFloat32(0);
      } else {
        stateValues[i] =
            byteData.getInt32(0).toDouble() * configData.telemetry[i].ratio;
      }
      ++stateIndex;
    }
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
    final type = (parameter.type == ParameterType.long) ? "long" : "float";
    inputText += "  /*${index++}*/ $type ${parameter.name};$newline";
  }

  inputText += "} PARAMETER;$newline$newline";
  inputText += "extern PARAMETER P;$newline$newline";
  inputText += "#endif /* PARAMETERS_H_ */$newline";

  return inputText;
}
