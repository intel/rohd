import 'package:flutter/material.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/models/tree_model.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/services/signal_service.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/ui/signal_table_text_field.dart';
import 'package:rohd_devtools_extension/src/modules/tree_structure/ui/signal_table.dart';

class SignalDetailsCard extends StatefulWidget {
  final TreeModel? module;
  final SignalService signalService;

  const SignalDetailsCard({
    Key? key,
    this.module,
    required this.signalService,
  }) : super(key: key);

  @override
  SignalDetailsCardState createState() => SignalDetailsCardState();
}

class SignalDetailsCardState extends State<SignalDetailsCard> {
  String? searchTerm;
  ValueNotifier<bool> inputSelected = ValueNotifier<bool>(true);
  ValueNotifier<bool> outputSelected = ValueNotifier<bool>(true);
  ValueNotifier<int> notifier = ValueNotifier<int>(0);

  void toggleNotifier() {
    notifier.value++;
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return AlertDialog(
              title: const Text('Filter Signals'),
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
                  SignalTableTextField(
                    labelText: 'Search Signals',
                    onChanged: (value) {
                      setState(() {
                        searchTerm = value;
                      });
                      toggleNotifier();
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.filter_list),
                    onPressed: _showFilterDialog,
                  ),
                ],
              ),
            ),
            ValueListenableBuilder(
              valueListenable: notifier,
              builder: (context, _, __) {
                return SignalTable(
                  selectedModule: widget.module!,
                  searchTerm: searchTerm,
                  inputSelectedVal: inputSelected.value,
                  outputSelectedVal: outputSelected.value,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
