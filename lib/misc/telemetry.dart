import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

enum TelemetryKeys {
  name,
  value,
  max,
  min,
  ratio,
  color,
  display,
}

enum StatusBitKeys {
  names,
  numBits,
  bitOffset,
  bitMask,
  stateName,
  stateIndex,
  value,
}

class Telemetry {
  final _numberFormatter = NumberFormat("0.####");
  final String _name;
  final double _max, _min, _range, _ratio;
  double _value = 0;
  String _scaledValue = "0";
  bool displayed = false;
  Color color = Colors.black;

  Telemetry(
      this._name, this._max, this._min, this._ratio, this.color, this.displayed)
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

  double get ratio {
    return _ratio;
  }

  void setBitValue(int bitValue) {
    if (_ratio == 0.0) {
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
    if (_ratio == 0.0) {
      _scaledValue = _numberFormatter.format(_value);
    } else {
      _scaledValue = _numberFormatter.format(_value * _ratio);
    }
  }

  String get scaledValue {
    return _scaledValue;
  }

  Map<TelemetryKeys, dynamic> toMap() {
    return {
      TelemetryKeys.name: name,
      TelemetryKeys.value: _value,
      TelemetryKeys.max: _max,
      TelemetryKeys.min: _min,
      TelemetryKeys.ratio: ratio,
      TelemetryKeys.color: color,
      TelemetryKeys.display: displayed,
    };
  }

  static Telemetry fromMap(Map<TelemetryKeys, dynamic> map) {
    return Telemetry(map[TelemetryKeys.name], map[TelemetryKeys.max], map[TelemetryKeys.min], map[TelemetryKeys.ratio],
        map[TelemetryKeys.color], map[TelemetryKeys.display]);
  }

  @override
  String toString() {
    return toMap().toString();
  }
}

class BitStatus {
  final _names = List<String>.empty(growable: true);
  final _numBits = List<int>.empty(growable: true);
  final _bitOffset = List<int>.empty(growable: true);
  final _bitMask = List<int>.empty(growable: true);
  // String selectedField = "";
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

  Map<StatusBitKeys, dynamic> toMap() {
    return {
      StatusBitKeys.names: _names,
      StatusBitKeys.numBits: _numBits,
      StatusBitKeys.bitOffset: _bitOffset,
      StatusBitKeys.bitMask: _bitMask,
      StatusBitKeys.stateName: stateName,
      StatusBitKeys.stateIndex: stateIndex,
      StatusBitKeys.value: _value,
    };
  }

  static BitStatus fromMap(Map<StatusBitKeys, dynamic> map) {
    final bitStatus = BitStatus();

    (map[StatusBitKeys.names] as Map<StatusBitKeys, String>).forEach((key, value) {
      bitStatus._names.add(value);
    });

    (map[StatusBitKeys.numBits] as Map<StatusBitKeys, int>).forEach((key, value) {
      bitStatus._numBits.add(value);
    });

    (map[StatusBitKeys.bitOffset] as Map<StatusBitKeys, int>).forEach((key, value) {
      bitStatus._bitOffset.add(value);
    });

    (map[StatusBitKeys.bitMask] as Map<StatusBitKeys, int>).forEach((key, value) {
      bitStatus._bitMask.add(value);
    });

    bitStatus.stateName = map[StatusBitKeys.stateName];
    bitStatus.stateIndex = map[StatusBitKeys.stateIndex];
    bitStatus._value = map[StatusBitKeys.value];

    return bitStatus;
  }

  @override
  String toString() {
    return toMap().toString();
  }
}
