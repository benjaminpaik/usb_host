
import 'package:usb_host/misc/config_data.dart';
import 'package:usb_host/models/file_model.dart';
import 'package:usb_host/models/screen_model.dart';
import 'package:usb_host/models/usb_model.dart';
import 'package:usb_host/protocol/usb_protocol.dart';
import 'package:usb_host/screens/home_route.dart';
import 'package:flutter/material.dart';
import 'package:usb_host/models/telemetry_model.dart';
import 'package:usb_host/models/parameter_table_model.dart';
import 'package:provider/provider.dart';

const homeRoute = '/';

void main() {
  runApp(const UsbHostApp());
}

class UsbHostApp extends StatelessWidget {
  const UsbHostApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // declare classes for dependency injection here
    final usbApi = UsbApi();
    final configData = ConfigData();

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ScreenModel>(
            create: (context) => ScreenModel()),
        ChangeNotifierProvider<TelemetryModel>(
            create: (context) => TelemetryModel(usbApi, configData)),
        ChangeNotifierProvider<FileModel>(
            create: (context) => FileModel(usbApi, configData)),
        ChangeNotifierProvider<ParameterTableModel>(
            create: (context) => ParameterTableModel(configData)),
        ChangeNotifierProvider<UsbModel>(
            create: (context) => UsbModel(usbApi, configData)),
      ],
      child: MaterialApp(
        title: 'USB Host',
        theme: ThemeData(
          useMaterial3: true,
          primaryColor: Colors.black,
          appBarTheme: const AppBarTheme(
            color: Colors.white,
            foregroundColor: Colors.black,
          ),
          textTheme: const TextTheme(
            titleSmall: TextStyle(
                fontSize: 16.0,
                fontWeight: FontWeight.normal,
                color: Colors.black),
            displayLarge: TextStyle(
                fontSize: 25.0,
                fontWeight: FontWeight.normal,
                color: Colors.white),
            titleLarge: TextStyle(
                fontSize: 14.0,
                fontWeight: FontWeight.normal,
                color: Colors.black),
            titleMedium: TextStyle(
                fontSize: 14.0,
                fontWeight: FontWeight.normal,
                color: Colors.black),
          ),
          colorScheme: ColorScheme.fromSwatch(primarySwatch: Colors.grey),
        ),
        initialRoute: homeRoute,
        routes: {
          homeRoute: (context) => const HomeRoute(),
        },
      ),
    );
  }
}
