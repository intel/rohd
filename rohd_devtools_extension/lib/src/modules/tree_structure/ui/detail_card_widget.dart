import 'package:flutter/material.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/models/tree_module.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/services/signal_service.dart';

class DetailCard extends StatelessWidget {
  final TreeModel? module;
  final String? inputSearchTerm;
  final String? outputSearchTerm;
  final SignalService signalService;

  const DetailCard({
    Key? key,
    this.module,
    this.inputSearchTerm,
    this.outputSearchTerm,
    required this.signalService,
  }) : super(key: key);

  Widget buildTableHeader({required String text}) {
    return SizedBox(
      height: 32,
      child: Center(
        child: Text(
          text,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (module == null) {
      return const Padding(
        padding: EdgeInsets.only(top: 20.0),
        child: Center(child: Text('No module selected')),
      );
    }

    final tableHeaders = ['Name', 'Direction', 'Value', 'Width'];

    return SizedBox(
      height: MediaQuery.of(context).size.height / 1.4,
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: Column(
          children: [
            // Search fields here
            Table(
              border: TableBorder.all(),
              columnWidths: const <int, TableColumnWidth>{
                0: FlexColumnWidth(),
                1: FlexColumnWidth(),
                2: FlexColumnWidth(),
              },
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: <TableRow>[
                TableRow(
                  children: List<Widget>.generate(
                    tableHeaders.length,
                    (index) => buildTableHeader(text: tableHeaders[index]),
                  ),
                ),
                ...signalService.generateSignalsRow(
                  module!,
                  inputSearchTerm,
                  outputSearchTerm,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
