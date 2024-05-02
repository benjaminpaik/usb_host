import 'package:usb_host/models/host_data_model.dart';
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
    final hostDataModel = Provider.of<HostDataModel>(context, listen: false);

    final valueList = Selector<HostDataModel, bool>(
      selector: (_, selectorModel) => selectorModel.statusValue,
      builder: (context, _, child) {

        final bitStatus = hostDataModel.configData.status;

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
