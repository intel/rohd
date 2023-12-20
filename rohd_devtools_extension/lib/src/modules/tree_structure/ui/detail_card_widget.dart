import 'package:flutter/material.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/models/tree_model.dart';
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
  DetailCardState createState() => DetailCardState();
}

class DetailCardState extends State<DetailCard> {
  String? searchTerm;
  ValueNotifier<bool> inputSelected = ValueNotifier<bool>(true);
  ValueNotifier<bool> outputSelected = ValueNotifier<bool>(true);
  ValueNotifier<int> notifier = ValueNotifier<int>(0);

  void toggleNotifier() {
    notifier.value++;
  }

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

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return AlertDialog(
              title: Text('Filter Signals'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  CheckboxListTile(
                    title: const Text('Input'),
                    value: inputSelected.value,
                    onChanged: (bool? value) {
                      setState(() {
                        inputSelected.value = value!;
                      });
                      toggleNotifier();
                    },
                  ),
                  CheckboxListTile(
                    title: const Text('Output'),
                    value: outputSelected.value,
                    onChanged: (bool? value) {
                      setState(() {
                        outputSelected.value = value!;
                      });
                      toggleNotifier();
                    },
                  ),
                ],
              ),
              actions: <Widget>[
                TextButton(
                  child: Text('Apply'),
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                ),
              ],
            );
          },
        );
      },
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
                    labelText: 'Search Signals',
                    onChanged: (value) {
                      setState(() {
                        searchTerm = value;
                      });
                      toggleNotifier();
                    },
                  ),
                  IconButton(
                    icon: Icon(Icons.filter_list),
                    onPressed: _showFilterDialog,
                  ),
                ],
              ),
            ),
            ValueListenableBuilder(
              valueListenable: notifier,
              builder: (context, _, __) {
                return Table(
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
                      searchTerm,
                      inputSelected.value,
                      outputSelected.value,
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
