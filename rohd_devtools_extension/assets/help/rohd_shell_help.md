# ROHD Debug Shell Help

<!-- tooltip -->

ROHD Debug Shell
  Enter          Run a command
  Tab            Complete the current command
  Up/Down        Browse command history

<!-- details -->

## Shell Controls

| Key | Description |
| --- | --- |
| Enter | Run the command in the input field |
| Tab | Request completion for the token at the cursor |
| Up / Down | Browse commands submitted in this shell session |

## Commands

| Command | Description |
| --- | --- |
| `help` | List the shell command syntax |
| `status` | Show the active design-session status and capabilities |
| `find-cell <path>` | Find a hierarchy cell by path |
| `find-port <path>` | Find a port by path |
| `find-ports <hierarchy-regex> [$root] [transparent]` | Find matching ports |
| `find-signal <path>` | Find a signal by path |
| `find-cells <hierarchy-regex> [$root] [transparent]` | Find matching hierarchy cells |
| `find-signals <hierarchy-regex> [$root] [transparent]` | Find matching signals |
| `fanin $signal [transparent]` | Trace signals feeding one signal alias |
| `fanout $signal [transparent]` | Trace signals driven by one signal alias |
| `get-value $signal [time]` | Read the latest or a historical signal value |
| `name $occurrence` | Expand one alias with its path and metadata |
| `send $signal` | Send one signal or a signal-list alias to the other panes |

`let <name> = find-cell|find-cells|find-port|find-ports|find-signal|find-signals ...`

`let` creates an alias for one occurrence or an occurrence list.

## Aliases

| Syntax | Description |
| --- | --- |
| `$sum` | Inspect one assigned occurrence |
| `$selected` | Inspect an assigned occurrence list |
| `$selected[4]` | Inspect one list occurrence by zero-based index |
| `$selected.length` | Return the number of list occurrences |

Use `$name`, `$name[index]`, or `$name.length` to inspect an alias.

## Hierarchy Patterns

`find-cells`, `find-signals`, and `find-ports` use the `rohd_hierarchy` query
language. Refer to `packages/rohd_hierarchy/README.md`, “Regex / glob search”,
for the complete syntax and examples.

A list alias retains the returned occurrence handles for commands that accept
a selection; commands requiring one occurrence report an error if given a
list. The shell is available when a ROHD debug target with diagnostics is
connected.

## Output

The shell displays successful commands in green and failures in red. Pretty
output shows occurrence addresses, list sizes, and signal values without
printing the full protocol JSON. Transported occurrence handles contain only
their addresses, even in `--json` mode. Run `name $occurrence` to expand one
handle with its path and metadata.