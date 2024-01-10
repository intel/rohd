# ROHD Devtool

The ROHD Devtool provides debugging functionality for hardware designers. Initial proposals and discussions for the devtool can be found at <https://github.com/intel/rohd/discussions/418>.

How to Use the ROHD Devtool:

1. Set a breakpoint on your ROHD design.
2. When the breakpoint is hit, an URL will be outputted.
3. Run the dart devtools command on your terminal.
4. A webpage will open, and you can paste the URL into the webpage.
5. Look for the tab labeled 'ROHD'.

## Contributions

We welcome contributions to the development of the ROHD Devtool. Please refer to our Contributing doc for guidance on how to get started.

## Running Tests on the Devtool

The ROHD Devtool runs in an iframe, which means that the --platform chrome flag is required to ensure tests are run in the browser.

Markdown Block

```cmd
flutter test --platform chrome Optional[test\modules\tree_structure\model_tree_card_test.dart] > test_output.txt
```

This command will output the test results to a text file named `test_output.txt`.
