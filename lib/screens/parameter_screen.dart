import 'package:usb_host/models/host_data_model.dart';
import 'package:usb_host/widgets/message_widget.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../definitions.dart';
import '../misc/parameter.dart';
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
    final parameterTableModel =
    Provider.of<ParameterTableModel>(context, listen: false);
    final hostDataModel = Provider.of<HostDataModel>(context, listen: false);

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
                  hostDataModel.getParametersUserSequence().then((success) {
                    if (success) {
                      parameterTableModel.updateTable();
                    }
                    displayMessage(context, hostDataModel.userMessage);
                  });
                },
              ),
              const Spacer(),
              ElevatedButton(
                child: const Text("send parameters"),
                onPressed: () {
                  hostDataModel.sendParameters().then((_) {
                    displayMessage(context, hostDataModel.userMessage);
                  });
                },
              ),
              const Spacer(),
              ElevatedButton(
                child: const Text("flash parameters"),
                onPressed: () {
                  hostDataModel.flashParameters().then((_) {
                    displayMessage(context, hostDataModel.userMessage);
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
            final parameters =
                Provider.of<HostDataModel>(context, listen: false)
                    .configData
                    .parameter;
            final parameterRows = List<DataRow>.generate(parameters.length,
                    (index) => ParameterRow(context, index: index).row);
            final headers = parameterHeaders
                .map((e) => DataColumn(
                label: TextButton(
                    onPressed: () {
                      switch (e) {
                        case (parameterFileHeader):
                          copyFileParameters(
                              parameterTableModel, parameters);
                          parameterTableModel.updateTable();
                          break;

                        case (parameterConnectedHeader):
                          copyConnectedParameters(
                              parameterTableModel, parameters);
                          parameterTableModel.updateTable();
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

  void copyFileParameters(
      ParameterTableModel parameterTableModel, List<Parameter> parameters) {
    for (int i = 0; i < parameters.length; i++) {
      if (parameterTableModel.rowSelected(i) &&
          parameters[i].fileValue != null) {
        parameters[i].currentValue = parameters[i].fileValue;
      }
    }
  }

  void copyConnectedParameters(
      ParameterTableModel parameterTableModel, List<Parameter> parameters) {
    for (int i = 0; i < parameters.length; i++) {
      if (parameterTableModel.rowSelected(i) &&
          parameters[i].connectedValue != null) {
        parameters[i].currentValue = parameters[i].connectedValue;
      }
    }
  }
}

class ParameterRow {
  late DataRow row;
  int index;

  ParameterRow(BuildContext context, {Key? key, this.index = -1}) {
    final parameterTableModel =
    Provider.of<ParameterTableModel>(context, listen: false);
    final parameters =
        Provider.of<HostDataModel>(context, listen: false).configData.parameter;

    row = DataRow(
      cells: [
        DataCell(
          (index >= 0) ? Text(index.toString()) : const Text(""),
        ),
        DataCell(
          Text(parameters[index].name),
        ),
        DataCell(
          TextField(
            controller:
            TextEditingController(text: parameters[index].currentString),
            style:
            const TextStyle(fontSize: standardFontSize, color: textColor),
            onChanged: (text) {
              parameters[index].setCurrentFromText(text);
            },
          ),
        ),
        DataCell(Text(parameters[index].fileString)),
        DataCell(Text(parameters[index].connectedString)),
      ],
      selected: parameterTableModel.rowSelected(index),
      onSelectChanged: (selected) {
        parameterTableModel.selectRow(index, selected);
      },
    );
  }
}
