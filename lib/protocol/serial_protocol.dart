import 'dart:async';
import 'dart:ffi';
import 'package:ffi/ffi.dart' show malloc;
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:usb_host/misc/file_utilities.dart';
import 'package:libusb/libusb32.dart';
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
  final _txBytes = malloc<Uint8>(SerialParse.usbHidBytes);
  final _rxBytes = malloc<Uint8>(SerialParse.usbHidBytes);
  final _rxTemp = Uint8List(SerialParse.usbHidBytes);
  final _dummy = malloc<Int32>(1);
  final libusb = Libusb(loadLibrary());
  Pointer<libusb_device_handle>? devHandle;

  _SerialProtocol() {
    SerialParse.crc16Generate();
    SerialParse.crc32Generate();
    // initialize TX bytes
    _txBytes[SerialParse.commandModeIndex] = 0;
    _txBytes[SerialParse.timestampIndex] = 0;

    if (libusb.libusb_init(nullptr) < 0) {
      throw Exception("failed to load library");
    }
  }

  void destructor() {
    malloc.free(_txBytes);
  }

  Future<bool> connect() async {
    devHandle = libusb.libusb_open_device_with_vid_pid(
        nullptr, SerialParse.vendorId, SerialParse.productId);

    if(devHandle != null) {
      libusb.libusb_detach_kernel_driver(devHandle!, 0);
      final result = libusb.libusb_claim_interface(devHandle!, 0);
      print("result: $result");
    }

    return (devHandle != nullptr);
  }

  void closePort() {
    if (devHandle != null) {
      libusb.libusb_close(devHandle!);
      libusb.libusb_exit(nullptr);
    }
  }

  int _txProtocol() {
    int bytesSent = 0;
    _txBytes[SerialParse.timestampIndex]++;
    // write bytes to the serial tx buffer
    if (devHandle != null) {
      bytesSent = libusb.libusb_control_transfer(
          devHandle!,
          SerialParse.ctrlOut,
          SerialParse.hidSetReport,
          (SerialParse.hidReportTypeOutput << 8) | 0x00,
          0,
          _txBytes,
          SerialParse.usbHidBytes,
          1000);

      // bytesSent = libusb.libusb_interrupt_transfer(
      //     devHandle!,
      //     0x00,
      //     _txBytes,
      //     SerialParse.usbHidBytes,
      //     _dummy,
      //     1000);
    }
    return bytesSent;
  }

  bool _rxProtocol() {
    int result = -1;
    if(devHandle != null) {
      result = libusb.libusb_control_transfer(
          devHandle!,
          SerialParse.ctrlIn,
          SerialParse.hidGetReport,
          (SerialParse.hidReportTypeInput << 8) | 0x00,
          0,
          _rxBytes,
          SerialParse.usbHidBytes,
          1000);

      // result = libusb.libusb_interrupt_transfer(
      //     devHandle!,
      //     0x80,
      //     _rxBytes,
      //     SerialParse.usbHidBytes,
      //     _dummy,
      //     5000);
      // print("result: $result transferred: ${_dummy[0]}");


      for(int i = 0; i < 64; i++) {
        _rxTemp[i] = _rxBytes[i];
      }
      print("rx: ${_rxTemp.toString()}");
    }
    return (result >= 0);
  }

  void loadTxData(List<int> data) {
    for (int i = 0; i < SerialParse.usbHidBytes; i++) {
      _txBytes[i] = data[i];
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
    final bytesSent = serial._txProtocol();
    if(bytesSent >= 0) {
      if (serial._rxProtocol()) {
        final rxBytes = Uint8List(SerialParse.usbHidBytes);
        for(int i = 0; i < SerialParse.usbHidBytes; i++) {
          rxBytes[i] = serial._rxBytes[i];
        }

        sendPort.send(rxBytes);
        if (configData[SerialKeys.recordState] == RecordState.inProgress) {
          writer?.write(rxBytes.toString() + newline);
        }
      }
    }
    // yield to the listener
    await Future.delayed(Duration.zero);
  }
  // free memory
  serial.destructor();
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
