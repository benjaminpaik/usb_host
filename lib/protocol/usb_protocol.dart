import 'dart:async';
import 'package:hidapi_dart/hid.dart';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:usb_host/misc/file_utilities.dart';
import 'usb_parse.dart';

enum ProtocolKeys {
  running,
  dataFile,
  recordState,
}

const _initConfigData = {
  ProtocolKeys.running: false,
  ProtocolKeys.dataFile: "",
  ProtocolKeys.recordState: RecordState.disabled,
};

class UsbApi {
  final applicationPath = Directory.current;
  final txBytes = Uint8List(UsbParse.usbHidBytes);
  final _rxBytes = Uint8List(UsbParse.usbHidBytes);
  int _checksumErrors = 0;
  Completer<SendPort> _sendPortCompleter = Completer<SendPort>();
  SendPort? _sendPort;
  final ReceivePort _receivePort;
  // clone initial config data
  final _configData = {..._initConfigData};
  var _watchdogTripped = false;
  bool get watchdogTripped => _watchdogTripped;

  UsbApi() : _receivePort = ReceivePort() {
    UsbParse.crc16Generate();
    _receivePort.listen(receiveDataEvent);
    txBytes[UsbParse.commandModeIndex] = 0;
    txBytes[UsbParse.timestampIndex] = 0;
  }

  set dataFile(String file) {
    if (_sendPort != null) {
      _configData[ProtocolKeys.dataFile] = file;
      _sendPort!.send({ProtocolKeys.dataFile: file});
    }
  }

  String get dataFile {
    return _configData[ProtocolKeys.dataFile] as String;
  }

  set recordState(RecordState state) {
    if (_sendPort != null) {
      _configData[ProtocolKeys.recordState] = state;
      _sendPort!.send({ProtocolKeys.recordState: state});
    }
  }

  RecordState get recordState {
    return _configData[ProtocolKeys.recordState] as RecordState;
  }

  void receiveDataEvent(dynamic data) {
    if (data is List<int>) {
      for (int i = 0; i < _rxBytes.length; i++) {
        _rxBytes[i] = data[i];
      }
    } else if (data is Map) {
      for (ProtocolKeys key in data.keys) {
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
      _configData[ProtocolKeys.running] = true;
      _sendPort!.send(_configData);
      sendPacket();
    }
  }

  void closePort() {
    if (_sendPort != null) {
      _configData[ProtocolKeys.running] = false;
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
    return _configData[ProtocolKeys.running] as bool;
  }
}

class _UsbProtocol {
  int errorCount = 0;
  final _txBytes = Uint8List(UsbParse.usbHidBytes + 1);
  final _rxBytes = Uint8List(UsbParse.usbHidBytes);
  var _hid = HID();

  _UsbProtocol() {
    UsbParse.crc16Generate();
    // initialize TX bytes
    _txBytes[UsbParse.commandModeIndex + 1] = 0;
    _txBytes[UsbParse.timestampIndex + 1] = 0;
  }

  Future<bool> connect() async {
    String? serial;
    _hid = HID(idVendor: UsbParse.vendorId, idProduct: UsbParse.productId, serial: serial);
    return (_hid.open() >= 0);
  }

  void closePort() {
    _hid.close();
  }

  Future<int> _txProtocol() async {
    int bytesSent = 0;
    _txBytes[UsbParse.timestampIndex + 1]++;
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
    for (int i = 0; i < UsbParse.usbHidBytes; i++) {
      _txBytes[i + 1] = data[i];
    }
  }
}

Future<void> _commIsolate(SendPort sendPort) async {
  IOSink? writer;
  _UsbProtocol usb = _UsbProtocol();
  final configData = {..._initConfigData};

  final receivePort = ReceivePort();
  sendPort.send(receivePort.sendPort);

  receivePort.listen((data) {
    bool openClosePort = false;
    // TX bytes input
    if (data is List<int>) {
      usb.loadTxData(data);
    } else if (data is Map) {
      // load all config data
      for (ProtocolKeys key in data.keys) {
        if (configData.containsKey(key)) {
          // special actions for received maps
          switch (key) {

            case (ProtocolKeys.running):
              openClosePort = (configData[key] != data[key]);
              break;

            case (ProtocolKeys.recordState):
              if (data[key] == RecordState.inProgress) {
                final dataFile = configData[ProtocolKeys.dataFile] as String;
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
        if (configData[ProtocolKeys.running] == true) {
          usb.connect().then((connected) {
            configData[ProtocolKeys.running] = connected;
            sendPort.send({ProtocolKeys.running: configData[ProtocolKeys.running]});
          });
        } else {
          usb.closePort();
          receivePort.close();
        }
      }
    }
  });

  while (configData[ProtocolKeys.running] == false) {
    // yield to the listener
    await Future.delayed(Duration.zero);
  }

  while (configData[ProtocolKeys.running] == true) {
    final bytesSent = await usb._txProtocol();
    if(bytesSent >= 0) {
      if (await usb._rxProtocol()) {
        sendPort.send(usb._rxBytes);
        if (configData[ProtocolKeys.recordState] == RecordState.inProgress) {
          writer?.write(usb._rxBytes.toString() + newline);
        }
      }
    }
    // yield to the listener
    await Future.delayed(Duration.zero);
  }
}
