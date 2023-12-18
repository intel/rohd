import 'package:flutter/material.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/models/tree_module.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/services/signal_service.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/ui/custom_text_field.dart';

class DetailCard extends StatefulWidget {
  final TreeModel? module;
  final SignalService signalService;

  const DetailCard({
    Key? key,
    this.module,
    required this.signalService,
  }) : super(key: key);

  @override
  _DetailCardState createState() => _DetailCardState();
}

class _DetailCardState extends State<DetailCard> {
  String? inputSearchTerm;
  String? outputSearchTerm;

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
    if (widget.module == null) {
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
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  DetailsCardTableTextField(
                    labelText: 'Search Input Signals',
                    onChanged: (value) {
                      setState(() {
                        inputSearchTerm = value;
                      });
                    },
                  ),
                  const SizedBox(width: 10),
                  DetailsCardTableTextField(
                    labelText: 'Search Output Signals',
                    onChanged: (value) {
                      setState(() {
                        outputSearchTerm = value;
                      });
                    },
                  ),
                ],
              ),
            ),
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
                ...widget.signalService.generateSignalsRow(
                  widget.module!,
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
