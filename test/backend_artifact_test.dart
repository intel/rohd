// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// backend_artifact_test.dart
// Tests for backend-specific artifact resolution contracts.
//
// 2026 July
// Author: Desmond A. Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import 'package:rohd/rohd.dart';
import 'package:test/test.dart';

class _CustomArtifactModule extends Module with SystemVerilog {
  @override
  String? definitionVerilog(String definitionType) =>
      'module $definitionType; endmodule';

  @override
  String instantiationVerilog(
    String instanceType,
    String instanceName,
    Map<String, String> ports,
  ) =>
      '$instanceType $instanceName(.signal(${ports['signal']}));';
}

void main() {
  group('SystemVerilog backend artifacts', () {
    test('adapt custom definition and instantiation hooks', () {
      final module = _CustomArtifactModule();

      final definition = module.artifactFor(
        const BackendArtifactContext.definition(
          backend: EmissionBackend.systemVerilog,
          definitionType: 'custom_definition',
        ),
      );
      final instantiation = module.artifactFor(
        const BackendArtifactContext.instantiation(
          backend: EmissionBackend.systemVerilog,
          instanceType: 'custom_definition',
          instanceName: 'custom_instance',
          ports: {'signal': 'source_signal'},
        ),
      );

      expect(definition, isNotNull);
      expect(definition!.backend, EmissionBackend.systemVerilog);
      expect(definition.kind, BackendArtifactKind.definition);
      expect(definition.contents, 'module custom_definition; endmodule');
      expect(instantiation, isNotNull);
      expect(instantiation!.backend, EmissionBackend.systemVerilog);
      expect(instantiation.kind, BackendArtifactKind.instantiation);
      expect(instantiation.contents,
          'custom_definition custom_instance(.signal(source_signal));');
    });

    test('do not provide SystemVerilog source to SystemC', () {
      final module = _CustomArtifactModule();

      expect(
        module.artifactFor(
          const BackendArtifactContext.definition(
            backend: EmissionBackend.systemC,
            definitionType: 'custom_definition',
          ),
        ),
        isNull,
      );
    });
  });
}
