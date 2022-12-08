import 'dart:typed_data';
import 'package:libusb/libusb32.dart';
import 'package:usb_host/protocol/serial_protocol.dart';

class SerialParse {
  static const vendorId = 1155;
  static const productId = 22352;

  static const ctrlIn = libusb_endpoint_direction.LIBUSB_ENDPOINT_IN |
      libusb_request_type.LIBUSB_REQUEST_TYPE_CLASS |
      libusb_request_recipient.LIBUSB_RECIPIENT_INTERFACE;
  static const ctrlOut = libusb_endpoint_direction.LIBUSB_ENDPOINT_OUT |
      libusb_request_type.LIBUSB_REQUEST_TYPE_CLASS |
      libusb_request_recipient.LIBUSB_RECIPIENT_INTERFACE;

  static const hidGetReport = 0x01;
  static const hidGetIdle = 0x02;
  static const hidGetProtocol = 0x03;
  static const hidSetReport = 0x09;
  static const hidSetIdle = 0x0A;
  static const hidSetProtocol = 0x0B;

  static const hidReportTypeInput = 0x01;
  static const hidReportTypeOutput = 0x02;
  static const hidReportTypeFeature = 0x03;

  static const commandValueIndex = 0;
  static const parameterTableIndex = 0;
  static const programInfoIndex = 0;
  static const programDataIndex = 2;

  static const nullMode = 0xFF;
  static const readParameters = 17;
  static const writeParameters = 18;
  static const flashParameters = 19;
  static const reprogramBootMode = 30;
  static const normalBootMode = 31;
  static const eraseProgramFlash = 32;
  static const writeProgramFlash = 33;
  static const readProgramFlash = 34;

  static const usbHidBytes = 64;
  static const bytesPerState = 4;
  static const _checksumSeed = 0xFF;
  static const _crc16Seed = 0x1021;
  static const _crc32Seed = 0x04C11DB7;

  static const commandModeIndex = 0;
  static const timestampIndex = 1;
  static const dataStartIndex = 4;

  static const stateRequest = 0xFFFF;
  static const checksumBytes = 2;
  static const maxStates = 15;

  static final _crc16Table = List.filled(256, 0, growable: false);
  static final _crc32Table = List.filled(256, 0, growable: false);
  static const timestampRollover = 256;
  static const timestampHostThreshold = 200;

  static void setCommandMode(SerialApi serial, int mode) {
    serial.txBytes[commandModeIndex] = mode;
  }

  static int getCommandMode(SerialApi serial) {
    return serial.rxBytes[commandModeIndex];
  }

  static void setData16(SerialApi serial, int value, int index) {
    // starting index
    int offset = (2 * index) + dataStartIndex;
    // byte conversion
    serial.txBytes[offset] = (value >> 8) & 0xFF;
    serial.txBytes[offset + 1] = value & 0xFF;
  }

  static int getData16(SerialApi serial, int index) {
    final byteData = ByteData(2);
    int offset = (2 * index) + dataStartIndex;
    byteData.setUint8(1, serial.rxBytes[offset + 1]);
    byteData.setUint8(0, serial.rxBytes[offset + 0]);
    return byteData.getInt32(0);
  }

  static void setData32(SerialApi serial, int value, int index) {
    // starting index
    int offset = (4 * index) + dataStartIndex;
    // byte conversion
    serial.txBytes[offset] = (value >> 24) & 0xFF;
    serial.txBytes[offset + 1] = (value >> 16) & 0xFF;
    serial.txBytes[offset + 2] = (value >> 8) & 0xFF;
    serial.txBytes[offset + 3] = value & 0xFF;
  }

  static int getData32(SerialApi serial, int index) {
    final byteData = ByteData(4);
    int offset = (4 * index) + dataStartIndex;
    byteData.setUint8(3, serial.rxBytes[offset + 3]);
    byteData.setUint8(2, serial.rxBytes[offset + 2]);
    byteData.setUint8(1, serial.rxBytes[offset + 1]);
    byteData.setUint8(0, serial.rxBytes[offset + 0]);
    return byteData.getInt32(0);
  }

  static int xorChecksum(List<int> packet, int checksumIndex) {
    int checksum = _checksumSeed;
    for (int i = 0; i < checksumIndex; i++) {
      checksum ^= packet[i];
    }
    return checksum;
  }

  static int crc16Checksum(List<int> bytes, int crcLength) {
    int crc = 0xFFFF, index = 0;
    for (int i = 0; i < crcLength; i++) {
      index = ((crc >> 8) ^ bytes[i]) & 0xFF;
      crc = ((crc << 8) ^ _crc16Table[index]) & 0xFFFF;
    }
    return crc;
  }

  static int crc16Rx(List<int> bytes, int crcIndex) {
    return (bytes[crcIndex] << 8) | (bytes[crcIndex + 1]) & 0xFFFF;
  }

  static void crc16Generate() {
    // iterate through each element in the table
    for (int dividend = 0; dividend < _crc16Table.length; dividend++) {
      // move dividend byte to MSB of 16-bit CRC
      int currentByte = dividend << 8;
      // loop through each bit in a byte
      for (int bit = 0; bit < 8; bit++) {
        // check the MSB of the value
        if ((currentByte & 0x8000) != 0) {
          currentByte <<= 1;
          currentByte ^= _crc16Seed;
        } else {
          currentByte <<= 1;
        }
      }
      // store the CRC value in the CRC table
      _crc16Table[dividend] = currentByte & 0xFFFF;
    }
  }

  static int crc32Checksum(List<int> values) {
    // initialize the checksum
    int checksum = 0xFFFFFFFF;
    // loop over all parameters
    for (int i = 0; i < values.length; i++) {
      checksum = crc32Single(checksum, (values[i] >> 24) & 0xFF);
      checksum = crc32Single(checksum, (values[i] >> 16) & 0xFF);
      checksum = crc32Single(checksum, (values[i] >> 8) & 0xFF);
      checksum = crc32Single(checksum, (values[i]) & 0xFF);
    }
    return checksum;
  }

  static int crc32Single(int checksum, int byteValue) {
    // XOR-in next input byte into MSB of CRC for the new intermediate dividend
    int index = ((checksum ^ (byteValue << 24)) >> 24) & 0xFF;
    // Shift out the MSB used for division in the table and XOR with the remainder
    return ((checksum << 8) ^ _crc32Table[index]);
  }

  static void crc32Generate() {
    // iterate through each element in the table
    for (int dividend = 0; dividend < _crc32Table.length; dividend++) {
      // move dividend byte to MSB of 32-bit CRC
      int currentByte = dividend << 24;
      // loop through each bit in a byte
      for (int bit = 0; bit < 8; bit++) {
        // check the MSB of the value
        if ((currentByte & 0x80000000) != 0) {
          currentByte <<= 1;
          currentByte ^= _crc32Seed;
        } else {
          currentByte <<= 1;
        }
      }
      // store the CRC value in the CRC table
      _crc32Table[dividend] = currentByte & 0xFFFFFFFF;
    }
  }

  static List<int> get crc16Table {
    return _crc16Table;
  }

  static List<int> get crc32Table {
    return _crc32Table;
  }

  static int bitCount(int i) {
    i = i - ((i >> 1) & 0x55555555);
    i = (i & 0x33333333) + ((i >> 2) & 0x33333333);
    return ((((i + (i >> 4)) & 0x0F0F0F0F) * 0x01010101) & 0xFFFFFFFF) >> 24;
  }
}
