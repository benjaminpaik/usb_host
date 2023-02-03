
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:usb_host/models/screen_model.dart';

class BottomNavigation extends StatelessWidget {

  const BottomNavigation({super.key});

  @override
  Widget build(BuildContext context) {

    final screenDataModel = Provider.of<ScreenModel>(context, listen: false);

    return Selector<ScreenModel, int>(
      selector: (_, selectorModel) => selectorModel.screenIndex,
      builder: (context, _, child) {
        return BottomNavigationBar(
          items: const <BottomNavigationBarItem>[
            BottomNavigationBarItem(
              icon: Icon(Icons.auto_graph),
              label: 'Control',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.account_tree_outlined),
              label: 'Parameters',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.notifications),
              label: 'Status',
            ),
          ],
          currentIndex: screenDataModel.screenIndex,
          selectedItemColor: Colors.green,
          onTap: (int index) {
            screenDataModel.screenIndex = index;
          },
        );
      },
    );
  }
}
