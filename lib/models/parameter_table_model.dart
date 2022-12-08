import 'package:flutter/material.dart';

class ParameterTableModel extends ChangeNotifier {

  List<bool> _rowSelection = <bool>[];
  String cellText = "";

  void initNumParameters(int numParameters) {
    _rowSelection = List.filled(numParameters, false);
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
}
