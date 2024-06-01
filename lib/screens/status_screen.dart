import 'package:usb_host/models/telemetry_model.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class StatusPage extends StatelessWidget {

  const StatusPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StatusBitList(),
        const Spacer(),
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
    final telemetryModel = Provider.of<TelemetryModel>(context, listen: false);

    final valueList = Selector<TelemetryModel, bool>(
      selector: (_, selectorModel) => selectorModel.statusChanged,
      builder: (context, _, child) {

        final bitStatus = telemetryModel.statusBits;

        final dataRows0 = List<DataRow>.generate(bitStatus.numFields, (index) {
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
            rows: dataRows0,
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
