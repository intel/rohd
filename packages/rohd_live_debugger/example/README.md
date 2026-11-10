# Debugging a ROHD design

Add the debugger to a ROHD project's `pubspec.yaml`:

```yaml
dev_dependencies:
  rohd_live_debugger: ^0.0.1
```

Run `dart pub get` and start a debug session for an instrumented ROHD program.
For a complete example, follow the
[serializer walkthrough](https://github.com/intel/rohd/tree/main/rohd_devtools_extension#preparing-the-program-being-debugged).
Pause after the program registers its diagnostic services, open DevTools in a
browser, and select the `rohd_live_debugger` tab.
