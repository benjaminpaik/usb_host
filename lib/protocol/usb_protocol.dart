import 'dart:async';
import 'dart:ffi';
import 'package:ffi/ffi.dart' show malloc;
import 'package:libusb/libusb32.dart';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:usb_host/misc/file_utilities.dart';
import 'usb_parse.dart';

const _connectTimeout = 1000;

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
  var _watchdogTimer = Timer(const Duration(milliseconds: 1000), () { });
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
    _watchdogTimer.cancel();
    _watchdogTimer = Timer(Duration(milliseconds: timeout), () {
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
  final _txBytes = malloc<Uint8>(UsbParse.usbHidBytes);
  var _rxBytes = Uint8List(UsbParse.usbHidBytes);
  final Pointer<Uint8> _rxBuffer = malloc<Uint8>(UsbParse.maxRxBufferSize);
  final Pointer<Int32> _rxLength = malloc<Int32>(1);

  final libusb = Libusb(loadLibrary());
  Pointer<libusb_device_handle>? devHandle = nullptr;

  _UsbProtocol() {
    UsbParse.crc16Generate();
    // initialize TX bytes
    _txBytes[UsbParse.commandModeIndex] = 0;
    _txBytes[UsbParse.timestampIndex] = 0;
    // initialize RX buffer
    _rxBuffer
        .asTypedList(UsbParse.maxRxBufferSize)
        .fillRange(0, UsbParse.maxRxBufferSize, 0);
    if (libusb.libusb_init(nullptr) < 0) {
      throw Exception("failed to load library");
    }
  }

  bool findDevice(int vid, int pid) {
    final deviceListPtr = malloc<Pointer<Pointer<libusb_device>>>();
    bool deviceFound = false;
    if(libusb.libusb_get_device_list(nullptr, deviceListPtr) > 0) {
      final deviceList = deviceListPtr.value;
      final descPtr = malloc<libusb_device_descriptor>();
      final path = malloc<Uint8>(8);

      for (int i = 0; deviceList[i] != nullptr; i++) {
        final result = libusb.libusb_get_device_descriptor(deviceList[i], descPtr);
        if(result >= 0) {
          if(vid == descPtr.ref.idVendor && pid == descPtr.ref.idProduct) {
            deviceFound = true;
          }
        }
      }
      malloc.free(descPtr);
      malloc.free(path);
      libusb.libusb_free_device_list(deviceList, 1);
    }
    malloc.free(deviceListPtr);
    return deviceFound;
  }

  void destructor() {
    malloc.free(_txBytes);
    malloc.free(_rxBuffer);
    malloc.free(_rxLength);
  }

  bool connect() {
    if(findDevice(UsbParse.vendorId, UsbParse.productId)) {
      int error = 0;
      devHandle = libusb.libusb_open_device_with_vid_pid(
          nullptr, UsbParse.vendorId, UsbParse.productId);
      if (devHandle != null) {
        error = libusb.libusb_detach_kernel_driver(devHandle!, 0);
        error = libusb.libusb_claim_interface(devHandle!, UsbParse.interface);
        if (error < 0) {
          devHandle = nullptr;
          // final errorPointer = libusb.libusb_error_name(error);
          // final errorMessage = String.fromCharCodes(errorPointer.asTypedList(20));
        }
      }
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
    _txBytes[UsbParse.timestampIndex]++;
    if (devHandle != null) {
      bytesSent = libusb.libusb_control_transfer(
          devHandle!,
          UsbParse.ctrlOut,
          UsbParse.hidSetReport,
          (UsbParse.hidReportTypeOutput << 8) | 0x00,
          UsbParse.interface,
          _txBytes,
          UsbParse.usbHidBytes,
          UsbParse.transferTimeout);
    }
    return bytesSent;
  }

  bool _rxProtocol() {
    int result = -1;
    if (devHandle != null) {
      result = libusb.libusb_interrupt_transfer(
          devHandle!,
          UsbParse.interruptIn,
          _rxBuffer,
          UsbParse.usbHidBytes,
          _rxLength,
          UsbParse.transferTimeout);
      if (result >= 0) {
        _rxBytes = _rxBuffer.asTypedList(_rxLength[0]);
      }
    }
    return (result >= 0);
  }

  void loadTxData(List<int> data) {
    final txLength = (data.length < UsbParse.usbHidBytes)
        ? data.length
        : UsbParse.usbHidBytes;
    for (int i = 0; i < txLength; i++) {
      _txBytes[i] = data[i];
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
          final connected = usb.connect();
          configData[ProtocolKeys.running] = connected;
          sendPort.send({ProtocolKeys.running: configData[ProtocolKeys.running]});
        } else {
          usb.closePort();
          receivePort.close();
        }
      }
    }
  });

  bool tryConnect = true;
  Timer(const Duration(milliseconds: _connectTimeout), () {
    tryConnect = false;
  });

  while (configData[ProtocolKeys.running] == false && tryConnect) {
    // yield to the listener
    await Future.delayed(Duration.zero);
  }

  while (configData[ProtocolKeys.running] == true) {
    final bytesSent = usb._txProtocol();
    if (bytesSent >= 0) {
      if (usb._rxProtocol()) {
        sendPort.send(usb._rxBytes);
        if (configData[ProtocolKeys.recordState] == RecordState.inProgress) {
          writer?.write(usb._rxBytes.toString() + newline);
        }
      }
    }
    // yield to the listener
    await Future.delayed(Duration.zero);
  }
  // free memory
  usb.destructor();
}

DynamicLibrary loadLibrary() {
  String path = "";
  if (Platform.isWindows) {
    path = '${Directory.current.path}\\libusb\\libusb-1.0.dll';
  }
  else if (Platform.isMacOS) {
    path = '${Directory.current.path}/libusb/libusb-1.0.dylib';
  } else if (Platform.isLinux) {
    path = '${Directory.current.path}/libusb/libusb-1.0.so';
  }
  else {
    throw 'libusb dynamic library not found';
  }
  return DynamicLibrary.open(path);
}
