import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

enum TelemetryKeys {
  value,
  name,
  max,
  min,
  type,
  scale,
  color,
  display,
}

enum TelemetryType {
  int,
  float,
}

enum StatusBitKeys {
  state,
  fields,
}

enum StatusFieldKeys {
  name,
  bits,
}

const colorMap = {
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

final reverseColorMap = colorMap.map((k, v) => MapEntry(v, k));

class Telemetry {
  final _numberFormatter = NumberFormat("0.####");
  final String _name;
  final double _max, _min, _range, _scale;
  final TelemetryType _type;
  double _value = 0;
  String _scaledValue = "0";
  bool display = false;
  Color color = Colors.black;

  Telemetry(this._name, this._max, this._min, this._type, this._scale,
      this.color, this.display)
      : _range = (_max - _min) {
    if (range <= 0) {
      throw const FormatException("invalid range");
    }
  }

  String get name {
    return _name;
  }

  double get max {
    return _max;
  }

  double get min {
    return _min;
  }

  double get range {
    return _range;
  }

  TelemetryType get type {
    return _type;
  }

  double get scale {
    return _scale;
  }

  void setBitValue(int bitValue) {
    if (_type == TelemetryType.float) {
      final byteData = ByteData(4);
      byteData.setInt32(0, bitValue);
      _value = byteData.getFloat32(0);
    } else {
      _value = bitValue.toDouble();
    }
  }

  double get value {
    return _value;
  }

  void updateScaledValue() {
    _scaledValue = _numberFormatter.format(_value * _scale);
  }

  String get scaledValue {
    return _scaledValue;
  }

  String get typeString {
    return (type == TelemetryType.float) ? TelemetryType.float.name : TelemetryType.int.name;
  }

  String get colorString {
    final result = reverseColorMap[color];
    return result ?? colorMap.keys.first;
  }

  Map<TelemetryKeys, dynamic> toMap() {
    return {
      TelemetryKeys.value: _value,
      TelemetryKeys.name: _name,
      TelemetryKeys.max: _max,
      TelemetryKeys.min: _min,
      TelemetryKeys.type: _type,
      TelemetryKeys.scale: _scale,
      TelemetryKeys.color: color,
      TelemetryKeys.display: display,
    };
  }

  static Telemetry fromMap(Map<TelemetryKeys, dynamic> map) {
    return Telemetry(
        map[TelemetryKeys.name],
        map[TelemetryKeys.max],
        map[TelemetryKeys.min],
        map[TelemetryKeys.type],
        map[TelemetryKeys.scale],
        map[TelemetryKeys.color],
        map[TelemetryKeys.display]);
  }
}

class BitStatus {
  final _names = List<String>.empty(growable: true);
  final _numBits = List<int>.empty(growable: true);
  final _bitOffset = List<int>.empty(growable: true);
  final _bitMask = List<int>.empty(growable: true);
  String stateName = "";
  int stateIndex = 0;
  int _value = 0;

  void createField(String name, int bits) {
    if (bits > 0) {
      final bitOffset = (_bitOffset.isNotEmpty)
          ? _numBits.reduce((value, element) => value + element)
          : 0;
      final bitMask = ((1 << bits) - 1) << bitOffset;

      _names.add(name);
      _numBits.add(bits);
      _bitOffset.add(bitOffset);
      _bitMask.add(bitMask);
    } else {
      throw FormatException;
    }
  }

  void clear() {
    _names.clear();
    _numBits.clear();
    _bitOffset.clear();
    _bitMask.clear();
  }

  set value(int value) {
    _value = value;
  }

  int fieldValue(int index) {
    if (index >= 0 && index < _names.length) {
      return ((_value & _bitMask[index]) >> _bitOffset[index]);
    } else {
      throw FormatException;
    }
  }

  int get numFields {
    return _names.length;
  }

  String fieldName(int index) {
    if (index >= 0 && index < _names.length) {
      return _names[index];
    } else {
      throw FormatException;
    }
  }

  int numBits(int index) {
    if (index >= 0 && index < _names.length) {
      return _numBits[index];
    } else {
      throw FormatException;
    }
  }

  Map<String, dynamic> toMap() {
    final statusFieldsMap =
    List<Map<String, dynamic>>.generate(numFields, (int index) =>
    {
      StatusFieldKeys.name.name: fieldName(index),
      StatusFieldKeys.bits.name: numBits(index),
    });

    return {
      StatusBitKeys.state.name: stateName,
      StatusBitKeys.fields.name: statusFieldsMap,
    };
  }

  static BitStatus fromMap(Map<String, dynamic> map) {
    final status = BitStatus();

    var statusFields = <Map>[];
    // parse status settings
    try {
      statusFields = List<Map>.from(map[StatusBitKeys.fields.name]);
    } catch (e) {
      throw const FormatException("invalid status settings");
    }

    try {
      status.stateName = map[StatusBitKeys.state.name];
    } catch (e) {
      throw const FormatException("invalid status state");
    }

    for (int i = 0; i < statusFields.length; i++) {
      try {
        final statusFieldMap = statusFields[i];
        final statusFieldName = statusFieldMap[StatusFieldKeys.name.name];
        final statusFieldBits = statusFieldMap[StatusFieldKeys.bits.name];
        status.createField(statusFieldName, statusFieldBits);
      } catch (e) {
        throw FormatException("invalid status field at index $i");
      }
    }
    return status;
  }
}
