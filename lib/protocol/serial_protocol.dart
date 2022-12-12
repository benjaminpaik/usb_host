import 'dart:async';
import 'dart:ffi';
import 'package:hidapi_dart/hid.dart';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:usb_host/misc/file_utilities.dart';
import 'serial_parse.dart';

enum SerialKeys {
  running,
  dataFile,
  recordState,
}

const _initConfigData = {
  SerialKeys.running: false,
  SerialKeys.dataFile: "",
  SerialKeys.recordState: RecordState.disabled,
};

class SerialApi {
  final applicationPath = Directory.current;
  final txBytes = Uint8List(SerialParse.usbHidBytes);
  final _rxBytes = Uint8List(SerialParse.usbHidBytes);
  int _checksumErrors = 0;
  Completer<SendPort> _sendPortCompleter = Completer<SendPort>();
  SendPort? _sendPort;
  final ReceivePort _receivePort;
  // clone initial config data
  final _configData = {..._initConfigData};
  var _watchdogTripped = false;
  bool get watchdogTripped => _watchdogTripped;

  SerialApi() : _receivePort = ReceivePort() {
    SerialParse.crc16Generate();
    SerialParse.crc32Generate();
    _receivePort.listen(receiveDataEvent);
    txBytes[SerialParse.commandModeIndex] = 0;
    txBytes[SerialParse.timestampIndex] = 0;
  }

  set dataFile(String file) {
    if (_sendPort != null) {
      _configData[SerialKeys.dataFile] = file;
      _sendPort!.send({SerialKeys.dataFile: file});
    }
  }

  String get dataFile {
    return _configData[SerialKeys.dataFile] as String;
  }

  set recordState(RecordState state) {
    if (_sendPort != null) {
      _configData[SerialKeys.recordState] = state;
      _sendPort!.send({SerialKeys.recordState: state});
    }
  }

  RecordState get recordState {
    return _configData[SerialKeys.recordState] as RecordState;
  }

  void receiveDataEvent(dynamic data) {
    if (data is List<int>) {
      for (int i = 0; i < _rxBytes.length; i++) {
        _rxBytes[i] = data[i];
      }
    } else if (data is Map) {
      for (SerialKeys key in data.keys) {
        if (_configData.containsKey(key)) {
          _configData[key] = data[key];
        }
      }
    } else if (data is int) {
      _checksumErrors = data;
    } else if (data is SendPort) {
      _sendPortCompleter.complete(data);
    }
  }

  Future<void> connect() async {
    // set the current directory so the DLL is loaded correctly
    Directory.current = applicationPath;
    await Isolate.spawn(_commIsolate, _receivePort.sendPort);
    _sendPortCompleter = Completer<SendPort>();
    _sendPort = await _sendPortCompleter.future;

    if (_sendPort != null) {
      _configData[SerialKeys.running] = true;
      _sendPort!.send(_configData);
      sendPacket();
    }
  }

  void closePort() {
    if (_sendPort != null) {
      _configData[SerialKeys.running] = false;
      _sendPort!.send(_configData);
    }
  }

  void sendPacket() {
    if (_sendPort != null) {
      _sendPort!.send(txBytes);
    }
  }

  void startWatchdog(int timeout) {
    _watchdogTripped = false;
    Timer(Duration(milliseconds: timeout), () {
      _watchdogTripped = true;
    });
  }

  int get checksumErrors {
    return _checksumErrors;
  }

  Uint8List get rxBytes {
    return _rxBytes;
  }

  bool get isRunning {
    return _configData[SerialKeys.running] as bool;
  }
}

class _SerialProtocol {
  int errorCount = 0;
  final _txBytes = Uint8List(SerialParse.usbHidBytes + 1);
  final _rxBytes = Uint8List(SerialParse.usbHidBytes);
  var _hid = HID();

  _SerialProtocol() {
    SerialParse.crc16Generate();
    SerialParse.crc32Generate();
    // initialize TX bytes
    _txBytes[SerialParse.commandModeIndex + 1] = 0;
    _txBytes[SerialParse.timestampIndex + 1] = 0;
  }

  Future<bool> connect() async {
    String? serial;
    _hid = HID(idVendor: SerialParse.vendorId, idProduct: SerialParse.productId, serial: serial);
    return (_hid.open() >= 0);
  }

  void closePort() {
    _hid.close();
  }

  Future<int> _txProtocol() async {
    int bytesSent = 0;
    _txBytes[SerialParse.timestampIndex + 1]++;
    await _hid.write(_txBytes).then((value) {
      bytesSent = value;
    });
    return bytesSent;
  }

  Future<bool> _rxProtocol() async {
    bool success = false;
    final hidRead = await _hid.read();
    if(hidRead != null) {
      for(int i = 0; i < hidRead.length; i++) {
        _rxBytes[i] = hidRead[i];
      }
      success = true;
    }
    return success;
  }

  void loadTxData(List<int> data) {
    for (int i = 0; i < SerialParse.usbHidBytes; i++) {
      _txBytes[i + 1] = data[i];
    }
  }
}

Future<void> _commIsolate(SendPort sendPort) async {
  IOSink? writer;
  _SerialProtocol serial = _SerialProtocol();
  final configData = {..._initConfigData};

  final receivePort = ReceivePort();
  sendPort.send(receivePort.sendPort);

  receivePort.listen((data) {
    bool openClosePort = false;
    // TX bytes input
    if (data is List<int>) {
      serial.loadTxData(data);
    } else if (data is Map) {
      // load all config data
      for (SerialKeys key in data.keys) {
        if (configData.containsKey(key)) {
          // special actions for received maps
          switch (key) {

            case (SerialKeys.running):
              openClosePort = (configData[key] != data[key]);
              break;

            case (SerialKeys.recordState):
              if (data[key] == RecordState.inProgress) {
                final dataFile = configData[SerialKeys.dataFile] as String;
                if (dataFile.isNotEmpty) {
                  writer = File(dataFile).openWrite();
                }
              } else {
                writer?.close();
              }
              break;

            default:
              break;
          }
          configData[key] = data[key];
        }
      }
      // open and close COM port based on running key
      if (openClosePort) {
        if (configData[SerialKeys.running] == true) {
          serial.connect().then((connected) {
            configData[SerialKeys.running] = connected;
            sendPort.send({SerialKeys.running: configData[SerialKeys.running]});
          });
        } else {
          serial.closePort();
          receivePort.close();
        }
      }
    }
  });

  while (configData[SerialKeys.running] == false) {
    // yield to the listener
    await Future.delayed(Duration.zero);
  }

  while (configData[SerialKeys.running] == true) {
    final bytesSent = await serial._txProtocol();
    if(bytesSent >= 0) {
      if (await serial._rxProtocol()) {
        sendPort.send(serial._rxBytes);
        if (configData[SerialKeys.recordState] == RecordState.inProgress) {
          writer?.write(serial._rxBytes.toString() + newline);
        }
      }
    }
    // yield to the listener
    await Future.delayed(Duration.zero);
  }
}

DynamicLibrary loadLibrary() {
  if (Platform.isWindows) {
    return DynamicLibrary.open(
        '${Directory.current.path}\\libusb\\libusb-1.0.dll');
  }
  if (Platform.isMacOS) {
    return DynamicLibrary.open(
        '${Directory.current.path}/libusb/libusb-1.0.dylib');
  } else if (Platform.isLinux) {
    return DynamicLibrary.open(
        '${Directory.current.path}/libusb/libusb-1.0.so');
  }
  throw 'libusb dynamic library not found';
}
