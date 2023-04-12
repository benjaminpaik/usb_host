

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:usb_host/models/screen_model.dart';
import 'package:usb_host/screens/parameter_screen.dart';
import 'package:usb_host/screens/status_screen.dart';

import '../widgets/bottom_navigation.dart';
import '../widgets/topbar.dart';
import 'control_screen.dart';

class HomeRoute extends StatelessWidget {

  const HomeRoute({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final appBody = Selector<ScreenModel, int>(
      selector: (_, selectorModel) => selectorModel.screenIndex,
      builder: (context, screenIndex, child) {
        return switch(screenIndex) {
          0 => const ControlPage(),
          1 => const ParameterPage(),
          _ => const StatusPage(),
        };
      },
    );

    return Scaffold(
      appBar: AppBar(
        title: const TopBar(),
      ),
      body: appBody,
      bottomNavigationBar: const BottomNavigation(),
    );
  }
}