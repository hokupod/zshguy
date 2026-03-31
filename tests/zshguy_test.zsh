#!/usr/bin/env zsh

emulate -L zsh
setopt no_unset
setopt pipefail
setopt errexit

typeset -r TEST_DIR="${0:A:h}"
typeset -r ZSHGUY_SH="${TEST_DIR:h}/zshguy.sh"
typeset -r ZSHGUY_PLUGIN_ZSH="${TEST_DIR:h}/zshguy.plugin.zsh"
typeset ZSHGUY_TEST_SETUP_STATE

if [[ -f "$ZSHGUY_PLUGIN_ZSH" ]]; then
  if source "$ZSHGUY_PLUGIN_ZSH"; then
    ZSHGUY_TEST_SETUP_STATE="loaded $ZSHGUY_PLUGIN_ZSH"
  else
    ZSHGUY_TEST_SETUP_STATE="setup failed $ZSHGUY_PLUGIN_ZSH"
  fi
elif [[ -f "$ZSHGUY_SH" ]]; then
  if source "$ZSHGUY_SH"; then
    ZSHGUY_TEST_SETUP_STATE="loaded $ZSHGUY_SH"
  else
    ZSHGUY_TEST_SETUP_STATE="setup failed $ZSHGUY_SH"
  fi
else
  ZSHGUY_TEST_SETUP_STATE="missing $ZSHGUY_SH"
fi

typeset -gi TESTS_PASSED=0
typeset -gi TESTS_FAILED=0

assert_eq() {
  local expected=$1
  local actual=$2
  local message=$3

  if [[ "$expected" == "$actual" ]]; then
    return 0
  fi

  print -ru2 -- "FAIL: $message"
  print -ru2 -- "  expected: $expected"
  print -ru2 -- "  actual:   $actual"
  return 1
}

assert_array_eq() {
  local message=$1
  local expected_name=$2
  local actual_name=$3
  local -a expected
  local -a actual
  local i

  expected=("${(@P)expected_name}")
  actual=("${(@P)actual_name}")

  assert_eq "${#expected[@]}" "${#actual[@]}" "$message arity" || return 1

  for (( i = 1; i <= ${#expected[@]}; ++i )); do
    assert_eq "$expected[i]" "$actual[i]" "$message element $i" || return 1
  done
}

assert_helper_available() {
  local helper_name=$1
  local helper_label=$2

  if (( ! $+functions[$helper_name] )); then
    print -ru2 -- "FAIL: $helper_label helper is missing"
    print -ru2 -- "  state:   $ZSHGUY_TEST_SETUP_STATE"
    if [[ "$ZSHGUY_TEST_SETUP_STATE" == missing* ]]; then
      print -ru2 -- "  bootstrap: zshguy.sh is missing"
    fi
    return 1
  fi
}

test_plugin_entrypoint_exists() {
  if [[ ! -f "$ZSHGUY_PLUGIN_ZSH" ]]; then
    print -ru2 -- "FAIL: plugin entrypoint is missing"
    print -ru2 -- "  path:    $ZSHGUY_PLUGIN_ZSH"
    return 1
  fi

  if ! zsh -f -c '
    source '"${(q)ZSHGUY_PLUGIN_ZSH}"' || exit 1
    (( ${+functions[_zshguy_run_lms]} ))
  '; then
    print -ru2 -- "FAIL: plugin entrypoint did not load helpers"
    print -ru2 -- "  path:    $ZSHGUY_PLUGIN_ZSH"
    return 1
  fi
}

test_compat_entrypoint_exists() {
  if [[ ! -f "$ZSHGUY_SH" ]]; then
    print -ru2 -- "FAIL: compat entrypoint is missing"
    print -ru2 -- "  path:    $ZSHGUY_SH"
    return 1
  fi

  if ! zsh -f -c '
    source '"${(q)ZSHGUY_SH}"' || exit 1
    (( ${+functions[_zshguy_run_lms]} ))
  '; then
    print -ru2 -- "FAIL: compat entrypoint did not load helpers"
    print -ru2 -- "  path:    $ZSHGUY_SH"
    return 1
  fi
}

test_plugin_entrypoint_can_be_sourced_twice() {
  if [[ ! -f "$ZSHGUY_PLUGIN_ZSH" ]]; then
    print -ru2 -- "FAIL: plugin entrypoint is missing"
    print -ru2 -- "  path:    $ZSHGUY_PLUGIN_ZSH"
    return 1
  fi

  local plugin_load_state

  plugin_load_state="$(
    zsh -f -c '
      source '"${(q)ZSHGUY_PLUGIN_ZSH}"' || exit 1
      source '"${(q)ZSHGUY_PLUGIN_ZSH}"' || exit 1
      if (( ! ${+functions[_zshguy_run_lms]} )); then
        exit 2
      fi
      if (( ! ${+parameters[_zshguy_plugin_loaded]} )); then
        exit 3
      fi
      print -r -- "${+functions[_zshguy_run_lms]} ${+parameters[_zshguy_plugin_loaded]}"
    '
  )" || {
    print -ru2 -- "FAIL: plugin entrypoint source failed on repeated load"
    print -ru2 -- "  path:    $ZSHGUY_PLUGIN_ZSH"
    return 1
  }

  assert_eq "1 1" "$plugin_load_state" "plugin entrypoint repeated source keeps helpers available" || return 1

}

test_plugin_entrypoint_skips_widget_registration_in_non_interactive_shell() {
  local widget_registration_state

  widget_registration_state="$(
    zsh -f -c '
      source '"${(q)ZSHGUY_PLUGIN_ZSH}"' || exit 1
      print -r -- "${+functions[_zshguy_run_lms]} ${+widgets[zshguy-widget]}"
    '
  )" || {
    print -ru2 -- "FAIL: plugin entrypoint non-interactive load failed"
    print -ru2 -- "  path:    $ZSHGUY_PLUGIN_ZSH"
    return 1
  }

  assert_eq "1 0" "$widget_registration_state" "plugin entrypoint skips widget registration in non-interactive shell" || return 1
}

test_run_lms_with_model() {
  local lms_output
  local lms_capture_file
  local -a lms_argv
  local -a expected_lms_argv
  local ZSHGUY_MODEL="test-model"

  if ! assert_helper_available _zshguy_run_lms "run lms"; then
    return 1
  fi

  lms_capture_file="$(mktemp "${TMPDIR:-/tmp}/zshguy-lms.XXXXXX")" || return 1
  lms() {
    printf '%s\0' "$@" >"$lms_capture_file"
    print -r -- "generated text"
  }

  if ! lms_output="$(_zshguy_run_lms "sys" "user")"; then
    print -ru2 -- "FAIL: run lms helper invocation failed"
    return 1
  fi

  assert_eq "generated text" "$lms_output" "run lms output" || return 1
  while IFS= read -r -d '' lms_arg; do
    lms_argv+=("$lms_arg")
  done <"$lms_capture_file"
  rm -f "$lms_capture_file"
  expected_lms_argv=(chat test-model -s sys -p user)
  assert_array_eq "run lms argv with model" expected_lms_argv lms_argv || return 1
}

test_run_lms_without_model() {
  local lms_output
  local lms_capture_file
  local -a lms_argv
  local -a expected_lms_argv
  unset ZSHGUY_MODEL

  if ! assert_helper_available _zshguy_run_lms "run lms"; then
    return 1
  fi

  lms_capture_file="$(mktemp "${TMPDIR:-/tmp}/zshguy-lms.XXXXXX")" || return 1
  lms() {
    printf '%s\0' "$@" >"$lms_capture_file"
    print -r -- "generated text"
  }

  if ! lms_output="$(_zshguy_run_lms "sys" "user")"; then
    print -ru2 -- "FAIL: run lms helper invocation failed"
    return 1
  fi

  assert_eq "generated text" "$lms_output" "run lms output" || return 1
  while IFS= read -r -d '' lms_arg; do
    lms_argv+=("$lms_arg")
  done <"$lms_capture_file"
  rm -f "$lms_capture_file"
  expected_lms_argv=(chat -s sys -p user)
  assert_array_eq "run lms argv without model" expected_lms_argv lms_argv || return 1
}

test_build_lms_args() {
  local lms_args
  local -a expected_lms_argv
  local expected_lms_args
  local ZSHGUY_MODEL="test-model"

  if ! assert_helper_available _zshguy_build_lms_args "build lms args"; then
    return 1
  fi

  if ! lms_args="$(_zshguy_build_lms_args "sys" "user")"; then
    print -ru2 -- "FAIL: build lms args helper invocation failed"
    return 1
  fi

  if [[ -z "$lms_args" ]]; then
    print -ru2 -- "FAIL: build lms args helper returned an empty value"
    return 1
  fi

  expected_lms_argv=(chat test-model -s sys -p user)
  expected_lms_args="${(@q)expected_lms_argv}"
  assert_eq "$expected_lms_args" "$lms_args" "build lms args" || return 1

  if [[ "$lms_args" == *"--model"* ]]; then
    print -ru2 -- "FAIL: build lms args helper used an unsupported --model contract"
    print -ru2 -- "  actual:   $lms_args"
    return 1
  fi
}

test_build_lms_args_preserves_special_characters() {
  local lms_args
  local -a expected_lms_argv
  local expected_lms_args
  local system_prompt=$'sys with spaces "quotes" * glob\nline'
  local user_prompt=$'user with spaces \'single quotes\' * glob\nline'
  local ZSHGUY_MODEL="test-model"

  if ! assert_helper_available _zshguy_build_lms_args "build lms args"; then
    return 1
  fi

  if ! lms_args="$(_zshguy_build_lms_args "$system_prompt" "$user_prompt")"; then
    print -ru2 -- "FAIL: build lms args helper invocation failed"
    return 1
  fi

  expected_lms_argv=(chat test-model -s "$system_prompt" -p "$user_prompt")
  expected_lms_args="${(@q)expected_lms_argv}"
  assert_eq "$expected_lms_args" "$lms_args" "build lms args special characters" || return 1
}

test_build_command_generation_system_prompt() {
  local current_dir
  local expected
  local actual

  if ! assert_helper_available _zshguy_build_command_generation_system_prompt "build command generation system prompt"; then
    return 1
  fi

  current_dir="$(pwd)"
  expected="You are a zsh command generator for an interactive terminal widget. The user describes what they want to do in natural language. Output ONLY a single zsh command that directly and minimally satisfies the request. Do not explain. Do not use markdown. Do not use code fences. Do not include multiple options. Do not add extra transformations, compression, deletion, extraction, or side effects unless the user explicitly asked for them. Prefer common, simple commands that a human would naturally write. If the user asks to list or filter files, prefer straightforward tools such as find, ls, or grep. Interpret ambiguous requests conservatively. If the user asks to list files with a given extension, return a file-listing command for that extension, not an archive or conversion command. Examples: 'list only .sh files' -> 'find . -type f -name '\''*.sh'\''' ; 'extract a tar.gz archive' -> 'tar -xvf archive.tar.gz'. No trailing newline. The command should work on macOS and Linux. Current directory: $current_dir"

  if ! actual="$(_zshguy_build_command_generation_system_prompt)"; then
    print -ru2 -- "FAIL: build command generation system prompt helper invocation failed"
    return 1
  fi

  assert_eq "$expected" "$actual" "build command generation system prompt" || return 1
}

test_build_insert_system_prompt() {
  local prefix='git '
  local suffix='status'
  local current_dir
  local expected
  local actual

  if ! assert_helper_available _zshguy_build_insert_system_prompt "build insert system prompt"; then
    return 1
  fi

  current_dir="$(pwd)"
  expected="You are a zsh command generator for an interactive terminal widget. The user has partially written a command line. The text before the cursor is: $prefix
The text after the cursor is: $suffix
Output ONLY the text to insert at the cursor position. Do not explain. Do not use markdown. Do not use code fences. Do not repeat the full command line. Do not change text outside the insertion. Keep the insertion minimal and directly relevant to the user's request. No trailing newline. The inserted text combined with the existing text should form a valid zsh command. Current directory: $current_dir"

  if ! actual="$(_zshguy_build_insert_system_prompt "$prefix" "$suffix")"; then
    print -ru2 -- "FAIL: build insert system prompt helper invocation failed"
    return 1
  fi

  assert_eq "$expected" "$actual" "build insert system prompt" || return 1
}

test_run_lms_preserves_special_characters() {
  local lms_output
  local lms_capture_file
  local -a lms_argv
  local -a expected_lms_argv
  local system_prompt=$'sys with spaces "quotes" * glob\nline'
  local user_prompt=$'user with spaces \'single quotes\' * glob\nline'
  local ZSHGUY_MODEL="test-model"

  if ! assert_helper_available _zshguy_run_lms "run lms"; then
    return 1
  fi

  lms_capture_file="$(mktemp "${TMPDIR:-/tmp}/zshguy-lms.XXXXXX")" || return 1
  lms() {
    printf '%s\0' "$@" >"$lms_capture_file"
    print -r -- "generated text"
  }

  if ! lms_output="$(_zshguy_run_lms "$system_prompt" "$user_prompt")"; then
    print -ru2 -- "FAIL: run lms helper invocation failed"
    return 1
  fi

  assert_eq "generated text" "$lms_output" "run lms special characters output" || return 1
  while IFS= read -r -d '' lms_arg; do
    lms_argv+=("$lms_arg")
  done <"$lms_capture_file"
  rm -f "$lms_capture_file"
  expected_lms_argv=(chat test-model -s "$system_prompt" -p "$user_prompt")
  assert_array_eq "run lms special characters" expected_lms_argv lms_argv || return 1
}

test_run_lms_strips_markdown_fences() {
  local lms_output
  local ZSHGUY_MODEL="test-model"

  if ! assert_helper_available _zshguy_run_lms "run lms"; then
    return 1
  fi

  lms() {
    print -r -- '```zsh'
    print -r -- 'ls -la'
    print -r -- '```'
  }

  if ! lms_output="$(_zshguy_run_lms "sys" "user")"; then
    print -ru2 -- "FAIL: run lms markdown fence normalization failed"
    return 1
  fi

  assert_eq "ls -la" "$lms_output" "run lms strips markdown fences" || return 1
}

test_run_lms_strips_think_block_and_trailing_tokens() {
  local lms_output
  local ZSHGUY_MODEL="test-model"

  if ! assert_helper_available _zshguy_run_lms "run lms"; then
    return 1
  fi

  lms() {
    print -r -- '<think>'
    print -r -- 'hidden reasoning'
    print -r -- '</think>'
    print -r -- ''
    print -r -- 'ls'
    print -r -- '<|im_end|>'
  }

  if ! lms_output="$(_zshguy_run_lms "sys" "user")"; then
    print -ru2 -- "FAIL: run lms think block normalization failed"
    return 1
  fi

  assert_eq "ls" "$lms_output" "run lms strips think block and trailing tokens" || return 1
}

test_run_lms_rejects_multiline_postamble() {
  local lms_status_file
  local lms_status=0
  local lms_output
  local ZSHGUY_MODEL="test-model"

  if ! assert_helper_available _zshguy_run_lms "run lms"; then
    return 1
  fi

  lms() {
    print -r -- 'ls -l'
    print -r -- 'This command lists files'
  }

  lms_status_file="$(mktemp "${TMPDIR:-/tmp}/zshguy-lms-status.XXXXXX")" || return 1
  lms_output="$({
    if _zshguy_run_lms "sys" "user"; then
      print -r -- 0 >"$lms_status_file"
    else
      print -r -- $? >"$lms_status_file"
    fi
  })"
  lms_status="$(<"$lms_status_file")"
  rm -f "$lms_status_file"

  assert_eq "1" "$lms_status" "run lms multiline postamble status" || return 1
  assert_eq "" "$lms_output" "run lms rejects multiline postamble output" || return 1
}

test_mode_for_buffer() {
  local prompt_mode
  local BUFFER="git status"

  if ! assert_helper_available _zshguy_mode_for_buffer "mode for buffer"; then
    return 1
  fi

  if ! prompt_mode="$(_zshguy_mode_for_buffer)"; then
    print -ru2 -- "FAIL: mode for buffer helper invocation failed"
    return 1
  fi

  assert_eq "insert" "$prompt_mode" "mode selection for partial input" || return 1

  BUFFER=""

  if ! prompt_mode="$(_zshguy_mode_for_buffer)"; then
    print -ru2 -- "FAIL: mode for buffer helper invocation failed"
    return 1
  fi

  assert_eq "empty" "$prompt_mode" "mode selection for empty input" || return 1
}

test_apply_insert() {
  local BUFFER="git status"
  local -i CURSOR=4

  if ! assert_helper_available _zshguy_apply_insert "apply insert"; then
    return 1
  fi

  if ! _zshguy_apply_insert " checkout"; then
    print -ru2 -- "FAIL: apply insert helper invocation failed"
    return 1
  fi

  assert_eq "git  checkoutstatus" "$BUFFER" "buffer after insert" || return 1
  assert_eq "13" "$CURSOR" "cursor after insert" || return 1
}

test_handle_generation_error_preserves_buffer_and_cursor() {
  local BUFFER="git status"
  local -i CURSOR=4

  if ! assert_helper_available _zshguy_handle_generation_error "handle generation error"; then
    return 1
  fi

  if ! _zshguy_handle_generation_error; then
    print -ru2 -- "FAIL: handle generation error helper invocation failed"
    return 1
  fi

  assert_eq "git status" "$BUFFER" "buffer after generation error" || return 1
  assert_eq "4" "$CURSOR" "cursor after generation error" || return 1
}

test_run_lms_failure_returns_stderr() {
  local lms_status_file
  local lms_status=0
  local lms_output
  local ZSHGUY_MODEL="test-model"

  if ! assert_helper_available _zshguy_run_lms "run lms"; then
    return 1
  fi

  lms() {
    print -ru2 -- "boom"
    return 1
  }

  lms_status_file="$(mktemp "${TMPDIR:-/tmp}/zshguy-lms-status.XXXXXX")" || return 1
  lms_output="$({
    if _zshguy_run_lms "sys" "user"; then
      print -r -- 0 >"$lms_status_file"
    else
      print -r -- $? >"$lms_status_file"
    fi
  })"
  lms_status="$(<"$lms_status_file")"
  rm -f "$lms_status_file"

  assert_eq "1" "$lms_status" "run lms failure status" || return 1
  assert_eq "boom" "$lms_output" "run lms failure returns stderr" || return 1
}

test_widget_skips_empty_prompt_without_mutation() {
  local BUFFER="git status"
  local -i CURSOR=4
  local -i expected_cursor=$CURSOR
  local expected_buffer=$BUFFER

  if ! assert_helper_available _zshguy_widget "widget"; then
    return 1
  fi

  if ! _zshguy_widget; then
    print -ru2 -- "FAIL: widget invocation failed for empty prompt skip path"
    return 1
  fi

  assert_eq "[zshguy] " "$BUFFER" "widget buffer for prompt mode" || return 1
  assert_eq "9" "$CURSOR" "widget cursor for prompt mode" || return 1
  if ! _zshguy_cancel; then
    print -ru2 -- "FAIL: cancel helper invocation failed for prompt mode"
    return 1
  fi
  assert_eq "$expected_buffer" "$BUFFER" "widget buffer restored after cancel" || return 1
  assert_eq "$expected_cursor" "$CURSOR" "widget cursor restored after cancel" || return 1
}

test_widget_uses_command_generation_flow_for_empty_buffer() {
  local BUFFER=""
  local -i CURSOR=0
  local lms_capture_file
  local -a lms_argv
  local -a expected_lms_argv
  local tty_prompt_capture_file
  local tty_prompt_value

  if ! assert_helper_available _zshguy_widget "widget"; then
    return 1
  fi

  _zshguy_build_command_generation_system_prompt() {
    print -r -- "command-generation-system"
  }
  _zshguy_build_insert_system_prompt() {
    print -r -- "insert-system"
  }
  _zshguy_run_lms() {
    printf '%s\0' "$@" >"$lms_capture_file"
    print -r -- "git status"
  }
  _zshguy_redraw_prompt() {
    printf '%s\0' "$BUFFER" >>"$tty_prompt_capture_file"
  }

  lms_capture_file="$(mktemp "${TMPDIR:-/tmp}/zshguy-widget.XXXXXX")" || return 1
  tty_prompt_capture_file="$(mktemp "${TMPDIR:-/tmp}/zshguy-tty-prompt.XXXXXX")" || return 1

  if ! _zshguy_widget; then
    print -ru2 -- "FAIL: widget invocation failed for empty buffer"
    rm -f "$lms_capture_file"
    rm -f "$tty_prompt_capture_file"
    return 1
  fi

  BUFFER="[zshguy] describe the command"
  CURSOR=${#BUFFER}

  if ! _zshguy_accept_line; then
    print -ru2 -- "FAIL: accept-line helper invocation failed for empty buffer"
    rm -f "$lms_capture_file"
    rm -f "$tty_prompt_capture_file"
    return 1
  fi

  while IFS= read -r -d '' lms_arg; do
    lms_argv+=("$lms_arg")
  done <"$lms_capture_file"
  rm -f "$lms_capture_file"
  tty_prompt_value="$(tr '\0' '\n' <"$tty_prompt_capture_file")"
  rm -f "$tty_prompt_capture_file"
  expected_lms_argv=("command-generation-system" "describe the command")
  assert_array_eq "widget argv for empty buffer" expected_lms_argv lms_argv || return 1
  if [[ "$tty_prompt_value" != *"[zshguy] "* ]]; then
    print -ru2 -- "FAIL: widget prompt mode redraw for empty buffer"
    print -ru2 -- "  actual:   $tty_prompt_value"
    return 1
  fi
  if [[ "$tty_prompt_value" != *"[zshguy] describe the command generating..."* ]]; then
    print -ru2 -- "FAIL: widget generating redraw for empty buffer"
    print -ru2 -- "  actual:   $tty_prompt_value"
    return 1
  fi
  assert_eq "git status" "$BUFFER" "widget buffer for empty buffer" || return 1
  assert_eq "10" "$CURSOR" "widget cursor for empty buffer" || return 1
}

test_widget_uses_insert_flow_for_existing_input() {
  local BUFFER="git status"
  local -i CURSOR=4
  local lms_capture_file
  local -a lms_argv
  local -a expected_lms_argv

  if ! assert_helper_available _zshguy_widget "widget"; then
    return 1
  fi

  _zshguy_build_command_generation_system_prompt() {
    print -r -- "command-generation-system"
  }
  _zshguy_build_insert_system_prompt() {
    print -r -- "insert-system"
  }
  _zshguy_redraw_prompt() {
    return 0
  }
  _zshguy_run_lms() {
    printf '%s\0' "$@" >"$lms_capture_file"
    print -r -- " checkout"
  }

  lms_capture_file="$(mktemp "${TMPDIR:-/tmp}/zshguy-widget.XXXXXX")" || return 1

  if ! _zshguy_widget; then
    print -ru2 -- "FAIL: widget invocation failed for existing input"
    rm -f "$lms_capture_file"
    return 1
  fi

  BUFFER="[zshguy] checkout"
  CURSOR=${#BUFFER}

  if ! _zshguy_accept_line; then
    print -ru2 -- "FAIL: accept-line helper invocation failed for existing input"
    rm -f "$lms_capture_file"
    return 1
  fi

  while IFS= read -r -d '' lms_arg; do
    lms_argv+=("$lms_arg")
  done <"$lms_capture_file"
  rm -f "$lms_capture_file"
  expected_lms_argv=("insert-system" "checkout")
  assert_array_eq "widget argv for existing input" expected_lms_argv lms_argv || return 1
  assert_eq "git  checkoutstatus" "$BUFFER" "widget buffer for existing input" || return 1
  assert_eq "13" "$CURSOR" "widget cursor for existing input" || return 1
}

test_widget_shows_inline_generation_display_and_defers_buffer_mutation_until_success() {
  local BUFFER="git status"
  local -i CURSOR=4
  local -a redraw_calls
  local redraw_capture_file
  local lms_capture_file
  local expected_buffer="git  checkoutstatus"

  if ! assert_helper_available _zshguy_widget "widget"; then
    return 1
  fi

  _zshguy_build_command_generation_system_prompt() {
    print -r -- "command-generation-system"
  }
  _zshguy_build_insert_system_prompt() {
    print -r -- "insert-system"
  }
  _zshguy_redraw_prompt() {
    printf '%s\0' "$BUFFER" >>"$redraw_capture_file"
  }
  _zshguy_run_lms() {
    if [[ "$BUFFER" != "[zshguy] describe the command generating..." ]]; then
      print -ru2 -- "FAIL: buffer mutated before generation completed"
      print -ru2 -- "  actual:   $BUFFER"
      return 1
    fi
    printf '%s\0' "$@" >>"$lms_capture_file"
    print -r -- " checkout"
  }

  redraw_capture_file="$(mktemp "${TMPDIR:-/tmp}/zshguy-widget-redraw.XXXXXX")" || return 1
  lms_capture_file="$(mktemp "${TMPDIR:-/tmp}/zshguy-widget-lms.XXXXXX")" || return 1

  if ! _zshguy_widget; then
    print -ru2 -- "FAIL: widget invocation failed for inline generation display path"
    rm -f "$redraw_capture_file"
    rm -f "$lms_capture_file"
    return 1
  fi

  BUFFER="[zshguy] describe the command"
  CURSOR=${#BUFFER}

  if ! _zshguy_accept_line; then
    print -ru2 -- "FAIL: accept-line helper invocation failed for inline generation display path"
    rm -f "$redraw_capture_file"
    rm -f "$lms_capture_file"
    return 1
  fi

  while IFS= read -r -d '' redraw_call; do
    redraw_calls+=("$redraw_call")
  done <"$redraw_capture_file"
  rm -f "$redraw_capture_file"
  assert_eq 3 "${#redraw_calls[@]}" "widget redraw call count on success" || return 1
  assert_eq "[zshguy] " "$redraw_calls[1]" "widget prompt mode redraw on success" || return 1
  assert_eq "[zshguy] describe the command generating..." "$redraw_calls[2]" "widget generating redraw payload on success" || return 1
  assert_eq "git  checkoutstatus" "$redraw_calls[3]" "widget final redraw payload on success" || return 1
  if [[ ! -s "$lms_capture_file" ]]; then
    print -ru2 -- "FAIL: widget should call run lms on success path"
    rm -f "$lms_capture_file"
    return 1
  fi
  rm -f "$lms_capture_file"
  assert_eq "$expected_buffer" "$BUFFER" "widget buffer after inline generation display success" || return 1
  assert_eq "13" "$CURSOR" "widget cursor after inline generation display success" || return 1
}

test_widget_clears_inline_generation_display_on_lms_failure() {
  local BUFFER="git status"
  local -i CURSOR=4
  local redraw_capture_file
  local -a redraw_calls
  local lms_capture_file

  if ! assert_helper_available _zshguy_widget "widget"; then
    return 1
  fi

  _zshguy_build_command_generation_system_prompt() {
    print -r -- "command-generation-system"
  }
  _zshguy_build_insert_system_prompt() {
    print -r -- "insert-system"
  }
  _zshguy_redraw_prompt() {
    printf '%s\0' "$BUFFER" >>"$redraw_capture_file"
  }
  _zshguy_run_lms() {
    printf '%s\0' "$@" >>"$lms_capture_file"
    return 1
  }

  redraw_capture_file="$(mktemp "${TMPDIR:-/tmp}/zshguy-widget-redraw.XXXXXX")" || return 1
  lms_capture_file="$(mktemp "${TMPDIR:-/tmp}/zshguy-widget-lms.XXXXXX")" || return 1

  if ! _zshguy_widget; then
    print -ru2 -- "FAIL: widget invocation failed for lms failure cleanup path"
    rm -f "$redraw_capture_file"
    rm -f "$lms_capture_file"
    return 1
  fi

  BUFFER="[zshguy] describe the command"
  CURSOR=${#BUFFER}

  if _zshguy_accept_line; then
    print -ru2 -- "FAIL: accept-line helper invocation should have failed for lms failure cleanup path"
    rm -f "$redraw_capture_file"
    rm -f "$lms_capture_file"
    return 1
  fi

  while IFS= read -r -d '' redraw_call; do
    redraw_calls+=("$redraw_call")
  done <"$redraw_capture_file"
  rm -f "$redraw_capture_file"
  assert_eq 3 "${#redraw_calls[@]}" "widget redraw call count on lms failure" || return 1
  assert_eq "[zshguy] " "$redraw_calls[1]" "widget prompt mode redraw on lms failure" || return 1
  assert_eq "[zshguy] describe the command generating..." "$redraw_calls[2]" "widget generating redraw payload on lms failure" || return 1
  assert_eq "git status" "$redraw_calls[3]" "widget restored redraw payload on lms failure" || return 1
  if [[ ! -s "$lms_capture_file" ]]; then
    print -ru2 -- "FAIL: widget should call run lms on failure path"
    rm -f "$lms_capture_file"
    return 1
  fi
  rm -f "$lms_capture_file"
  assert_eq "git status" "$BUFFER" "widget buffer after lms failure" || return 1
  assert_eq "4" "$CURSOR" "widget cursor after lms failure" || return 1
}

test_widget_cleans_prompt_line_on_tty_read_failure() {
  local BUFFER="git status"
  local -i CURSOR=4
  local -i expected_cursor=$CURSOR
  local expected_buffer=$BUFFER

  if ! assert_helper_available _zshguy_widget "widget"; then
    return 1
  fi

  _zshguy_build_command_generation_system_prompt() {
    print -r -- "command-generation-system"
  }
  _zshguy_build_insert_system_prompt() {
    print -r -- "insert-system"
  }
  _zshguy_run_lms() {
    print -ru2 -- "FAIL: run lms should not be called when tty prompt read fails"
    return 1
  }
  _zshguy_redraw_prompt() {
    return 0
  }

  if ! _zshguy_widget; then
    print -ru2 -- "FAIL: widget invocation failed for tty read failure cleanup path"
    return 1
  fi

  assert_eq "[zshguy] " "$BUFFER" "widget buffer after entering prompt mode" || return 1
  assert_eq "9" "$CURSOR" "widget cursor after entering prompt mode" || return 1

  if ! _zshguy_cancel; then
    print -ru2 -- "FAIL: cancel helper invocation failed for tty read failure cleanup path"
    return 1
  fi

  assert_eq "$expected_buffer" "$BUFFER" "widget buffer restored after cancel path" || return 1
  assert_eq "$expected_cursor" "$CURSOR" "widget cursor restored after cancel path" || return 1
}

test_delete_guard_blocks_prefix_deletion() {
  local BUFFER="[zshguy] "
  local -i CURSOR=9

  if ! assert_helper_available _zshguy_backward_delete_char "backward delete char"; then
    return 1
  fi

  zle() {
    print -ru2 -- "FAIL: builtin backward delete should not run at prefix boundary"
    return 1
  }

  typeset -g _zshguy_state="collecting_prompt"

  if ! _zshguy_backward_delete_char; then
    print -ru2 -- "FAIL: backward delete guard invocation failed"
    return 1
  fi

  assert_eq "[zshguy] " "$BUFFER" "backward delete guard preserves prefix buffer" || return 1
  assert_eq "9" "$CURSOR" "backward delete guard preserves prefix cursor" || return 1
}

test_delete_guard_allows_query_deletion() {
  local BUFFER="[zshguy] abc"
  local -i CURSOR=12

  if ! assert_helper_available _zshguy_backward_delete_char "backward delete char"; then
    return 1
  fi

  zle() {
    if [[ "$1" != ".backward-delete-char" ]]; then
      print -ru2 -- "FAIL: unexpected zle widget"
      print -ru2 -- "  actual:   $1"
      return 1
    fi
    BUFFER="${BUFFER:0:$(( CURSOR - 1 ))}${BUFFER:$CURSOR}"
    CURSOR=$(( CURSOR - 1 ))
  }

  typeset -g _zshguy_state="collecting_prompt"

  if ! _zshguy_backward_delete_char; then
    print -ru2 -- "FAIL: backward delete invocation failed for query content"
    return 1
  fi

  assert_eq "[zshguy] ab" "$BUFFER" "backward delete removes query character" || return 1
  assert_eq "11" "$CURSOR" "backward delete updates cursor in query" || return 1
}

test_delete_guard_preserves_prefix_for_line_and_word_kills() {
  local BUFFER="[zshguy] abc"
  local -i CURSOR=12

  if ! assert_helper_available _zshguy_backward_kill_word "backward kill word"; then
    return 1
  fi

  zle() {
    case "$1" in
      .backward-kill-word|.kill-whole-line)
        BUFFER=""
        CURSOR=0
        ;;
      *)
        print -ru2 -- "FAIL: unexpected zle widget"
        print -ru2 -- "  actual:   $1"
        return 1
        ;;
    esac
  }

  typeset -g _zshguy_state="collecting_prompt"

  if ! _zshguy_backward_kill_word; then
    print -ru2 -- "FAIL: backward kill word invocation failed"
    return 1
  fi

  assert_eq "[zshguy] " "$BUFFER" "backward kill word restores prefix" || return 1
  assert_eq "9" "$CURSOR" "backward kill word restores prefix cursor" || return 1

  BUFFER="[zshguy] abc"
  CURSOR=12

  if ! _zshguy_kill_whole_line; then
    print -ru2 -- "FAIL: kill whole line invocation failed"
    return 1
  fi

  assert_eq "[zshguy] " "$BUFFER" "kill whole line restores prefix" || return 1
  assert_eq "9" "$CURSOR" "kill whole line restores prefix cursor" || return 1
}

test_delete_guard_falls_through_outside_prompt_mode() {
  local BUFFER="plain text"
  local -i CURSOR=10
  local zle_widget_called=""

  if ! assert_helper_available _zshguy_backward_delete_char "backward delete char"; then
    return 1
  fi

  zle() {
    zle_widget_called=$1
  }

  typeset -g _zshguy_state=""

  if ! _zshguy_backward_delete_char; then
    print -ru2 -- "FAIL: backward delete fallthrough invocation failed"
    return 1
  fi

  assert_eq ".backward-delete-char" "$zle_widget_called" "backward delete fallthrough widget" || return 1
}

test_widget_registers_in_interactive_shell() {
  local registration_state

  registration_state="$(
    zsh -f -ic "source ${(q)ZSHGUY_SH}; print -r -- \${+widgets[zshguy-widget]}"
  )" || {
    print -ru2 -- "FAIL: widget registration check failed"
    return 1
  }

  assert_eq "1" "$registration_state" "widget registration in interactive shell" || return 1
}

run_test() {
  local test_name=$1

  if "$test_name"; then
    (( ++TESTS_PASSED ))
    print -r -- "ok - $test_name"
  else
    (( ++TESTS_FAILED ))
    print -r -- "not ok - $test_name"
  fi
}

main() {
  run_test test_plugin_entrypoint_exists
  run_test test_compat_entrypoint_exists
  run_test test_plugin_entrypoint_can_be_sourced_twice
  run_test test_plugin_entrypoint_skips_widget_registration_in_non_interactive_shell
  run_test test_run_lms_with_model
  run_test test_run_lms_without_model
  run_test test_build_lms_args
  run_test test_build_lms_args_preserves_special_characters
  run_test test_build_command_generation_system_prompt
  run_test test_build_insert_system_prompt
  run_test test_run_lms_preserves_special_characters
  run_test test_run_lms_strips_markdown_fences
  run_test test_run_lms_strips_think_block_and_trailing_tokens
  run_test test_run_lms_rejects_multiline_postamble
  run_test test_mode_for_buffer
  run_test test_apply_insert
  run_test test_handle_generation_error_preserves_buffer_and_cursor
  run_test test_run_lms_failure_returns_stderr
  run_test test_widget_uses_command_generation_flow_for_empty_buffer
  run_test test_widget_uses_insert_flow_for_existing_input
  run_test test_widget_shows_inline_generation_display_and_defers_buffer_mutation_until_success
  run_test test_widget_clears_inline_generation_display_on_lms_failure
  run_test test_widget_cleans_prompt_line_on_tty_read_failure
  run_test test_delete_guard_blocks_prefix_deletion
  run_test test_delete_guard_allows_query_deletion
  run_test test_delete_guard_preserves_prefix_for_line_and_word_kills
  run_test test_delete_guard_falls_through_outside_prompt_mode
  run_test test_widget_registers_in_interactive_shell
  run_test test_widget_skips_empty_prompt_without_mutation

  print -r -- ""
  print -r -- "$TESTS_PASSED passed, $TESTS_FAILED failed"

  (( TESTS_FAILED == 0 ))
}

main "$@"
