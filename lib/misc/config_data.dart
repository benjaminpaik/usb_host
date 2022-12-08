
import 'package:usb_host/misc/parameter.dart';
import 'package:usb_host/misc/telemetry.dart';

enum ConfigDataKeys {
  commandMax,
  commandMin,
  modes,
  telemetry,
  status,
  parameter,
}

class ConfigData {
  bool initialized = false;
  int _commandMax = 1000,
      _commandMin = -1000;
  List<String> modes = List.empty(growable: true);
  List<Telemetry> telemetry = List.empty(growable: true);
  BitStatus status = BitStatus();
  List<Parameter> parameter = List.empty(growable: true);

  void setRange(int max, int min) {
    if (max > min) {
      _commandMax = max;
      _commandMin = min;
    } else {
      throw FormatException;
    }
  }

  int get commandMax {
    return _commandMax;
  }

  int get commandMin {
    return _commandMin;
  }

  Map<ConfigDataKeys, dynamic> toMap() {
    return {
      ConfigDataKeys.commandMax: _commandMax,
      ConfigDataKeys.commandMin: _commandMin,
      ConfigDataKeys.modes: modes,
      ConfigDataKeys.telemetry: telemetry,
      ConfigDataKeys.status: status,
      ConfigDataKeys.parameter: parameter,
    };
  }

  static ConfigData fromMap(Map<ConfigDataKeys, dynamic> map) {
    return ConfigData()
      .._commandMax = map[ConfigDataKeys.commandMax]
      .._commandMin = map[ConfigDataKeys.commandMin]
      ..modes = map[ConfigDataKeys.modes]
      ..telemetry = map[ConfigDataKeys.telemetry]
      ..status = map[ConfigDataKeys.status]
      ..parameter = map[ConfigDataKeys.parameter];
  }

}
