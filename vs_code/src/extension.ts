// The module 'vscode' contains the VS Code extensibility API
// Import the module and reference it with the alias vscode in your code below
import * as vscode from 'vscode';

// This method is called when your extension is activated
// Your extension is activated the very first time the command is executed
export function activate(context: vscode.ExtensionContext) {

	// Use the console to output diagnostic information (console.log) and errors (console.error)
	// This line of code will only be executed once when your extension is activated
	console.log('Congratulations, your extension "rohd" is now active!');

	// The command has been defined in the package.json file
	// Now provide the implementation of the command with registerCommand
	// The commandId parameter must match the command field in package.json
	let disposable = vscode.commands.registerCommand('rohd.helloWorld', () => {
		// The code you place here will be executed every time your command is executed
		// Display a message box to the user
		vscode.window.showInformationMessage('Hello World from ROHD!');
	});

	context.subscriptions.push(disposable);


	let moduleCommand = vscode.commands.registerCommand('rohd.create_module', async () => {
		
		const modName = await vscode.window.showInputBox({
			placeHolder: "Module Name",
			prompt: "what is your module name?",
			value: "AndGate"
		});

		const nInputs = await vscode.window.showInputBox({
			placeHolder: "Number of Logic inputs",
			prompt: "what is the number of input Logic?",
			value: "1"
		});

		

		// generate logic parameters in the constructor
		const inputStrings = (nInputs: number): [string, string] => {
			let i = 0;
			let constructorLogics = "";
			let portLogics = "";
			while (i < nInputs) {
				constructorLogics += `Logic a${i},`;
				portLogics += `a${i} = addInput('a${i}', a${i}); \n`;
				i += 1;
			}
			return [constructorLogics, portLogics];
		};

		// current editor
		const editor = vscode.window.activeTextEditor;

		// check if there is no selection
		if (editor?.selection.isEmpty) {
			// the Position object give u the line and character 
			// where the cursor is
			const position = editor.selection.active;
			const snippetStr = new vscode.SnippetString(`class ${modName} extends Module {
				${modName}(${inputStrings(Number(nInputs))[0]}) {
					${inputStrings(Number(nInputs))[1]}
					// Add Output here
					// ...


					// Add Logic Here (e.g Combinational, Sequential)
					// ...
				}
			}`);
			console.log(snippetStr);
			editor.insertSnippet(snippetStr, position);
		}
	});
}



// This method is called when your extension is deactivated
export function deactivate() {}
