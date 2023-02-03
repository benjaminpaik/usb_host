import 'package:usb_host/models/screen_model.dart';
import 'package:usb_host/screens/home_route.dart';
import 'package:flutter/material.dart';
import 'package:usb_host/models/host_data_model.dart';
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
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ScreenModel>(
            create: (context) => ScreenModel()),
        ChangeNotifierProvider<HostDataModel>(
            create: (context) => HostDataModel()),
        ChangeNotifierProvider<ParameterTableModel>(
            create: (context) => ParameterTableModel()),
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
            titleSmall: TextStyle(fontSize: 16.0, fontWeight: FontWeight.normal, color: Colors.black),
            displayLarge: TextStyle(fontSize: 25.0, fontWeight: FontWeight.normal, color: Colors.white),
            titleLarge: TextStyle(fontSize: 14.0, fontWeight: FontWeight.normal, color: Colors.black),
            titleMedium: TextStyle(fontSize: 14.0, fontWeight: FontWeight.normal, color: Colors.black),
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
