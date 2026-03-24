# bashguy

A shell widget that generates bash commands from natural language using Claude.

Type what you want to do in plain English, and Claude generates the command and inserts it into your command line. If there's already partial input, it inserts a completion at the cursor position.

## Requirements

- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) (`claude` command)
- Bash

## Installation

Add the following to your `.bashrc`:

```bash
source /path/to/bashguy.sh
```

## Key Binding

No key binding is set by default. Add a `bind` command after sourcing the script in your `.bashrc`:

```bash
source /path/to/bashguy.sh
bind -x '"\C-g": _bashguy_widget'
```

### Examples

| Key | bind command |
|-----|-------------|
| Ctrl+G | `bind -x '"\C-g": _bashguy_widget'` |
| Ctrl+J | `bind -x '"\C-j": _bashguy_widget'` |
| Ctrl+X Ctrl+G | `bind -x '"\C-x\C-g": _bashguy_widget'` |

## Usage

1. Press your bound key to get a `[bashguy]` prompt
2. Describe what you want to do (e.g., `count the number of files in the current directory`)
3. Claude generates the command and inserts it into your command line

If you press the key with partial input on the command line, it inserts a completion at the cursor position.

## Changing the Model

Set the `BASHGUY_MODEL` environment variable to use a different model. The default is `claude-sonnet-4-20250514`.

```bash
export BASHGUY_MODEL=claude-haiku-4-5-20251001
```
