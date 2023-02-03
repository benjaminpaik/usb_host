import 'package:flutter/material.dart';

class ScreenModel extends ChangeNotifier {

  int _screenIndex = 0;

  int get screenIndex {
    return _screenIndex;
  }

  set screenIndex(int index) {
    _screenIndex = index;
    notifyListeners();
  }
}
