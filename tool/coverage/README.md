# Coverage Tools

`generate_coverage.sh` runs coverage for the package in the current working
directory, writes `coverage/lcov.info`, and generates `coverage/html`. Pass
`--generate-svg` when CI needs the temporary badge at
`/tmp/coverage-badge.svg`.

```sh
bash tool/coverage/generate_coverage.sh
```

`view_coverage.sh` serves the current package's HTML report on a loopback port.
Use `--regenerate` to collect fresh coverage first.

```sh
bash tool/coverage/view_coverage.sh --regenerate
```
