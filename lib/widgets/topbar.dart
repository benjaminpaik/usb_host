import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:usb_host/models/file_model.dart';
import 'package:usb_host/models/usb_model.dart';

import '../misc/file_utilities.dart';
import '../models/telemetry_model.dart';
import '../models/parameter_table_model.dart';
import 'message_widget.dart';

const _verticalPadding = 8.0;
const _horizontalPadding = 8.0;

class TopBar extends StatelessWidget {
  const TopBar({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final fileModel = Provider.of<FileModel>(context, listen: false);
    final telemetryModel = Provider.of<TelemetryModel>(context, listen: false);
    final parameterTableModel =
    Provider.of<ParameterTableModel>(context, listen: false);
    final usbModel = Provider.of<UsbModel>(context, listen: false);

    final openFileMenuItem = MenuItemButton(
        onPressed: () {
          fileModel.openConfigFile((bool success) {
            if (success) {
              telemetryModel.updatePlotDataFromConfig();
              parameterTableModel.initRows();
            }
            displayMessage(context, fileModel.userMessage);
          });
        },
        shortcut: const SingleActivator(LogicalKeyboardKey.keyO, control: true),
        child: const Text("open file"));

    final saveFileMenuItem = MenuItemButton(
      onPressed: () {
        fileModel.saveConfigFile();
      },
      shortcut: const SingleActivator(LogicalKeyboardKey.keyS, control: true),
      child: Selector<TelemetryModel, bool>(
        selector: (_, telemetryLoaded) => telemetryModel.telemetry.isNotEmpty,
        builder: (context, fileLoaded, child) {
          return Text(
            "save file",
            style: TextStyle(
              color: fileLoaded ? null : Colors.grey,
            ),
          );
        },
      ),
    );

    final createDataFileMenuItem = MenuItemButton(
      onPressed: () {
        if (usbModel.isRunning) {
          fileModel.createDataFile();
        }
      },
      shortcut: const SingleActivator(LogicalKeyboardKey.keyD, control: true),
      child: Selector<UsbModel, bool>(
        selector: (_, usbModel) => usbModel.isRunning,
        builder: (context, running, child) {
          return Text(
            "create data file",
            style: TextStyle(
              color: running ? null : Colors.grey,
            ),
          );
        },
      ),
    );

    final parseDataMenuItem = MenuItemButton(
        child: const Text("parse data"),
        onPressed: () {
          fileModel.parseDataFile(
              true, () => displayMessage(context, fileModel.userMessage));
        });

    final saveByteFileMenuItem = MenuItemButton(
      child: Row(
        children: [
          const Text("save byte file"),
          Selector<TelemetryModel, bool>(
            selector: (_, selectorModel) => fileModel.saveByteFile,
            builder: (context, saveByteFile, child) {
              return Checkbox(
                  value: fileModel.saveByteFile,
                  onChanged: (bool? value) {
                    fileModel.saveByteFile = value ?? false;
                  });
            },
          ),
        ],
      ),
      onPressed: () {},
    );

    final createHeaderMenuItem = MenuItemButton(
      onPressed: () {
        fileModel.saveHeaderFile();
      },
      shortcut: const SingleActivator(LogicalKeyboardKey.keyH, control: true),
      child: Selector<TelemetryModel, bool>(
        selector: (_, selectorModel) =>
        selectorModel.telemetry.isNotEmpty,
        builder: (context, fileLoaded, child) {
          return Text(
            "create header",
            style: TextStyle(
              color: fileLoaded ? null : Colors.grey,
            ),
          );
        },
      ),
    );

    final programTargetMenuItem = MenuItemButton(
      onPressed: () {
        usbModel.initBootloader().then((_) {
          if(context.mounted) {
            displayMessage(context, usbModel.userMessage);
          }
          usbModel.usbConnect();
        });
      },
      shortcut: const SingleActivator(LogicalKeyboardKey.keyP, control: true),
      child: const Text("program target"),
    );

    final fileMenu = [
      openFileMenuItem,
      saveFileMenuItem,
      createDataFileMenuItem,
    ];

    final toolsMenu = [
      parseDataMenuItem,
      saveByteFileMenuItem,
      createHeaderMenuItem,
      programTargetMenuItem,
    ];

    final recordButton = Selector<FileModel, RecordState>(
      selector: (_, selectorModel) => fileModel.recordState,
      builder: (context, recordState, child) {
        return IconButton(
            onPressed: () {
              fileModel.recordButtonEvent(() {
                displayMessage(context, fileModel.userMessage);
              });
            },
            icon: recordState.icon);
      },
    );

    final connectButton = Padding(
      padding: const EdgeInsets.symmetric(
          vertical: _verticalPadding, horizontal: _horizontalPadding),
      child: SizedBox(
        width: 120.0,
        child: ElevatedButton(
          child: Selector<UsbModel, bool>(
            selector: (_, usbModel) => usbModel.isRunning,
            builder: (context, isRunning, child) {
              return Text(isRunning ? "Disconnect" : "Connect");
            },
          ),
          onPressed: () {
            usbModel.usbConnect().then((success) {
              if (success) {
                parameterTableModel.updateTable();
                telemetryModel.startPlots();
              }
              if(context.mounted) {
                displayMessage(context, usbModel.userMessage);
              }
            });
          },
        ),
      ),
    );

    // combine items from both menus and register shortcuts
    _initShortcuts(context, [...fileMenu, ...toolsMenu]);

    return Row(
      children: [
        MenuBar(children: [
          SubmenuButton(menuChildren: fileMenu, child: const Text('File')),
          SubmenuButton(menuChildren: toolsMenu, child: const Text('Tools')),
          recordButton,
        ]),
        const Spacer(),
        connectButton,
      ],
    );
  }
}

void _initShortcuts(BuildContext context, List<MenuItemButton> menuItems) {
  if (ShortcutRegistry.of(context).shortcuts.isEmpty) {
    final validMenuItems = menuItems
        .where((item) => item.shortcut != null && item.onPressed != null);
    final shortcutMap = {
      for (final item in validMenuItems)
        item.shortcut!: VoidCallbackIntent(item.onPressed!)
    };
    ShortcutRegistry.of(context).addAll(shortcutMap);
  }
}
