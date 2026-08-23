# Module Services Branch Stack Analysis

Date: 2026-08-05

## Current conclusion

The `module_services` branch no longer appears necessary for the `ModuleTree.instance.rootModule` behavior. That pattern is already coming from `module_services_api`, not from `module_services` and not from an overlay in `baseRepo_pr_order.sh`.

The `SvService` rename cleanup was committed locally on `module_services` as:

- `a2b261e0b Migrate SvService to SystemVerilogService`

After that commit:

- `HEAD` has zero `SvService` references.
- The working tree had only diagnostics/root-module cleanup left.
- The remaining diagnostics cleanup was shown to match `module_services_api` exactly once the companion `inspector_service.dart` change was included.

## Root-module origin

`merged_pr_order` already has the newer root-module API in committed history:

```dart
Module? get rootModule => ModuleTree.instance.rootModule;

@internal
set rootModule(Module? module) {
  ModuleTree.instance.rootModule = module;
}
```

`git blame` in `merged_pr_order` attributes that pattern to `module_services_api` commits:

- `b8f5f6385 refactor: Convert rootModule field to property with ModuleTree sync`
- `e8bc6d38b cleanup module_services lookup and rootModule APIs`
- `8d9be7311 cleaner ModuleTree update`

The same commits are present in `module_services_api` history for:

- `lib/src/diagnostics/module_services.dart`
- `lib/src/diagnostics/inspector_service.dart`

`source_debug` and `fst-writer` still show the older pattern using `ModuleTree.rootModuleInstance`, so they are not the source of the newer API.

## Overlay/script check

A search of `baseRepo_pr_order.sh` did not show an explicit rewrite to `ModuleTree.instance.rootModule`. The script still contains older `rootModuleInstance`-style cleanup and later compatibility patching, but not this exact API conversion.

A prior verification checkpoint also showed the pattern immediately after the API branch was applied:

- `tmp/pr_order_verify_20260719_170207/after_api_checkpoint/...`

That supports the conclusion that `module_services_api` introduced the pattern before later downstream branch merges.

## Current local dirty files to remember

The root-module cleanup in `module_services` currently touches:

- `lib/src/diagnostics/module_services.dart`
- `lib/src/diagnostics/inspector_service.dart`

Important nuance: changing only `module_services.dart` to call `ModuleTree.instance.rootModule` does not compile unless the companion `ModuleTree.rootModule` accessor/setter from `inspector_service.dart` is also present.

## Validation performed

Focused validation after applying the paired diagnostics change:

```sh
/home/desmond/flutter_3.44/flutter/bin/dart test test/module_services_test.dart --platform vm --reporter expanded --fail-fast
```

Result: all tests passed.

Diagnostics on the two touched files were clean.

## Likely next decision

If we decide `module_services` should remain in the merge order, commit the two diagnostics files as a sync from `module_services_api`.

If we decide `module_services` should be removed from the merge order, do not keep this duplicated root-module cleanup in `module_services`; it is already supplied by `module_services_api`.

The remaining reason to keep `module_services` would need to be something other than the root-module pattern or the `SvService` naming migration, since both now have upstream/final coverage.
