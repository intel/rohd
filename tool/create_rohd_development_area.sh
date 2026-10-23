#!/usr/bin/env bash
# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
destination=""
package_name=""
module_name="MyModule"
rohd_path="$repo_root"
hcl_path="$HOME/rohd-hcl"

usage() {
  cat <<'USAGE'
Create a ROHD development package with ROHD-HCL component support.

Usage:
  tool/create_rohd_development_area.sh DESTINATION [options]

Options:
  --package-name NAME  Dart package name (defaults to the destination name)
  --module-name NAME   Module class name (defaults to MyModule)
  --rohd-path PATH     ROHD checkout (defaults to this repository)
  --hcl-path PATH      ROHD-HCL checkout (defaults to ~/rohd-hcl)
  -h, --help           Show this help

The generated package uses local path dependencies for ROHD and ROHD-HCL,
plus a local rohd_hierarchy override for the ROHD workspace dependency.
It also includes the ROHD component guide, optional ROHD-HCL integration
guidance, and the rohd-hardware and rohd-hierarchy agent skills.
After creation, run:
  cd DESTINATION
  dart pub get
  dart test
USAGE
}

fail() {
  printf 'Error: %s\n' "$1" >&2
  exit 1
}

expand_home_path() {
  case "$1" in
    '~') printf '%s\n' "$HOME" ;;
    '~/'*) printf '%s/%s\n' "$HOME" "${1:2}" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

yaml_quote() {
  local escaped
  escaped="$(printf '%s' "$1" | sed "s/'/''/g")"
  printf "'%s'" "$escaped"
}

while (($#)); do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --package-name|--module-name|--rohd-path|--hcl-path)
      option="$1"
      shift
      (($#)) || fail "Missing value for $option."
      case "$option" in
        --package-name) package_name="$1" ;;
        --module-name) module_name="$1" ;;
        --rohd-path) rohd_path="$1" ;;
        --hcl-path) hcl_path="$1" ;;
      esac
      ;;
    --*)
      fail "Unknown option: $1. Run with --help for usage."
      ;;
    *)
      if [[ -n "$destination" ]]; then
        fail "Only one destination may be specified."
      fi
      destination="$1"
      ;;
  esac
  shift
done

[[ -n "$destination" ]] || {
  usage >&2
  exit 2
}

rohd_path="$(realpath -e -- "$(expand_home_path "$rohd_path")")" ||
  fail "ROHD checkout not found: $rohd_path"
hcl_path="$(realpath -e -- "$(expand_home_path "$hcl_path")")" ||
  fail "ROHD-HCL checkout not found: $hcl_path"

[[ -f "$rohd_path/pubspec.yaml" ]] &&
  grep -Eq '^name:[[:space:]]*rohd[[:space:]]*$' "$rohd_path/pubspec.yaml" ||
  fail "ROHD checkout must contain a package named rohd: $rohd_path"
[[ -f "$hcl_path/pubspec.yaml" ]] &&
  grep -Eq '^name:[[:space:]]*rohd_hcl[[:space:]]*$' "$hcl_path/pubspec.yaml" ||
  fail "ROHD-HCL checkout must contain a package named rohd_hcl: $hcl_path"

rohd_hierarchy_path="$rohd_path/packages/rohd_hierarchy"
[[ -f "$rohd_hierarchy_path/pubspec.yaml" ]] &&
  grep -Eq '^name:[[:space:]]*rohd_hierarchy[[:space:]]*$' \
    "$rohd_hierarchy_path/pubspec.yaml" ||
  fail "ROHD checkout must contain packages/rohd_hierarchy."
rohd_version="$(awk '$1 == "version:" {print $2; exit}' "$rohd_path/pubspec.yaml")"
hcl_version="$(awk '$1 == "version:" {print $2; exit}' "$hcl_path/pubspec.yaml")"
[[ -n "$rohd_version" && -n "$hcl_version" ]] ||
  fail "Could not read ROHD and ROHD-HCL package versions."
component_guide="$repo_root/doc/Component.md"
hierarchy_skill="$repo_root/.github/skills/rohd-hierarchy/SKILL.md"
hardware_skill="$repo_root/.github/skills/rohd-hardware/SKILL.md"
[[ -f "$component_guide" ]] ||
  fail "Missing component guide: $component_guide"
[[ -f "$hierarchy_skill" ]] ||
  fail "Missing rohd_hierarchy skill: $hierarchy_skill"
[[ -f "$hardware_skill" ]] ||
  fail "Missing rohd-hardware skill: $hardware_skill"

destination="$(realpath -m -- "$destination")"
if [[ -e "$destination" ]]; then
  [[ -d "$destination" ]] || fail "Destination exists and is not a directory."
  [[ -z "$(find "$destination" -mindepth 1 -maxdepth 1 -print -quit)" ]] ||
    fail "Destination is not empty: $destination"
fi
mkdir -p "$destination"

if [[ -z "$package_name" ]]; then
  package_name="${destination##*/}"
  package_name="${package_name,,}"
  package_name="${package_name//-/_}"
  package_name="$(printf '%s' "$package_name" |
    sed -E 's/[^a-z0-9_]+/_/g; s/_+/_/g; s/^_+|_+$//g')"
  [[ "$package_name" =~ ^[a-z] ]] || package_name="rohd_${package_name}"
fi
[[ "$package_name" =~ ^[a-z][a-z0-9_]*$ ]] ||
  fail "Invalid Dart package name: $package_name"
[[ "$module_name" =~ ^[A-Z][A-Za-z0-9]*$ ]] ||
  fail "Module name must be a PascalCase Dart identifier: $module_name"

module_file="$(printf '%s' "$module_name" |
  sed -E 's/([a-z0-9])([A-Z])/\1_\2/g' |
  tr '[:upper:]' '[:lower:]')"
rohd_relative="$(realpath --relative-to="$destination" "$rohd_path")"
hcl_relative="$(realpath --relative-to="$destination" "$hcl_path")"
hierarchy_relative="$(realpath --relative-to="$destination" "$rohd_hierarchy_path")"

mkdir -p "$destination/lib/src" "$destination/test" "$destination/doc"
mkdir -p "$destination/.github/skills/rohd-hierarchy"
mkdir -p "$destination/.github/skills/rohd-hardware"
cp "$component_guide" "$destination/doc/Component.md"
cp "$hierarchy_skill" "$destination/.github/skills/rohd-hierarchy/SKILL.md"
cp "$hardware_skill" "$destination/.github/skills/rohd-hardware/SKILL.md"

cat >"$destination/pubspec.yaml" <<YAML
name: $package_name
description: A ROHD development package with ROHD-HCL component support.
publish_to: none
version: 0.1.0

environment:
  sdk: '>=3.6.0 <4.0.0'

dependencies:
  rohd: ^$rohd_version
  rohd_hcl: ^$hcl_version

dev_dependencies:
  test: ^1.25.0

dependency_overrides:
  rohd:
    path: $(yaml_quote "$rohd_relative")
  rohd_hcl:
    path: $(yaml_quote "$hcl_relative")
  rohd_hierarchy:
    path: $(yaml_quote "$hierarchy_relative")
YAML

cat >"$destination/lib/$package_name.dart" <<DART
export 'src/$module_file.dart';
DART

cat >"$destination/lib/src/$module_file.dart" <<DART
// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// $module_file.dart
//
// 2026 October 22
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';

/// A small typed structure used by the starter module ports.
class ${module_name}Packet extends LogicStructure {
  /// The single-bit packet field.
  Logic get flag => elements[0];

  /// The four-bit packet field.
  Logic get nibble => elements[1];

  /// Creates a packet with two independently addressable fields.
  ${module_name}Packet({String? name})
    : super([
        Logic(name: 'flag'),
        Logic(name: 'nibble', width: 4),
      ], name: name ?? '${module_file}_packet');

  @override
  ${module_name}Packet clone({String? name}) =>
      ${module_name}Packet(name: name ?? this.name);
}

/// Tags the input and output ports of [${module_name}Interface].
enum ${module_name}InterfacePort {
  /// Tags signals driven into a module.
  toModule,

  /// Tags signals driven from a module.
  fromModule,
}

/// A minimal interface port that the starter module inverts.
class ${module_name}Interface extends Interface<${module_name}InterfacePort> {
  /// Signal driven into the module.
  Logic get signalIn => port('signalIn');

  /// Inverted signal driven from the module.
  Logic get signalOut => port('signalOut');

  /// Creates the interface ports and their directions.
  ${module_name}Interface() {
    setPorts([Logic.port('signalIn')], [${module_name}InterfacePort.toModule]);
    setPorts([Logic.port('signalOut')], [${module_name}InterfacePort.fromModule]);
  }

  @override
  ${module_name}Interface clone() => ${module_name}Interface();
}

/// A small parent shell that exposes typed ports through a child module.
class $module_name extends Module {
  /// The inverted structured output.
  ${module_name}Packet get structureOut =>
      output('structureOut') as ${module_name}Packet;

  /// The inverted [LogicArray] output.
  LogicArray get arrayOut => output('arrayOut') as LogicArray;

  /// The inverted typed-array output.
  TypedLogicArray<${module_name}Packet, LogicValue> get typedArrayOut =>
      output('typedArrayOut') as TypedLogicArray<${module_name}Packet, LogicValue>;

  /// Creates a shell that delegates each typed port to a child inverter.
  $module_name(
    ${module_name}Packet structureIn,
    LogicArray arrayIn,
    TypedLogicArray<${module_name}Packet, LogicValue> typedArrayIn,
    ${module_name}Interface control, {
    super.name = '${module_file}',
  }) : super(definitionName: '${module_name}Shell') {
    structureIn = addTypedInput('structureIn', structureIn);
    arrayIn = addInputArray(
      'arrayIn',
      arrayIn,
      dimensions: arrayIn.dimensions,
      elementWidth: arrayIn.elementWidth,
      numUnpackedDimensions: arrayIn.numUnpackedDimensions,
    );
    typedArrayIn = addTypedInput('typedArrayIn', typedArrayIn);
    control = addInterfacePorts(
      control,
      inputTags: {${module_name}InterfacePort.toModule},
      outputTags: {${module_name}InterfacePort.fromModule},
      uniquify: (original) => 'control_\$original',
    );

    final child = _${module_name}PortInverter(
      structureIn,
      arrayIn,
      typedArrayIn,
      control,
    );
    addTypedOutput(
      'structureOut',
      child.structureOut.clone,
    ).gets(child.structureOut);
    addOutputArray(
      'arrayOut',
      dimensions: child.arrayOut.dimensions,
      elementWidth: child.arrayOut.elementWidth,
      numUnpackedDimensions: child.arrayOut.numUnpackedDimensions,
    ).gets(child.arrayOut);
    addTypedOutput(
      'typedArrayOut',
      child.typedArrayOut.clone,
    ).gets(child.typedArrayOut);
  }
}

/// Owns the typed child ports and inverts every leaf signal.
class _${module_name}PortInverter extends Module {
  ${module_name}Packet get structureOut =>
      output('structureOut') as ${module_name}Packet;

  LogicArray get arrayOut => output('arrayOut') as LogicArray;

  TypedLogicArray<${module_name}Packet, LogicValue> get typedArrayOut =>
      output('typedArrayOut') as TypedLogicArray<${module_name}Packet, LogicValue>;

  _${module_name}PortInverter(
    ${module_name}Packet structureIn,
    LogicArray arrayIn,
    TypedLogicArray<${module_name}Packet, LogicValue> typedArrayIn,
    ${module_name}Interface control,
  ) : super(definitionName: '${module_name}PortInverter') {
    structureIn = addTypedInput('structureIn', structureIn);
    final structureOut = addTypedOutput('structureOut', structureIn.clone);
    structureOut.flag <= ~structureIn.flag;
    structureOut.nibble <= ~structureIn.nibble;

    arrayIn = addInputArray(
      'arrayIn',
      arrayIn,
      dimensions: arrayIn.dimensions,
      elementWidth: arrayIn.elementWidth,
      numUnpackedDimensions: arrayIn.numUnpackedDimensions,
    );
    final arrayOut = addOutputArray(
      'arrayOut',
      dimensions: arrayIn.dimensions,
      elementWidth: arrayIn.elementWidth,
      numUnpackedDimensions: arrayIn.numUnpackedDimensions,
    );
    for (final (index, input) in arrayIn.arrayElements.indexed) {
      arrayOut.arrayElements[index] <= ~input;
    }

    typedArrayIn = addTypedInput('typedArrayIn', typedArrayIn);
    final typedArrayOut = addTypedOutput('typedArrayOut', typedArrayIn.clone);
    for (final (index, input) in typedArrayIn.arrayElements.indexed) {
      final output = typedArrayOut.arrayElements[index];
      output.flag <= ~input.flag;
      output.nibble <= ~input.nibble;
    }

    final internalControl = addInterfacePorts(
      control,
      inputTags: {${module_name}InterfacePort.toModule},
      outputTags: {${module_name}InterfacePort.fromModule},
      uniquify: (original) => 'control_\$original',
    );
    internalControl.signalOut <= ~internalControl.signalIn;
  }
}
DART

cat >"$destination/test/${module_file}_test.dart" <<DART
// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// ${module_file}_test.dart
//
// 2026 October 22
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'dart:io';

import 'package:rohd/rohd.dart';
import 'package:$package_name/$package_name.dart';
import 'package:test/test.dart';

void main() {
  tearDown(() async {
    SourceTracer.clear();
    await Simulator.reset();
  });

  test('$module_name preserves typed ports across a child inverter', () async {
    SourceTracer.activate();
    final structureIn = ${module_name}Packet(name: 'structureIn');
    final arrayIn = LogicArray(
      [2],
      1,
      name: 'arrayIn',
      numUnpackedDimensions: 1,
    );
    final typedArrayIn = TypedLogicArray<${module_name}Packet, LogicValue>(
      [2],
      ${module_name}Packet.new,
      name: 'typedArrayIn',
      numUnpackedDimensions: 1,
    );
    final control = ${module_name}Interface();
    final dut = $module_name(structureIn, arrayIn, typedArrayIn, control);
    await dut.build();

    final debugDirectory = Directory.systemTemp.createTempSync(
      '${module_file}_debug_',
    );
    addTearDown(() => debugDirectory.deleteSync(recursive: true));

    final sv = SystemVerilogService(
      dut,
      multiFile: true,
      outputDirectory: debugDirectory.path,
      register: false,
    )..writeOutputs();
    final trace = TraceService(
      dut,
      svService: sv,
      packageRoot: Directory.current.path,
      outputPath: debugDirectory.path,
      svOutputMode: SvOutputMode.perModule,
      register: false,
    )..write();
    final netlist = NetlistService(
      dut,
      configuration: NetlistSynthesizerConfiguration(
        trace: true,
        packageRoot: Directory.current.path,
      ),
      packageRoot: Directory.current.path,
      outputDirectory: debugDirectory.path,
      register: false,
    )..writeOutputs();
    final waveformPath = '\${debugDirectory.path}/${module_file}.vcd';
    dut.dumpWaves(outputPath: waveformPath);

    structureIn.flag.put(0);
    structureIn.nibble.put(0x3);
    arrayIn.arrayElements[0].put(0);
    arrayIn.arrayElements[1].put(1);
    typedArrayIn.arrayElements[0]
      ..flag.put(0)
      ..nibble.put(0x5);
    typedArrayIn.arrayElements[1]
      ..flag.put(1)
      ..nibble.put(0x0);
    control.signalIn.put(0);

    expect(dut.structureOut.flag.value.toInt(), 1);
    expect(dut.structureOut.nibble.value.toInt(), 0xc);
    expect(dut.arrayOut.arrayElements[0].value.toInt(), 1);
    expect(dut.arrayOut.arrayElements[1].value.toInt(), 0);
    expect(dut.typedArrayOut.arrayElements[0].flag.value.toInt(), 1);
    expect(dut.typedArrayOut.arrayElements[0].nibble.value.toInt(), 0xa);
    expect(dut.typedArrayOut.arrayElements[1].flag.value.toInt(), 0);
    expect(dut.typedArrayOut.arrayElements[1].nibble.value.toInt(), 0xf);
    expect(control.signalOut.value.toInt(), 1);

    Simulator.registerAction(1, () {
      structureIn.flag.put(1);
      control.signalIn.put(1);
    });
    Simulator.setMaxSimTime(2);
    await Simulator.run();

    expect(dut.subModules, hasLength(1));
    expect(
      dut.typedArrayOut,
      isA<TypedLogicArray<${module_name}Packet, LogicValue>>(),
    );
    expect(netlist.json, contains('rohd.src_trace'));
    expect(trace.writtenPath, isNotNull);
    expect(File(trace.writtenPath!).existsSync(), isTrue);
    expect(
      debugDirectory.listSync().whereType<File>().any(
        (file) => file.path.endsWith('.rohd.json'),
      ),
      isTrue,
    );
    expect(
      debugDirectory.listSync().whereType<File>().any(
        (file) => file.path.endsWith('.sv'),
      ),
      isTrue,
    );
    expect(File(waveformPath).readAsStringSync(), contains(r'\$enddefinitions'));
  });
}
DART

cat >"$destination/README.md" <<README
# $package_name

A starter development package for building and testing ROHD modules with
ROHD-HCL components available. The generated shell demonstrates a
\`LogicStructure\`, \`LogicArray\`, \`TypedLogicArray\`, and \`Interface\`
crossing a parent/child module boundary.

The generated \`pubspec.yaml\` points to local ROHD and ROHD-HCL checkouts.
Change those paths if either checkout moves.

The generated test performs a small inversion check and creates temporary
traced netlist, VCD waveform, SystemVerilog, and FLC artifacts. Change its
temporary debug directory to a persistent \`build/\` path when you want to
inspect those files after the test completes.

See [doc/Component.md](doc/Component.md) for ROHD component construction and
optional ROHD-HCL integration guidance.
Agent guidance is included in:

- [.github/skills/rohd-hardware/SKILL.md](.github/skills/rohd-hardware/SKILL.md)
  for ROHD module construction, testing, and simulation.
- [.github/skills/rohd-hierarchy/SKILL.md](.github/skills/rohd-hierarchy/SKILL.md)
  for the \`rohd_hierarchy\` package.

\`\`\`sh
dart pub get
dart test
\`\`\`
README

if command -v dart >/dev/null; then
  dart format "$destination/lib" "$destination/test" >/dev/null
else
  printf 'Warning: Dart was not found; run dart format lib test after creation.\n' >&2
fi

printf 'Created ROHD development area: %s\n' "$destination"
printf 'Package: %s\nModule: %s\n' "$package_name" "$module_name"
printf 'ROHD: %s\nROHD-HCL: %s\n' "$rohd_path" "$hcl_path"
