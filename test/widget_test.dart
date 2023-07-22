// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:usb_host/definitions.dart';
import 'package:usb_host/misc/parameter.dart';

void main() {

  test("Parameter value should be settable and gettable", () {
    final parameter = Parameter();

    // test floating point numbers
    const testInput1 = "3.14159";
    parameter.type = ParameterType.float;
    parameter.setCurrentFromText(testInput1);
    expect(parameter.currentString, testInput1);

    // test integers
    const testInput2 = "1234567";
    parameter.type = ParameterType.long;
    parameter.setCurrentFromText(testInput2);
    expect(parameter.currentString, testInput2);
  });

}
