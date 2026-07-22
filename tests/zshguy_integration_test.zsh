#!/usr/bin/env zsh

emulate -LR zsh
setopt no_unset
setopt pipefail

zmodload zsh/zpty
zmodload zsh/zselect

typeset -r TEST_DIR="${0:A:h}"
typeset -r FIXTURE_PATH="${ZSHGUY_TEST_FIXTURE:-$TEST_DIR/fixtures/zle-plugin-stack.zsh}"
typeset -r PLUGIN_PATH="${ZSHGUY_TEST_PLUGIN:-${TEST_DIR:h}/zshguy.plugin.zsh}"
typeset -gi TESTS_PASSED=0
typeset -gi TESTS_FAILED=0
typeset -g ZPTY_SESSION=""
typeset -g ZPTY_OUTPUT=""
typeset -gi ZPTY_FD=-1

TRAPEXIT() {
  if [[ -n $ZPTY_SESSION ]]; then
    zpty -d "$ZPTY_SESSION" >/dev/null 2>&1 || true
  fi
}

_zpty_start() {
  local session=$1

  ZPTY_OUTPUT=""
  zpty -b -e "$session" env TERM=dumb PS1=__ZPTY_READY__ zsh -dfi || return 1
  ZPTY_SESSION=$session
  ZPTY_FD=$REPLY
}

_zpty_stop() {
  local session=$1

  zpty -w "$session" exit >/dev/null 2>&1 || true
  zpty -d "$session" >/dev/null 2>&1 || true
  ZPTY_SESSION=""
  ZPTY_FD=-1
  ZPTY_OUTPUT=""
}

_zpty_drain() {
  local session=$1
  local chunk

  while zpty -r -t "$session" chunk; do
    ZPTY_OUTPUT+=$chunk
  done
}

_zpty_fail_on_sentinel() {
  local sentinel
  local -a sentinels=(
    __STARTUP_FAIL__
    __FIXTURE_FAIL__
    __PLUGIN_FAIL__
    __NESTED_AUTOSUGGEST__
  )

  for sentinel in "${sentinels[@]}"; do
    if [[ $ZPTY_OUTPUT == *"$sentinel"* ]]; then
      print -ru2 -- "FAIL: interactive shell emitted $sentinel"
      print -ru2 -- "  output: ${(V)ZPTY_OUTPUT}"
      return 1
    fi
  done
}

_zpty_expect() {
  local session=$1
  local expected=$2
  local label=$3
  local -i deadline=$(( SECONDS + 8 ))

  while (( SECONDS < deadline )); do
    _zpty_drain "$session"
    _zpty_fail_on_sentinel || return 1

    if [[ $ZPTY_OUTPUT == *"$expected"* ]]; then
      ZPTY_OUTPUT=${ZPTY_OUTPUT#*${(b)expected}}
      return 0
    fi

    zpty -t "$session" || break
    zselect -t 5 -r "$ZPTY_FD" >/dev/null 2>&1 || true
  done

  print -ru2 -- "FAIL: timed out waiting for $label"
  print -ru2 -- "  expected: $expected"
  print -ru2 -- "  output:   ${(V)ZPTY_OUTPUT}"
  return 1
}

_zpty_write_line() {
  local session=$1
  local line=$2

  zpty -w "$session" "$line"
}

_zpty_write_raw() {
  local session=$1
  local value=$2

  zpty -w -n "$session" "$value"
}

_verify_normal_input() {
  local session=$1

  _zpty_write_line "$session" "print -r -- '__NORMAL_''OK__'" || return 1
  _zpty_expect "$session" __NORMAL_OK__ "normal command execution" || return 1
  _zpty_expect "$session" __ZPTY_PROMPT__ "prompt after normal command"
}

_verify_abbreviation() {
  local session=$1

  _zpty_write_line "$session" zzq || return 1
  _zpty_expect "$session" __ABBR_OK__ "abbreviation expansion" || return 1
  _zpty_expect "$session" __ZPTY_PROMPT__ "prompt after abbreviation expansion"
}

_verify_backward_delete() {
  local session=$1

  _zpty_write_raw "$session" "typeset -g DELETE_PROBE=badX" || return 1
  _zpty_write_raw "$session" $'\x7f' || return 1
  _zpty_write_line "$session" '; print -r -- "__DELETE_${DELETE_PROBE}__"' || return 1
  _zpty_expect "$session" __DELETE_bad__ "backward-delete-char" || return 1
  _zpty_expect "$session" __ZPTY_PROMPT__ "prompt after backward-delete-char"
}

_configure_zshguy_widget() {
  local session=$1

  _zpty_write_line "$session" "lms() { print -r -- \"print -r -- '__GENERATED_''OK__'\"; }; bindkey '^X^J' zshguy-widget; bindkey '^G' send-break; print -r -- '__ZSHGUY_''READY__'" || return 1
  _zpty_expect "$session" __ZSHGUY_READY__ "zshguy test binding" || return 1
  _zpty_expect "$session" __ZPTY_PROMPT__ "prompt after zshguy test binding"
}

_verify_cancel_restores_buffer() {
  local session=$1

  _zpty_write_raw "$session" "print -r -- '__RESTORE_''OK__'" || return 1
  _zpty_write_raw "$session" $'\x18\x0a' || return 1
  _zpty_write_raw "$session" $'\x07' || return 1
  _zpty_write_raw "$session" $'\n' || return 1
  _zpty_expect "$session" __RESTORE_OK__ "buffer restoration after cancel" || return 1
  _zpty_expect "$session" __ZPTY_PROMPT__ "prompt after buffer restoration"
}

_verify_generation() {
  local session=$1

  _zpty_write_raw "$session" $'\x18\x0a' || return 1
  _zpty_write_line "$session" "generate a marker" || return 1
  _zpty_write_raw "$session" $'\n' || return 1
  _zpty_expect "$session" __GENERATED_OK__ "generated command execution" || return 1
  _zpty_expect "$session" __ZPTY_PROMPT__ "prompt after generated command"
}

_verify_stack() {
  local load_mode=$1
  local session="zshguy-${load_mode}"
  local shell_setup="unsetopt prompt_cr prompt_sp; PS1='__ZPTY_''PROMPT__'; RPS1=''; bindkey -e"

  _zpty_start "$session" || return 1
  _zpty_expect "$session" __ZPTY_READY__ "initial prompt" || {
    _zpty_stop "$session"
    return 1
  }

  if [[ $load_mode == startup ]]; then
    _zpty_write_line "$session" "$shell_setup; if source ${(q)FIXTURE_PATH} && source ${(q)PLUGIN_PATH}; then print -r -- '__STARTUP_''READY__'; else print -r -- '__STARTUP_''FAIL__'; fi" || {
      _zpty_stop "$session"
      return 1
    }
    _zpty_expect "$session" __STARTUP_READY__ "startup plugin load" || {
      _zpty_stop "$session"
      return 1
    }
    _zpty_expect "$session" __ZPTY_PROMPT__ "prompt after startup plugin load" || {
      _zpty_stop "$session"
      return 1
    }
  else
    _zpty_write_line "$session" "$shell_setup; if source ${(q)FIXTURE_PATH}; then print -r -- '__FIXTURE_''READY__'; else print -r -- '__FIXTURE_''FAIL__'; fi" || {
      _zpty_stop "$session"
      return 1
    }
    _zpty_expect "$session" __FIXTURE_READY__ "fixture prompt" || {
      _zpty_stop "$session"
      return 1
    }
    _zpty_expect "$session" __ZPTY_PROMPT__ "prompt after fixture load" || {
      _zpty_stop "$session"
      return 1
    }

    _zpty_write_line "$session" "if source ${(q)PLUGIN_PATH}; then print -r -- '__PLUGIN_''READY__'; else print -r -- '__PLUGIN_''FAIL__'; fi" || {
      _zpty_stop "$session"
      return 1
    }
    _zpty_expect "$session" __PLUGIN_READY__ "late plugin source" || {
      _zpty_stop "$session"
      return 1
    }
    _zpty_expect "$session" __ZPTY_PROMPT__ "prompt after late plugin source" || {
      _zpty_stop "$session"
      return 1
    }
  fi

  _configure_zshguy_widget "$session" || {
    _zpty_stop "$session"
    return 1
  }
  _verify_normal_input "$session" || {
    _zpty_stop "$session"
    return 1
  }
  _verify_abbreviation "$session" || {
    _zpty_stop "$session"
    return 1
  }
  _verify_backward_delete "$session" || {
    _zpty_stop "$session"
    return 1
  }
  _verify_cancel_restores_buffer "$session" || {
    _zpty_stop "$session"
    return 1
  }
  _verify_generation "$session" || {
    _zpty_stop "$session"
    return 1
  }

  _zpty_stop "$session"
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

test_startup_load_preserves_widget_stack() {
  _verify_stack startup
}

test_late_source_preserves_widget_stack() {
  _verify_stack late-source
}

main() {
  run_test test_startup_load_preserves_widget_stack
  run_test test_late_source_preserves_widget_stack

  print -r -- ""
  print -r -- "$TESTS_PASSED passed, $TESTS_FAILED failed"

  (( TESTS_FAILED == 0 ))
}

main "$@"
