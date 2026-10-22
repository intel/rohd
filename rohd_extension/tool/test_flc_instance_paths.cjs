const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');

test('resolves waveform instance names through FLC source occurrences', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'rohd-flc-instance-'));
  try {
    fs.writeFileSync(path.join(root, 'source.dart'), 'void main() {}\n');
    const flcPath = path.join(root, 'design.flc.json');
    fs.writeFileSync(flcPath, JSON.stringify({
      version: 6,
      files: ['source.dart'],
      modules: {
        Adder_E4M4: {
          sourceOccurrences: [{ path: 'top/adder', definitionName: 'Adder_E4M4' }],
          tree: [['0:1:1', 'sum']],
        },
      },
    }));
    const exports = {};
    vm.runInNewContext(
      fs.readFileSync(path.join(__dirname, '../out/flc_service.js'), 'utf8'),
      {
        exports,
        require: name => name === 'vscode' ? {
          window: { createOutputChannel: () => ({ appendLine() {} }) },
          workspace: { workspaceFolders: [{ uri: { fsPath: root } }] },
        } : require(name),
      },
    );
    for (const name of ['Adder_E4M4', 'top/adder', 'adder']) {
      assert.equal(exports.queryModule(flcPath, name).formats.rohd.available, true);
      const frames = exports.lookupSignal(flcPath, name, 'sum', 'rohd');
      assert.equal(frames.length, 1);
      assert.equal(frames[0].line, 1);
    }
    assert.equal(exports.lookupSignal(flcPath, 'unrelated', 'sum', 'rohd').length, 0);
  } finally {
    fs.rmSync(root, { recursive: true });
  }
});
