import 'dart:typed_data';

import 'package:intl/intl.dart';

enum ParameterType {
  int,
  float,
}

enum ParameterKeys {
  name,
  type,
  currentValue,
  fileValue,
  connectedValue,
  deviceValue,
}

class Parameter {
  String name = "";
  ParameterType type = ParameterType.int;
  int? currentValue;
  int? fileValue;
  int? connectedValue;
  int? deviceValue;

  void setCurrentFromText(String text) {
    final byteData = ByteData(4);

    try {
      final value = double.parse(text);
      if (type == ParameterType.float) {
        byteData.setFloat32(0, value);
      } else {
        byteData.setInt32(0, value.toInt());
      }
      currentValue = byteData.getInt32(0);
    } catch (_) {}
  }

  String get currentString {
    return parameterToString(type, currentValue);
  }

  String get fileString {
    return parameterToString(type, fileValue);
  }

  String get connectedString {
    return parameterToString(type, connectedValue);
  }

  String get deviceString {
    return parameterToString(type, deviceValue);
  }

  Map<ParameterKeys, dynamic> toMap() {
    return {
      ParameterKeys.name: name,
      ParameterKeys.type: type,
      ParameterKeys.currentValue: currentValue,
      ParameterKeys.fileValue: fileValue,
      ParameterKeys.connectedValue: connectedValue,
      ParameterKeys.deviceValue: deviceValue,
    };
  }

  static Parameter fromMap(Map<ParameterKeys, dynamic> map) {
    return Parameter()
      ..name = map[ParameterKeys.name]
      ..type = map[ParameterKeys.type]
      ..currentValue = map[ParameterKeys.currentValue]
      ..fileValue = map[ParameterKeys.fileValue]
      ..connectedValue = map[ParameterKeys.connectedValue]
      ..deviceValue = map[ParameterKeys.deviceValue];
  }

  @override
  String toString() {
    return toMap().toString();
  }
}

String parameterToString(ParameterType type, int? value) {
  final byteData = ByteData(4);
  if (value != null) {
    if (type == ParameterType.float) {
      byteData.setInt32(0, value);
      final floatRound = double.parse(byteData.getFloat32(0).toStringAsPrecision(7));

      if (floatRound == 0.0 || (floatRound.abs() < 10000 && floatRound.abs() > 0.001)) {
        return NumberFormat("0.0#####").format(floatRound);
      }
      else {
        return NumberFormat("0.0###E0##").format(floatRound);
      }
    } else {
      return value.toString();
    }
  } else {
    return "";
  }
}
