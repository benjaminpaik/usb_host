import 'package:flutter/material.dart';

const Color textColor = Colors.black;
const double standardFontSize = 12;
const buttonWidth = 150.0;
const buttonHeight = 50.0;

const parameterTimeout = 2500;

const parameterIndexHeader = "index";
const parameterNameHeader = "name";
const parameterCurrentHeader = "current";
const parameterFileHeader = "file";
const parameterConnectedHeader = "connected";
final parameterHeaders = [
  parameterIndexHeader,
  parameterNameHeader,
  parameterCurrentHeader,
  parameterFileHeader,
  parameterConnectedHeader
];

class _InfoMessage {
  final connected = "connection successful";
  final disconnected = "disconnection successful";
  final parseData = "generated parsed data file";
  final parameterGet = "parameter retrieval successful";
  final parameterWrite = "parameter send successful";
  final parameterFlash = "parameter flash successful";
  final bootloader = "bootloader initiated; disconnecting usb";
}

class _ErrorMessage {
  final connect = "could not connect to device";
  final parameterGet = "could not retrieve parameters";
  final parameterWrite = "could not send parameters";
  final parameterFlash = "could not flash parameters";
  final parameterNum = "could not get number of parameters";
  final parameterLengthMatch =
      "number of parameters on device does not match config";
  parameterUpdate(Iterable<String> mismatchParameters) {
    final mismatchString = mismatchParameters.toString();
    final mismatchStringFormatted =
        mismatchString.substring(1, mismatchString.length - 1);
    return "parameter(s) not updated: $mismatchStringFormatted";
  }

  final bootloader = "could not initiate bootloader";
}

class Message {
  static final info = _InfoMessage();
  static final error = _ErrorMessage();
}
