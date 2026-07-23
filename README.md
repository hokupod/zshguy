# zshguy

A zsh widget that generates commands from natural language using LM Studio or Ollama.

Type what you want to do in plain English, and `zshguy` asks the model for a zsh command or an insertion at the cursor position.

## Requirements

- `zsh` only
- One local model backend:
  - `lms` from [LM Studio](https://lmstudio.ai/)
  - `ollama` from [Ollama](https://ollama.com/)

### Preflight

For LM Studio, complete its first-run setup and run:

```zsh
# Check LMS CLI availability
lms --help

# Confirm LM Studio is running and the model is reachable
lms chat -p "ping"
```

If you set `ZSHGUY_MODEL`, run `lms chat "$ZSHGUY_MODEL" -p "ping"` instead.

For Ollama, start the server and run:

```zsh
# Check Ollama CLI and server availability
ollama --version

# Confirm installed model names
ollama list

# Verify generation
ollama run qwen3:4b "ping"
```

### LM Studio model setup (example: `qwen/qwen3.5-9b`)

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

### Ollama model setup (example: `qwen3:4b`)

```zsh
# Download model
ollama pull qwen3:4b

# Confirm local model name
ollama list

# Verify generation
ollama run qwen3:4b "ping"
```

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
The generated command is placed in the command buffer and is not executed automatically.
Review it, then press Enter to execute it.

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

## Backend and Model

LM Studio is the default backend. Existing configurations continue to work without `ZSHGUY_BACKEND`:

```zsh
export ZSHGUY_BACKEND=lms
export ZSHGUY_MODEL=llama-3.1-8b-instruct
```

For Ollama, set the backend and an installed model name:

```zsh
export ZSHGUY_BACKEND=ollama
export ZSHGUY_MODEL=qwen3:4b
```

`ZSHGUY_MODEL` is optional for LM Studio because `lms chat` can use its default model. It is required for Ollama.
The Ollama CLI connects to `127.0.0.1:11434` by default. To use another host or port, set `OLLAMA_HOST`:

```zsh
export OLLAMA_HOST=127.0.0.1:12345
```

Ollama thinking output is hidden so only the generated command is passed to the widget.

## Debugging

To inspect model output rejected by validation, enable debug mode:

```zsh
export ZSHGUY_DEBUG=1
```

When validation fails, `zshguy` prints the raw output and normalized output to `stderr`.

## Testing

Run the unit tests and interactive ZLE integration tests:

```zsh
zsh tests/run.zsh
```

The integration tests cover both startup loading and sourcing `zshguy` after other ZLE plugins have already initialized.

## License

MIT

## Author

hokupod

Originally based on [`bashguy`](https://github.com/mattn/bashguy) by Yasuhiro Matsumoto (a.k.a. mattn).
