import 'package:usb_host/models/usb_model.dart';
import 'package:usb_host/widgets/message_widget.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../definitions.dart';
import 'package:usb_host/models/parameter_table_model.dart';

const parameterIndexHeader = "index";
const parameterNameHeader = "name";
const parameterCurrentHeader = "current";
const parameterFileHeader = "file";
const parameterConnectedHeader = "connected";
final parameterHeaders = [
  parameterIndexHeader,
  parameterNameHeader,
  parameterCurrentHeader,
  parameterFileHeader,
  parameterConnectedHeader
];

class ParameterPage extends StatelessWidget {
  static const String title = "Parameter";
  static Icon icon = const Icon(Icons.desktop_windows_outlined);

  const ParameterPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final usbModel = Provider.of<UsbModel>(context, listen: false);
    final parameterTableModel =
        Provider.of<ParameterTableModel>(context, listen: false);

    return Column(
      children: [
        const Expanded(
          flex: 5,
          child: Row(
            children: [
              ParameterTable(),
            ],
          ),
        ),
        Expanded(
          child: Row(
            children: [
              const Spacer(flex: 2),
              ElevatedButton(
                child: const Text("get parameters"),
                onPressed: () {
                  usbModel.getParametersUserSequence().then((success) {
                    if (success) {
                      parameterTableModel.updateTable();
                    }
                    if(context.mounted) {
                      displayMessage(context, usbModel.userMessage);
                    }
                  });
                },
              ),
              const Spacer(),
              ElevatedButton(
                child: const Text("send parameters"),
                onPressed: () {
                  usbModel.sendParameters().then((_) {
                    if(context.mounted) {
                      displayMessage(context, usbModel.userMessage);
                    }
                  });
                },
              ),
              const Spacer(),
              ElevatedButton(
                child: const Text("flash parameters"),
                onPressed: () {
                  usbModel.flashParameters().then((_) {
                    if(context.mounted) {
                      displayMessage(context, usbModel.userMessage);
                    }
                  });
                },
              ),
              const Spacer(flex: 2),
            ],
          ),
        ),
      ],
    );
  }
}

class ParameterTable extends StatelessWidget {
  const ParameterTable({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: Consumer<ParameterTableModel>(
          builder: (context, length, child) {
            final parameterTableModel =
                Provider.of<ParameterTableModel>(context, listen: false);
            final parameterRows = List<DataRow>.generate(
                parameterTableModel.numRows,
                (index) => ParameterRow(context, index: index).row);
            final headers = parameterHeaders
                .map((e) => DataColumn(
                    label: TextButton(
                        onPressed: () {
                          switch (e) {
                            case (parameterFileHeader):
                              parameterTableModel.copyFileParameters();
                              break;

                            case (parameterConnectedHeader):
                              parameterTableModel.copyConnectedParameters();
                              break;

                            default:
                              break;
                          }
                        },
                        child: Text(e))))
                .toList();
            return DataTable(columns: headers, rows: parameterRows);
          },
        ),
      ),
    );
  }
}

class ParameterRow {
  late DataRow row;
  int index;

  ParameterRow(BuildContext context, {Key? key, this.index = -1}) {
    final parameterTableModel =
        Provider.of<ParameterTableModel>(context, listen: false);

    row = DataRow(
      cells: [
        DataCell(
          (index >= 0) ? Text(index.toString()) : const Text(""),
        ),
        DataCell(
          Text(parameterTableModel.parameterName(index)),
        ),
        DataCell(
          TextField(
            controller: TextEditingController(
                text: parameterTableModel.getCurrentText(index)),
            style:
                const TextStyle(fontSize: standardFontSize, color: textColor),
            onChanged: (text) {
              parameterTableModel.setCurrentText(index, text);
            },
          ),
        ),
        DataCell(Text(parameterTableModel.getFileText(index))),
        DataCell(Text(parameterTableModel.getConnectedText(index))),
      ],
      selected: parameterTableModel.rowSelected(index),
      onSelectChanged: (selected) {
        parameterTableModel.selectRow(index, selected);
      },
    );
  }
}
