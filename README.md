# zshguy

A zsh widget that generates commands from natural language using `lms`.

Type what you want to do in plain English, and `zshguy` asks the model for a zsh command or an insertion at the cursor position.

## Requirements

- `zsh` only
- `lms` command from [LM Studio](https://lmstudio.ai/)
- LM Studio must be started once and finish its first-run setup before `lms` will work reliably

### Preflight

Run `lms` once before using the widget and confirm it can reach your model:

```zsh
lms chat -p "ping"
```

If you set `ZSHGUY_MODEL`, run `lms chat "$ZSHGUY_MODEL" -p "ping"` instead.

## Installation

Source the script from your `.zshrc`:

```zsh
source /path/to/zshguy.sh
```

When sourced in an interactive shell, the script registers `zshguy-widget` with `zle -N`.

## Key Binding

`zshguy` does not bind a key automatically. Add a manual `bindkey` mapping after sourcing the script:

```zsh
source /path/to/zshguy.sh
bindkey '^X^J' zshguy-widget
```

Other examples:

```zsh
bindkey '^X^J' zshguy-widget
bindkey '^X^G' zshguy-widget
```

## Usage

Press your bound key, then enter a prompt at the `[zshguy]` prompt.

### Empty buffer

If the command line is empty, `zshguy` generates a full zsh command.

Example prompt:

```text
count the number of files in the current directory
```

### Existing input

If you already have text on the command line, `zshguy` inserts text at the cursor position.

Example buffer:

```text
git checkout 
```

Example prompt:

```text
main
```

If the prompt is empty or generation fails, the current buffer stays unchanged.

## Changing the Model

Set `ZSHGUY_MODEL` to choose a different LM Studio model name:

```zsh
export ZSHGUY_MODEL=llama-3.1-8b-instruct
```

If `ZSHGUY_MODEL` is unset, `lms chat` uses its default model.

## License

MIT

## Author

hokupod

Originally based on [`bashguy`](https://github.com/mattn/bashguy) by Yasuhiro Matsumoto (a.k.a. mattn).
