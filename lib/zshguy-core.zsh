# zshguy-core.zsh - shared helper and widget implementation

_zshguy_build_lms_args() {
  emulate -L zsh
  setopt local_options no_unset

  local system_prompt=$1
  local user_prompt=$2
  local -a lms_args

  if [[ -n ${ZSHGUY_MODEL-} ]]; then
    lms_args=(chat "$ZSHGUY_MODEL" -s "$system_prompt" -p "$user_prompt")
  else
    lms_args=(chat -s "$system_prompt" -p "$user_prompt")
  fi

  print -r -- "${(@q)lms_args}"
}

_zshguy_mode_for_buffer() {
  emulate -L zsh
  setopt local_options no_unset

  if [[ -n ${BUFFER-} ]]; then
    print -r -- insert
  else
    print -r -- empty
  fi
}

_zshguy_run_lms() {
  emulate -L zsh
  setopt local_options no_unset

  local system_prompt=$1
  local user_prompt=$2
  local lms_args
  local -a lms_argv
  local lms_output
  local lms_stderr_file
  local lms_stderr
  local normalized_output

  lms_args="$(_zshguy_build_lms_args "$system_prompt" "$user_prompt")" || return 1
  lms_argv=("${(@Q)${(z)lms_args}}")

  lms_stderr_file="$(mktemp "${TMPDIR:-/tmp}/zshguy-lms-stderr.XXXXXX")" || return 1

  if ! lms_output="$(lms "${lms_argv[@]}" 2>"$lms_stderr_file")"; then
    lms_stderr="$(<"$lms_stderr_file")"
    command rm -f "$lms_stderr_file"
    lms_stderr="${lms_stderr%%$'\n'*}"
    lms_stderr="${lms_stderr%$'\r'}"
    print -r -- "$lms_stderr"
    return 1
  fi

  command rm -f "$lms_stderr_file"

  normalized_output="$(_zshguy_normalize_model_output "$lms_output")" || return 1
  if ! _zshguy_validate_model_output "$normalized_output"; then
    _zshguy_debug_validation_failure "$lms_output" "$normalized_output"
    print -r -- "model output was rejected by validation"
    return 1
  fi
  print -r -- "$normalized_output"
}

_zshguy_debug_validation_failure() {
  emulate -L zsh
  setopt local_options no_unset

  [[ ${ZSHGUY_DEBUG-} == 1 ]] || return 0

  local raw_output=${1-}
  local normalized_output=${2-}

  print -ru2 -- "[zshguy debug] raw output: ${raw_output}"
  print -ru2 -- "[zshguy debug] normalized output: ${normalized_output}"
}

_zshguy_normalize_model_output() {
  emulate -L zsh
  setopt local_options no_unset

  local raw_output=${1-}
  local extracted_command
  local line
  local -i in_think=0
  local -a lines
  local -a cleaned_lines

  lines=("${(@f)raw_output}")

  for line in "${lines[@]}"; do
    line="${line//$'\r'/}"

    if (( in_think )); then
      if [[ "$line" == *'</think>'* ]]; then
        in_think=0
      fi
      continue
    fi

    if [[ "$line" == *'<think>'* ]]; then
      if [[ "$line" != *'</think>'* ]]; then
        in_think=1
      fi
      continue
    fi

    line="${line//<|im_end|>/}"
    line="$(_zshguy_trim_whitespace "$line")" || return 1

    if [[ "$line" == '</think>' ]]; then
      continue
    fi

    cleaned_lines+=("$line")
  done

  while (( ${#cleaned_lines[@]} )) && [[ -z "${cleaned_lines[1]}" ]]; do
    cleaned_lines=("${cleaned_lines[@]:1}")
  done

  while (( ${#cleaned_lines[@]} )) && [[ -z "${cleaned_lines[-1]}" ]]; do
    cleaned_lines=("${cleaned_lines[@]:0:-1}")
  done

  if (( ${#cleaned_lines[@]} >= 2 )) &&
    [[ "${cleaned_lines[1]}" == '```'* ]] &&
    [[ "${cleaned_lines[-1]}" == '```' ]]; then
    cleaned_lines=("${cleaned_lines[@]:1:${#cleaned_lines[@]}-2}")
  fi

  if (( ${#cleaned_lines[@]} > 1 )); then
    extracted_command="$(_zshguy_extract_last_command_candidate "${cleaned_lines[@]}")" || return 1
    if [[ -n "$extracted_command" ]]; then
      print -r -- "$extracted_command"
      return 0
    fi
  fi

  print -r -- "${(F)cleaned_lines}"
}

_zshguy_trim_whitespace() {
  emulate -L zsh
  setopt local_options no_unset

  local value=${1-}

  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  print -r -- "$value"
}

_zshguy_is_command_candidate() {
  emulate -L zsh
  setopt local_options no_unset

  local line

  line="$(_zshguy_trim_whitespace "${1-}")" || return 1

  [[ -n "$line" ]] || return 1
  [[ "$line" != *'```'* ]] || return 1
  [[ "$line" != *'<think>'* ]] || return 1
  [[ "$line" != *'</think>'* ]] || return 1
  [[ "$line" != *'<|im_end|>'* ]] || return 1
  [[ ! "$line" =~ '^(The|This|That|These|Those|Here|There|I|You|We|It|They|A|An)[[:space:]]' ]] || return 1
  [[ ! "$line" =~ '[.!?]$' ]] || return 1
  [[ "$line" =~ '^([A-Z_][A-Z0-9_]*=[^[:space:]]+[[:space:]]+)*([a-z0-9_./-]+)([[:space:]].*)?$' ]] || return 1

  return 0
}

_zshguy_extract_last_command_candidate() {
  emulate -L zsh
  setopt local_options no_unset

  local line
  local -a candidate_lines

  candidate_lines=("$@")

  line="$(_zshguy_trim_whitespace "${candidate_lines[-1]-}")" || return 1
  if _zshguy_is_command_candidate "$line"; then
    print -r -- "$line"
    return 0
  fi

  return 0
}

_zshguy_validate_model_output() {
  emulate -L zsh
  setopt local_options no_unset

  local output=${1-}

  [[ -n "$output" ]] || return 1
  [[ "$output" != *$'\n'* ]] || return 1
  [[ "$output" != *'```'* ]] || return 1
  [[ "$output" != *'<think>'* ]] || return 1
  [[ "$output" != *'</think>'* ]] || return 1
  [[ "$output" != *'<|im_end|>'* ]] || return 1

  return 0
}

_zshguy_apply_insert() {
  emulate -L zsh
  setopt local_options no_unset

  local insertion=$1

  BUFFER="${BUFFER:0:$CURSOR}${insertion}${BUFFER:$CURSOR}"
  CURSOR=$(( CURSOR + ${#insertion} ))
}

_zshguy_handle_generation_error() {
  emulate -L zsh
  setopt local_options no_unset

  local error_message=${1-}
  local message

  [[ -o zle ]] || return 0

  message="$(_zshguy_generation_error_message "$error_message")" || return 1
  zle -M "$message"

  return 0
}

_zshguy_generation_error_message() {
  emulate -L zsh
  setopt local_options no_unset

  local error_message=${1-}

  if [[ -n "$error_message" ]]; then
    print -r -- "[zshguy] lms failed: $error_message. Continue typing to dismiss."
  else
    print -r -- "[zshguy] lms failed: unknown error. Continue typing to dismiss."
  fi
}

_zshguy_build_command_generation_system_prompt() {
  emulate -L zsh
  setopt local_options no_unset

  print -r -- "You are a zsh command generator for an interactive terminal widget. The user describes what they want to do in natural language. Output ONLY a single zsh command that directly and minimally satisfies the request. Do not explain. Do not use markdown. Do not use code fences. Do not include multiple options. Do not add extra transformations, compression, deletion, extraction, or side effects unless the user explicitly asked for them. Prefer common, simple commands that a human would naturally write. If the user asks to list or filter files, prefer straightforward tools such as find, ls, or grep. Interpret ambiguous requests conservatively. If the user asks to list files with a given extension, return a file-listing command for that extension, not an archive or conversion command. Examples: 'list only .sh files' -> 'find . -type f -name '\''*.sh'\''' ; 'extract a tar.gz archive' -> 'tar -xvf archive.tar.gz'. No trailing newline. The command should work on macOS and Linux. Current directory: $PWD"
}

_zshguy_build_insert_system_prompt() {
  emulate -L zsh
  setopt local_options no_unset

  local prefix=${1-}
  local suffix=${2-}

  print -r -- "You are a zsh command generator for an interactive terminal widget. The user has partially written a command line. The text before the cursor is: $prefix
The text after the cursor is: $suffix
Output ONLY the text to insert at the cursor position. Do not explain. Do not use markdown. Do not use code fences. Do not repeat the full command line. Do not change text outside the insertion. Keep the insertion minimal and directly relevant to the user's request. No trailing newline. The inserted text combined with the existing text should form a valid zsh command. Current directory: $PWD"
}

_zshguy_prompt_prefix() {
  emulate -L zsh
  setopt local_options no_unset

  print -r -- "[zshguy] "
}

_zshguy_prompt_prefix_length() {
  emulate -L zsh
  setopt local_options no_unset

  local prompt_prefix

  prompt_prefix="$(_zshguy_prompt_prefix)" || return 1
  print -r -- "${#prompt_prefix}"
}

_zshguy_clear_state() {
  emulate -L zsh
  setopt local_options no_unset

  typeset -g _zshguy_state=""
  typeset -g _zshguy_saved_buffer=""
  typeset -gi _zshguy_saved_cursor=0
  typeset -g _zshguy_saved_mode=""
}

_zshguy_begin_prompt_mode() {
  emulate -L zsh
  setopt local_options no_unset

  local prompt_prefix

  prompt_prefix="$(_zshguy_prompt_prefix)" || return 1

  typeset -g _zshguy_state="collecting_prompt"
  typeset -g _zshguy_saved_buffer="${BUFFER-}"
  typeset -gi _zshguy_saved_cursor=${CURSOR-0}
  _zshguy_saved_mode="$(_zshguy_mode_for_buffer)" || return 1

  BUFFER="$prompt_prefix"
  CURSOR=${#BUFFER}
}

_zshguy_restore_saved_buffer() {
  emulate -L zsh
  setopt local_options no_unset

  BUFFER=${_zshguy_saved_buffer-}
  CURSOR=${_zshguy_saved_cursor-0}
}

_zshguy_extract_prompt_query() {
  emulate -L zsh
  setopt local_options no_unset

  local prompt_prefix

  prompt_prefix="$(_zshguy_prompt_prefix)" || return 1

  if [[ ${BUFFER-} == "$prompt_prefix"* ]]; then
    print -r -- "${BUFFER#"$prompt_prefix"}"
    return 0
  fi

  return 1
}

_zshguy_show_generating_buffer() {
  emulate -L zsh
  setopt local_options no_unset

  local user_prompt=${1-}
  local prompt_prefix

  prompt_prefix="$(_zshguy_prompt_prefix)" || return 1
  typeset -g _zshguy_state="generating"
  BUFFER="${prompt_prefix}${user_prompt} generating..."
  CURSOR=${#BUFFER}
}

_zshguy_cancel() {
  emulate -L zsh
  setopt local_options no_unset

  [[ -n ${_zshguy_state-} ]] || return 0

  _zshguy_restore_saved_buffer
  _zshguy_clear_state
  _zshguy_redraw_prompt
}

_zshguy_redraw_prompt() {
  emulate -L zsh
  setopt local_options no_unset

  [[ -o zle ]] || return 0

  zle "$(_zshguy_redraw_widget)"
}

_zshguy_redraw_widget() {
  emulate -L zsh
  setopt local_options no_unset

  print -r -- "-R"
}

_zshguy_restore_prompt_prefix_boundary() {
  emulate -L zsh
  setopt local_options no_unset

  local prompt_prefix
  local -i prefix_length

  prompt_prefix="$(_zshguy_prompt_prefix)" || return 1
  prefix_length="$(_zshguy_prompt_prefix_length)" || return 1

  if [[ ${BUFFER-} != "$prompt_prefix"* ]]; then
    BUFFER="${prompt_prefix}${BUFFER#"$prompt_prefix"}"
  fi

  if (( ${#BUFFER} < prefix_length )); then
    BUFFER="$prompt_prefix"
  fi

  if (( CURSOR < prefix_length )); then
    CURSOR=$prefix_length
  fi
}

_zshguy_original_widget_name() {
  emulate -L zsh
  setopt local_options no_unset

  case "${1-}" in
    accept-line)
      print -r -- "${_zshguy_orig_accept_line_widget:-.accept-line}"
      ;;
    send-break)
      print -r -- "${_zshguy_orig_send_break_widget:-.send-break}"
      ;;
    backward-delete-char)
      print -r -- "${_zshguy_orig_backward_delete_char_widget:-.backward-delete-char}"
      ;;
    vi-backward-delete-char)
      print -r -- "${_zshguy_orig_vi_backward_delete_char_widget:-.vi-backward-delete-char}"
      ;;
    backward-kill-word)
      print -r -- "${_zshguy_orig_backward_kill_word_widget:-.backward-kill-word}"
      ;;
    vi-backward-kill-word)
      print -r -- "${_zshguy_orig_vi_backward_kill_word_widget:-.vi-backward-kill-word}"
      ;;
    backward-kill-line)
      print -r -- "${_zshguy_orig_backward_kill_line_widget:-.backward-kill-line}"
      ;;
    kill-whole-line)
      print -r -- "${_zshguy_orig_kill_whole_line_widget:-.kill-whole-line}"
      ;;
    *)
      return 1
      ;;
  esac
}

_zshguy_capture_original_widget() {
  emulate -L zsh
  setopt local_options no_unset

  local widget_name=${1-}
  local backup_widget_name=${2-}
  local target_parameter_name=${3-}
  local widget_kind=${widgets[$widget_name]-}
  local resolved_widget_name

  if [[ $widget_kind == "builtin" ]]; then
    resolved_widget_name=".$widget_name"
  else
    zle -A "$widget_name" "$backup_widget_name" || return 1
    resolved_widget_name="$backup_widget_name"
  fi

  if [[ -n $target_parameter_name ]]; then
    typeset -g "$target_parameter_name=$resolved_widget_name"
    return 0
  fi

  print -r -- "$resolved_widget_name"
}

_zshguy_call_original_widget() {
  emulate -L zsh
  setopt local_options no_unset

  local widget_name=${1-}
  local original_widget

  original_widget="$(_zshguy_original_widget_name "$widget_name")" || return 1
  zle "$original_widget"
}

_zshguy_run_delete_widget() {
  emulate -L zsh
  setopt local_options no_unset

  [[ -o zle ]] && zle -M ""

  local widget_name=${1-}
  local -i prefix_length

  if [[ ${_zshguy_state-} != "collecting_prompt" ]]; then
    _zshguy_call_original_widget "$widget_name" || return 1
    return 0
  fi

  prefix_length="$(_zshguy_prompt_prefix_length)" || return 1

  if (( CURSOR <= prefix_length )); then
    BUFFER="$(_zshguy_prompt_prefix)" || return 1
    CURSOR=$prefix_length
    return 0
  fi

  _zshguy_call_original_widget "$widget_name" || return 1
  _zshguy_restore_prompt_prefix_boundary || return 1
}

_zshguy_backward_delete_char() {
  emulate -L zsh
  setopt local_options no_unset

  _zshguy_run_delete_widget backward-delete-char
}

_zshguy_vi_backward_delete_char() {
  emulate -L zsh
  setopt local_options no_unset

  _zshguy_run_delete_widget vi-backward-delete-char
}

_zshguy_backward_kill_word() {
  emulate -L zsh
  setopt local_options no_unset

  _zshguy_run_delete_widget backward-kill-word
}

_zshguy_vi_backward_kill_word() {
  emulate -L zsh
  setopt local_options no_unset

  _zshguy_run_delete_widget vi-backward-kill-word
}

_zshguy_backward_kill_line() {
  emulate -L zsh
  setopt local_options no_unset

  _zshguy_run_delete_widget backward-kill-line
}

_zshguy_kill_whole_line() {
  emulate -L zsh
  setopt local_options no_unset

  _zshguy_run_delete_widget kill-whole-line
}

_zshguy_accept_line() {
  emulate -L zsh
  setopt local_options no_unset

  [[ -o zle ]] && zle -M ""

  local user_prompt
  local system_prompt
  local lms_output

  if [[ ${_zshguy_state-} != "collecting_prompt" ]]; then
    _zshguy_call_original_widget accept-line || return 1
    return 0
  fi

  user_prompt="$(_zshguy_extract_prompt_query)" || {
    _zshguy_cancel
    return 0
  }

  if [[ -z $user_prompt ]]; then
    _zshguy_cancel
    return 0
  fi

  if [[ ${_zshguy_saved_mode-} == "insert" ]]; then
    system_prompt="$(_zshguy_build_insert_system_prompt \
      "${_zshguy_saved_buffer:0:${_zshguy_saved_cursor-0}}" \
      "${_zshguy_saved_buffer:${_zshguy_saved_cursor-0}}")" || return 0
  else
    system_prompt="$(_zshguy_build_command_generation_system_prompt)" || return 0
  fi

  _zshguy_show_generating_buffer "$user_prompt" || return 0
  _zshguy_redraw_prompt

  if ! lms_output="$(_zshguy_run_lms "$system_prompt" "$user_prompt")"; then
    _zshguy_restore_saved_buffer
    _zshguy_clear_state
    _zshguy_redraw_prompt
    _zshguy_handle_generation_error "$lms_output"
    return 1
  fi

  _zshguy_restore_saved_buffer
  if [[ ${_zshguy_saved_mode-} == "insert" ]]; then
    _zshguy_apply_insert "$lms_output"
  else
    BUFFER=$lms_output
    CURSOR=${#BUFFER}
  fi
  _zshguy_clear_state
  _zshguy_redraw_prompt

  return 0
}

_zshguy_send_break() {
  emulate -L zsh
  setopt local_options no_unset

  [[ -o zle ]] && zle -M ""

  if [[ -n ${_zshguy_state-} ]]; then
    _zshguy_cancel
    return 0
  fi

  _zshguy_call_original_widget send-break
}

_zshguy_widget() {
  emulate -L zsh
  setopt local_options no_unset

  [[ -o zle ]] && zle -M ""

  [[ -z ${_zshguy_state-} ]] || return 0

  _zshguy_begin_prompt_mode || return 0
  _zshguy_redraw_prompt

  return 0
}
