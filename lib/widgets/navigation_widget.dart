import 'package:usb_host/misc/file_utilities.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/host_data_model.dart';
import '../models/parameter_table_model.dart';
import 'message_widget.dart';

const controlRoute = '/';
const parameterRoute = '/parameter';
const statusRoute = '/status';

class CustomNavigationDrawer extends StatelessWidget {
  const CustomNavigationDrawer({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: <Widget>[
          DrawerHeader(
            decoration: BoxDecoration(color: Theme.of(context).primaryColor),
            child: Text(
              'Menu',
              style: Theme.of(context).textTheme.displayLarge,
            ),
          ),
          ListTile(
            title: Text(
              'Control',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            onTap: () {
              Navigator.pushReplacementNamed(context, controlRoute);
            },
          ),
          ListTile(
            title: Text(
              'Parameter',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            onTap: () {
              Navigator.pushReplacementNamed(context, parameterRoute);
            },
          ),
          ListTile(
            title: Text(
              'Status',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            onTap: () {
              Navigator.pushReplacementNamed(context, statusRoute);
            },
          ),
        ],
      ),
    );
  }
}

class CustomMenuBar extends StatelessWidget {
  const CustomMenuBar({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final hostDataModel = Provider.of<HostDataModel>(context, listen: false);
    final parameterTableModel =
        Provider.of<ParameterTableModel>(context, listen: false);

    final saveFileMenuText = Selector<HostDataModel, bool>(
      selector: (_, selectorModel) =>
          selectorModel.configData.telemetry.isNotEmpty,
      builder: (context, fileLoaded, child) {
        return Text(
          "save file",
          style: TextStyle(
            color: fileLoaded ? null : Colors.grey,
          ),
        );
      },
    );

    final dataFileMenuText = Selector<HostDataModel, bool>(
      selector: (_, selectorModel) => selectorModel.usb.isRunning,
      builder: (context, running, child) {
        return Text(
          "create data file",
          style: TextStyle(
            color: running ? null : Colors.grey,
          ),
        );
      },
    );

    final fileMenuItems = [
      PopupMenuItem(
          child: const Text("open file"),
          onTap: () {
            hostDataModel.openConfigFile(() {
              if (hostDataModel.configData.initialized) {
                parameterTableModel.initNumParameters(
                    hostDataModel.configData.parameter.length);
              }
              displayMessage(context, hostDataModel.userMessage);
            });
          }),
      PopupMenuItem(
          child: saveFileMenuText,
          onTap: () {
            if (hostDataModel.configData.telemetry.isNotEmpty) {
              hostDataModel
                  .saveFile(generateConfigFile(hostDataModel.configData));
            }
          }),
      PopupMenuItem(
          child: dataFileMenuText,
          onTap: () {
            if (hostDataModel.usb.isRunning) {
              hostDataModel.createDataFile();
            }
          }),
    ];

    final toolsMenuItems = [
      PopupMenuItem(
          child: const Text("parse data"),
          onTap: () {
            hostDataModel.parseDataFile(
                true, () => displayMessage(context, hostDataModel.userMessage));
          }),
      PopupMenuItem(
        child: Row(
          children: [
            const Text("save byte file"),
            const Spacer(),
            Selector<HostDataModel, bool>(
              selector: (_, selectorModel) => selectorModel.saveByteFile,
              builder: (context, saveByteFile, child) {
                return Checkbox(
                    value: hostDataModel.saveByteFile,
                    onChanged: (bool? value) {
                      hostDataModel.saveByteFile = value ?? false;
                    });
              },
            ),
          ],
        ),
      ),
      PopupMenuItem(
          child: const Text("create header"),
          onTap: () {
            if (hostDataModel.configData.telemetry.isNotEmpty) {
              hostDataModel
                  .saveFile(generateHeaderFile(hostDataModel.configData));
            }
          }),
      PopupMenuItem(child: const Text("program target"), onTap: () {}),
    ];

    final fileMenu = Padding(
      padding: const EdgeInsets.all(8.0),
      child: PopupMenuButton(
        child: const Text("File"),
        itemBuilder: (context) => fileMenuItems,
      ),
    );

    final toolsMenu = Padding(
      padding: const EdgeInsets.all(8.0),
      child: PopupMenuButton(
        child: const Text("Tools"),
        itemBuilder: (context) => toolsMenuItems,
      ),
    );

    final recordButton = Padding(
      padding: const EdgeInsets.all(8.0),
      child: Selector<HostDataModel, RecordState>(
        selector: (_, selectorModel) => selectorModel.usb.recordState,
        builder: (context, recordState, child) {
          return IconButton(
              onPressed: () {
                hostDataModel.recordButtonEvent(() {
                  displayMessage(context, hostDataModel.userMessage);
                });
              },
              icon: recordState.icon);
        },
      ),
    );

    final connectButton = Padding(
      padding: const EdgeInsets.all(8.0),
      child: SizedBox(
        width: 110.0,
        child: ElevatedButton(
          child: Selector<HostDataModel, bool>(
            selector: (_, selectorModel) => selectorModel.usb.isRunning,
            builder: (context, isRunning, child) {
              return Text(isRunning ? "Disconnect" : "Connect");
            },
          ),
          onPressed: () {
            hostDataModel.usbConnect().then((success) {
              if (success) {
                parameterTableModel.updateTable();
              }
              displayMessage(context, hostDataModel.userMessage);
            });
          },
        ),
      ),
    );

    return Row(
      children: [
        fileMenu,
        toolsMenu,
        recordButton,
        const Spacer(),
        connectButton,
      ],
    );
  }
}
