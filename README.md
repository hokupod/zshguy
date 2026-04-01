# zshguy

A zsh widget that generates commands from natural language using `lms`.

Type what you want to do in plain English, and `zshguy` asks the model for a zsh command or an insertion at the cursor position.

## Requirements

- `zsh` only
- `lms` command from [LM Studio](https://lmstudio.ai/)
- LM Studio must be started once and finish its first-run setup before `lms` will work reliably

### Preflight

Run these steps before using the widget:

```zsh
# Check LMS CLI availability
lms --help

# Confirm LM Studio is running and the model is reachable
lms chat -p "ping"
```

If you set `ZSHGUY_MODEL`, run `lms chat "$ZSHGUY_MODEL" -p "ping"` instead.

### Model setup (example: `qwen/qwen3.5-9b`)

`qwen/qwen3.5-9b` is an example model name. Replace it with the model key you want to use.

When preparing a new environment, run once:

```zsh
# Download model
lms get qwen/qwen3.5-9b

# Confirm local model key
lms ls

# Load model to memory
lms load qwen/qwen3.5-9b

# Verify generation
lms chat qwen/qwen3.5-9b -p "ping"
```

If you omit the model/key argument for `lms get` or `lms load`, LM Studio opens an interactive selector.

## Installation

### sheldon

Add `zshguy` to your `plugins.toml` and let sheldon load the canonical plugin entrypoint:

```toml
[plugins.zshguy]
github = "hokupod/zshguy"
```

### Other plugin managers

Use `zshguy.plugin.zsh` as the canonical plugin entrypoint:

```zsh
source /path/to/zshguy.plugin.zsh
```

`zshguy.sh` remains available as a compatibility path for manual sourcing and older setups.

### Manual source

If you do not use a plugin manager, source the compatibility wrapper from your `.zshrc`:

```zsh
source /path/to/zshguy.sh
```

## Key Binding

`zshguy` does not bind a key automatically. Add a manual `bindkey` mapping:

```zsh
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

## Debugging

To inspect model output rejected by validation, enable debug mode:

```zsh
export ZSHGUY_DEBUG=1
```

When validation fails, `zshguy` will print the raw output and normalized output to `stderr`.


## License

MIT

## Author

hokupod

Originally based on [`bashguy`](https://github.com/mattn/bashguy) by Yasuhiro Matsumoto (a.k.a. mattn).
