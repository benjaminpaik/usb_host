import 'package:flutter/material.dart';
import '../misc/config_data.dart';

class ParameterTableModel extends ChangeNotifier {

  final ConfigData _configData;
  List<bool> _rowSelection = <bool>[];

  ParameterTableModel(this._configData);

  void initRows() {
    _rowSelection = List.filled(_configData.parameter.length, false);
    notifyListeners();
  }

  void updateTable() {
    notifyListeners();
  }

  void selectRow(int index, bool? selected) {

    if(index < _rowSelection.length) {
      _rowSelection[index] = selected ?? false;
    }
    notifyListeners();
  }

  bool rowSelected(int index) {
    if(index < _rowSelection.length) {
      return _rowSelection[index];
    }
    else {
      return false;
    }
  }

  int get numRows {
    return _configData.parameter.length;
  }

  void copyFileParameters() {
    for (int i = 0; i < numRows; i++) {
      if (rowSelected(i) && _configData.parameter[i].fileValue != null) {
        _configData.parameter[i].currentValue =
            _configData.parameter[i].fileValue;
      }
    }
    notifyListeners();
  }

  void copyConnectedParameters() {
    for (int i = 0; i < numRows; i++) {
      if (rowSelected(i) && _configData.parameter[i].connectedValue != null) {
        _configData.parameter[i].currentValue =
            _configData.parameter[i].connectedValue;
      }
    }
    notifyListeners();
  }

  String parameterName(int index) {
    if(index >= 0 && index < _configData.parameter.length) {
      return _configData.parameter[index].name;
    }
    else {
      return "";
    }
  }

  String getCurrentText(int index) {
    if(index >= 0 && index < _configData.parameter.length) {
      return _configData.parameter[index].currentString;
    }
    else {
      return "";
    }
  }

  void setCurrentText(int index, String text) {
    if(index >= 0 && index < _configData.parameter.length) {
      _configData.parameter[index].setCurrentFromText(text);
    }
  }

  String getFileText(int index) {
    if(index >= 0 && index < _configData.parameter.length) {
      return _configData.parameter[index].fileString;
    }
    else {
      return "";
    }
  }

  String getConnectedText(int index) {
    if(index >= 0 && index < _configData.parameter.length) {
      return _configData.parameter[index].connectedString;
    }
    else {
      return "";
    }
  }

}
