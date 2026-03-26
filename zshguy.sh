# zshguy.sh - source this file in your .zshrc
# Usage: source /path/to/zshguy.sh

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

  lms_args="$(_zshguy_build_lms_args "$system_prompt" "$user_prompt")" || return 1
  lms_argv=("${(@Q)${(z)lms_args}}")

  if ! lms_output="$(lms "${lms_argv[@]}" 2>/dev/null)"; then
    return 1
  fi

  lms_output="$(_zshguy_normalize_model_output "$lms_output")" || return 1
  _zshguy_validate_model_output "$lms_output" || return 1
  print -r -- "$lms_output"
}

_zshguy_normalize_model_output() {
  emulate -L zsh
  setopt local_options no_unset

  local raw_output=${1-}
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
    cleaned_lines=("${cleaned_lines[-1]}")
  fi

  print -r -- "${(F)cleaned_lines}"
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

  return 0
}

_zshguy_build_command_generation_system_prompt() {
  emulate -L zsh
  setopt local_options no_unset

  print -r -- "You are a zsh command generator for an interactive terminal widget. The user describes what they want to do in natural language. Output ONLY a single zsh command that directly and minimally satisfies the request. Do not explain. Do not use markdown. Do not use code fences. Do not include multiple options. Do not add extra transformations, compression, deletion, extraction, or side effects unless the user explicitly asked for them. Prefer common, simple commands that a human would naturally write. If the user asks to list or filter files, prefer straightforward tools such as find, ls, or grep. Interpret ambiguous requests conservatively. If the user asks to list files with a given extension, return a file-listing command for that extension, not an archive or conversion command. Examples: 'list only .sh files' -> 'find . -type f -name '\''*.sh'\''' ; 'extract a tar.gz archive' -> 'tar -xvf archive.tar.gz'. No trailing newline. The command should work on macOS and Linux. Current directory: $(pwd)"
}

_zshguy_build_insert_system_prompt() {
  emulate -L zsh
  setopt local_options no_unset

  local prefix=${1-}
  local suffix=${2-}

  print -r -- "You are a zsh command generator for an interactive terminal widget. The user has partially written a command line. The text before the cursor is: $prefix
The text after the cursor is: $suffix
Output ONLY the text to insert at the cursor position. Do not explain. Do not use markdown. Do not use code fences. Do not repeat the full command line. Do not change text outside the insertion. Keep the insertion minimal and directly relevant to the user's request. No trailing newline. The inserted text combined with the existing text should form a valid zsh command. Current directory: $(pwd)"
}

_zshguy_notify_tty() {
  emulate -L zsh
  setopt local_options no_unset

  local message=${1-}

  [[ -o interactive ]] || return 0

  print -rn -- "$message" >/dev/tty 2>/dev/null || return 0
}

_zshguy_read_tty_prompt() {
  emulate -L zsh
  setopt local_options no_unset

  local prompt=${1-}
  local saved_tty
  local user_prompt

  saved_tty=$(stty -g </dev/tty) || return 1
  stty sane </dev/tty || return 1

  print -rn -- "$prompt" >/dev/tty || {
    stty "$saved_tty" </dev/tty
    return 1
  }

  if ! IFS= read -r user_prompt </dev/tty; then
    stty "$saved_tty" </dev/tty
    return 1
  fi

  stty "$saved_tty" </dev/tty || return 1

  print -r -- "$user_prompt"
}

_zshguy_widget() {
  emulate -L zsh
  setopt local_options no_unset

  local tty_prompt='[zshguy] '
  local user_prompt
  local system_prompt
  local lms_output
  local prefix
  local suffix

  if ! user_prompt="$(_zshguy_read_tty_prompt "$tty_prompt")"; then
    _zshguy_notify_tty $'\r\e[K'
    _zshguy_handle_generation_error
    return 0
  fi

  if [[ -z $user_prompt ]]; then
    return 0
  fi

  if [[ -n ${BUFFER-} ]]; then
    prefix=${BUFFER:0:$CURSOR}
    suffix=${BUFFER:$CURSOR}
    system_prompt="$(_zshguy_build_insert_system_prompt "$prefix" "$suffix")" || return 0
  else
    system_prompt="$(_zshguy_build_command_generation_system_prompt)" || return 0
  fi

  _zshguy_notify_tty "[zshguy] ${user_prompt} generating..."

  if ! lms_output="$(_zshguy_run_lms "$system_prompt" "$user_prompt")"; then
    _zshguy_notify_tty $'\r\e[K'
    _zshguy_handle_generation_error
    return 0
  fi

  _zshguy_notify_tty $'\r\e[K'

  if [[ -n $lms_output ]]; then
    _zshguy_apply_insert "$lms_output"
  fi

  return 0
}

if [[ -o interactive ]]; then
  zle -N zshguy-widget _zshguy_widget
fi
