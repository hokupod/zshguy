#!/usr/bin/env zsh

emulate -L zsh
setopt no_unset
setopt pipefail
setopt errexit

typeset -r TEST_DIR="${0:A:h}"
typeset -r ZSHGUY_SH="${TEST_DIR:h}/zshguy.sh"
typeset ZSHGUY_TEST_SETUP_STATE

if [[ -f "$ZSHGUY_SH" ]]; then
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
  expected="You are a zsh command generator. The user describes what they want to do in natural language. Output ONLY a single zsh command (no explanation, no markdown, no code fences, no trailing newline). The command should work on macOS and Linux. Current directory: $current_dir"

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
  expected="You are a zsh command generator. The user has partially written a command line. The text before the cursor is: $prefix
The text after the cursor is: $suffix
Output ONLY the text to insert at the cursor position (no explanation, no markdown, no code fences, no trailing newline). The inserted text combined with the existing text should form a valid zsh command. Current directory: $current_dir"

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

test_run_lms_failure_suppresses_stderr() {
  local lms_status_file
  local lms_status=0
  local lms_output
  local lms_stderr
  local ZSHGUY_MODEL="test-model"

  if ! assert_helper_available _zshguy_run_lms "run lms"; then
    return 1
  fi

  lms() {
    print -ru2 -- "boom"
    return 1
  }

  lms_status_file="$(mktemp "${TMPDIR:-/tmp}/zshguy-lms-status.XXXXXX")" || return 1
  lms_stderr="$({
    if lms_output="$(_zshguy_run_lms "sys" "user")"; then
      print -r -- 0 >"$lms_status_file"
    else
      print -r -- $? >"$lms_status_file"
    fi
  } 2>&1)"
  lms_status="$(<"$lms_status_file")"
  rm -f "$lms_status_file"

  assert_eq "1" "$lms_status" "run lms failure status" || return 1
  assert_eq "" "$lms_output" "run lms failure output" || return 1
  assert_eq "" "$lms_stderr" "run lms stderr suppression" || return 1
}

test_widget_skips_empty_prompt_without_mutation() {
  local BUFFER="git status"
  local -i CURSOR=4
  local -i expected_cursor=$CURSOR
  local expected_buffer=$BUFFER
  local run_lms_capture_file

  if ! assert_helper_available _zshguy_widget "widget"; then
    return 1
  fi

  _zshguy_build_command_generation_system_prompt() {
    print -r -- "command-generation-system"
  }
  _zshguy_build_insert_system_prompt() {
    print -r -- "insert-system"
  }
  _zshguy_read_tty_prompt() {
    print -r -- ""
  }
  _zshguy_notify_tty() {
    return 0
  }

  run_lms_capture_file="$(mktemp "${TMPDIR:-/tmp}/zshguy-widget-run-lms.XXXXXX")" || return 1
  _zshguy_run_lms() {
    print -r -- "called" >"$run_lms_capture_file"
    return 1
  }

  if ! _zshguy_widget; then
    print -ru2 -- "FAIL: widget invocation failed for empty prompt skip path"
    rm -f "$run_lms_capture_file"
    return 1
  fi

  assert_eq "$expected_buffer" "$BUFFER" "widget buffer for empty prompt skip path" || return 1
  assert_eq "$expected_cursor" "$CURSOR" "widget cursor for empty prompt skip path" || return 1
  assert_eq "" "$(<"$run_lms_capture_file")" "widget should not call run lms for empty prompt" || return 1
  rm -f "$run_lms_capture_file"
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
  _zshguy_read_tty_prompt() {
    printf '%s' "$1" >"$tty_prompt_capture_file"
    print -r -- "describe the command"
  }
  _zshguy_notify_tty() {
    return 0
  }
  _zshguy_run_lms() {
    printf '%s\0' "$@" >"$lms_capture_file"
    print -r -- "git status"
  }

  lms_capture_file="$(mktemp "${TMPDIR:-/tmp}/zshguy-widget.XXXXXX")" || return 1
  tty_prompt_capture_file="$(mktemp "${TMPDIR:-/tmp}/zshguy-tty-prompt.XXXXXX")" || return 1

  if ! _zshguy_widget; then
    print -ru2 -- "FAIL: widget invocation failed for empty buffer"
    rm -f "$lms_capture_file"
    rm -f "$tty_prompt_capture_file"
    return 1
  fi

  while IFS= read -r -d '' lms_arg; do
    lms_argv+=("$lms_arg")
  done <"$lms_capture_file"
  rm -f "$lms_capture_file"
  tty_prompt_value="$(<"$tty_prompt_capture_file")"
  rm -f "$tty_prompt_capture_file"
  expected_lms_argv=("command-generation-system" "describe the command")
  assert_array_eq "widget argv for empty buffer" expected_lms_argv lms_argv || return 1
  assert_eq "[zshguy] " "$tty_prompt_value" "widget tty prompt for empty buffer" || return 1
  assert_eq "git status" "$BUFFER" "widget buffer for empty buffer" || return 1
  assert_eq "10" "$CURSOR" "widget cursor for empty buffer" || return 1
}

test_widget_uses_insert_flow_for_existing_input() {
  local BUFFER="git status"
  local -i CURSOR=4
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
  _zshguy_read_tty_prompt() {
    printf '%s' "$1" >"$tty_prompt_capture_file"
    print -r -- "checkout"
  }
  _zshguy_notify_tty() {
    return 0
  }
  _zshguy_run_lms() {
    printf '%s\0' "$@" >"$lms_capture_file"
    print -r -- " checkout"
  }

  lms_capture_file="$(mktemp "${TMPDIR:-/tmp}/zshguy-widget.XXXXXX")" || return 1
  tty_prompt_capture_file="$(mktemp "${TMPDIR:-/tmp}/zshguy-tty-prompt.XXXXXX")" || return 1

  if ! _zshguy_widget; then
    print -ru2 -- "FAIL: widget invocation failed for existing input"
    rm -f "$lms_capture_file"
    rm -f "$tty_prompt_capture_file"
    return 1
  fi

  while IFS= read -r -d '' lms_arg; do
    lms_argv+=("$lms_arg")
  done <"$lms_capture_file"
  rm -f "$lms_capture_file"
  tty_prompt_value="$(<"$tty_prompt_capture_file")"
  rm -f "$tty_prompt_capture_file"
  expected_lms_argv=("insert-system" "checkout")
  assert_array_eq "widget argv for existing input" expected_lms_argv lms_argv || return 1
  assert_eq "[zshguy] " "$tty_prompt_value" "widget tty prompt for existing input" || return 1
  assert_eq "git  checkoutstatus" "$BUFFER" "widget buffer for existing input" || return 1
  assert_eq "13" "$CURSOR" "widget cursor for existing input" || return 1
}

test_widget_clears_generation_line_on_lms_failure() {
  local BUFFER="git status"
  local -i CURSOR=4
  local -a notify_calls
  local notify_capture_file
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
  _zshguy_read_tty_prompt() {
    print -r -- "describe the command"
  }
  _zshguy_notify_tty() {
    printf '%s\0' "$1" >>"$notify_capture_file"
  }
  _zshguy_run_lms() {
    printf '%s\0' "$@" >>"$lms_capture_file"
    return 1
  }

  notify_capture_file="$(mktemp "${TMPDIR:-/tmp}/zshguy-widget-notify.XXXXXX")" || return 1
  lms_capture_file="$(mktemp "${TMPDIR:-/tmp}/zshguy-widget-lms.XXXXXX")" || return 1

  if ! _zshguy_widget; then
    print -ru2 -- "FAIL: widget invocation failed for lms failure cleanup path"
    rm -f "$notify_capture_file"
    rm -f "$lms_capture_file"
    return 1
  fi

  while IFS= read -r -d '' notify_call; do
    notify_calls+=("$notify_call")
  done <"$notify_capture_file"
  rm -f "$notify_capture_file"
  assert_eq 2 "${#notify_calls[@]}" "widget notify call count on lms failure" || return 1
  assert_eq "[zshguy] describe the command generating..." "$notify_calls[1]" "widget notify generation message on lms failure" || return 1
  assert_eq $'\r\e[K' "$notify_calls[2]" "widget notify cleanup on lms failure" || return 1
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
  local -a notify_calls
  local notify_capture_file

  if ! assert_helper_available _zshguy_widget "widget"; then
    return 1
  fi

  _zshguy_build_command_generation_system_prompt() {
    print -r -- "command-generation-system"
  }
  _zshguy_build_insert_system_prompt() {
    print -r -- "insert-system"
  }
  _zshguy_read_tty_prompt() {
    return 1
  }
  _zshguy_notify_tty() {
    printf '%s\0' "$1" >>"$notify_capture_file"
  }
  _zshguy_run_lms() {
    print -ru2 -- "FAIL: run lms should not be called when tty prompt read fails"
    return 1
  }

  notify_capture_file="$(mktemp "${TMPDIR:-/tmp}/zshguy-widget-notify.XXXXXX")" || return 1

  if ! _zshguy_widget; then
    print -ru2 -- "FAIL: widget invocation failed for tty read failure cleanup path"
    rm -f "$notify_capture_file"
    return 1
  fi

  while IFS= read -r -d '' notify_call; do
    notify_calls+=("$notify_call")
  done <"$notify_capture_file"
  rm -f "$notify_capture_file"
  assert_eq 1 "${#notify_calls[@]}" "widget notify call count on tty read failure" || return 1
  assert_eq $'\r\e[K' "$notify_calls[1]" "widget notify cleanup on tty read failure" || return 1
  assert_eq "$expected_buffer" "$BUFFER" "widget buffer after tty read failure" || return 1
  assert_eq "$expected_cursor" "$CURSOR" "widget cursor after tty read failure" || return 1
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
  run_test test_run_lms_with_model
  run_test test_run_lms_without_model
  run_test test_build_lms_args
  run_test test_build_lms_args_preserves_special_characters
  run_test test_build_command_generation_system_prompt
  run_test test_build_insert_system_prompt
  run_test test_run_lms_preserves_special_characters
  run_test test_mode_for_buffer
  run_test test_apply_insert
  run_test test_handle_generation_error_preserves_buffer_and_cursor
  run_test test_run_lms_failure_suppresses_stderr
  run_test test_widget_uses_command_generation_flow_for_empty_buffer
  run_test test_widget_uses_insert_flow_for_existing_input
  run_test test_widget_clears_generation_line_on_lms_failure
  run_test test_widget_cleans_prompt_line_on_tty_read_failure
  run_test test_widget_registers_in_interactive_shell
  run_test test_widget_skips_empty_prompt_without_mutation

  print -r -- ""
  print -r -- "$TESTS_PASSED passed, $TESTS_FAILED failed"

  (( TESTS_FAILED == 0 ))
}

main "$@"
