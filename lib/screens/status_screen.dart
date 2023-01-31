import 'package:usb_host/models/host_data_model.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../widgets/navigation_widget.dart';

class StatusPage extends StatelessWidget {
  static const String title = 'Control';
  static Icon icon = const Icon(Icons.code);

  const StatusPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const CustomMenuBar(),
      ),
      drawer: const CustomNavigationDrawer(),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const StatusSelector(),
          StatusBitList(),
          const Spacer(),
        ],
      ),
    );
  }
}

class StatusSelector extends StatelessWidget {
  const StatusSelector({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final hostDataModel = Provider.of<HostDataModel>(context, listen: false);

    const telemetrySelectLabel = Padding(
      padding: EdgeInsets.symmetric(vertical: 20.0, horizontal: 25.0),
      child: Text("Telemetry Status Select: "),
    );

    final statusBitList = Selector<HostDataModel, String?>(
      selector: (_, selectorModel) => selectorModel.statusState,
      builder: (context, _, child) {
        return DropdownButton(
          value: hostDataModel.statusState,
          items: hostDataModel.configData.telemetry
              .map((item) =>
              DropdownMenuItem(value: item.name, child: Text(item.name)))
              .toList(),
          onChanged: (String? state) {
            hostDataModel.statusState = state;
          },
        );
      },
    );

    return Row(
      children: [
        telemetrySelectLabel,
        statusBitList,
      ],
    );
  }
}

class StatusBitList extends StatelessWidget {
  final valueScrollController = ScrollController();

  StatusBitList({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final dataHeaders =
        ["name: ", "value: "].map((e) => DataColumn(label: Text(e))).toList();
    final hostDataModel = Provider.of<HostDataModel>(context, listen: false);
    final bitStatus = hostDataModel.configData.status;

    final valueList = Selector<HostDataModel, String?>(
      selector: (_, selectorModel) => selectorModel.statusState,
      builder: (context, _, child) {
        final dataRows = List<DataRow>.generate(bitStatus.numFields, (index) {
          return DataRow(
            cells: [
              DataCell(SizedBox(
                width: 300,
                child: Text(bitStatus.fieldName(index)),
              )),
              DataCell(Text(bitStatus.fieldValue(index).toString())),
            ],
          );
        });

        return SingleChildScrollView(
          controller: valueScrollController,
          scrollDirection: Axis.vertical,
          child: DataTable(
            columnSpacing: 0,
            columns: dataHeaders,
            rows: dataRows,
          ),
        );
      },
    );

    return Expanded(
      flex: 10,
      child: valueList,
    );
  }
}
