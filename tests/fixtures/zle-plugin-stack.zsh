# Minimal zsh-autosuggestions + zsh-abbr interaction fixture.

autoload -Uz add-zsh-hook

typeset -g ZSH_AUTOSUGGEST_ORIGINAL_WIDGET_PREFIX="autosuggest-orig-"
typeset -gA _ZSH_AUTOSUGGEST_BIND_COUNTS
typeset -gi ZSHGUY_TEST_AUTOSUGGEST_DEPTH=0

_zshguy_test_autosuggest_invoke() {
  emulate -L zsh
  setopt local_options no_unset

  local original_widget=$1
  local -i widget_status
  shift

  (( ++ZSHGUY_TEST_AUTOSUGGEST_DEPTH ))
  if (( ZSHGUY_TEST_AUTOSUGGEST_DEPTH > 1 )); then
    BUFFER="print -r -- '__NESTED_''AUTOSUGGEST__'"
    CURSOR=${#BUFFER}
    zle .accept-line
    (( --ZSHGUY_TEST_AUTOSUGGEST_DEPTH ))
    return 1
  fi

  zle "$original_widget" -- "$@"
  widget_status=$?
  (( --ZSHGUY_TEST_AUTOSUGGEST_DEPTH ))
  return $widget_status
}

_zshguy_test_autosuggest_bind_widget() {
  emulate -L zsh
  setopt local_options no_unset

  local widget=$1
  local prefix=$ZSH_AUTOSUGGEST_ORIGINAL_WIDGET_PREFIX
  local widget_kind=${widgets[$widget]-}
  local original_widget
  local bound_widget
  local -i bind_count

  case $widget_kind in
    user:_zsh_autosuggest_(bound|orig)_*)
      bind_count=${_ZSH_AUTOSUGGEST_BIND_COUNTS[$widget]:-0}
      ;;
    user:*)
      bind_count=$(( ${_ZSH_AUTOSUGGEST_BIND_COUNTS[$widget]:-0} + 1 ))
      _ZSH_AUTOSUGGEST_BIND_COUNTS[$widget]=$bind_count
      zle -N "${prefix}${bind_count}-${widget}" "${widget_kind#user:}"
      ;;
    builtin)
      bind_count=$(( ${_ZSH_AUTOSUGGEST_BIND_COUNTS[$widget]:-0} + 1 ))
      _ZSH_AUTOSUGGEST_BIND_COUNTS[$widget]=$bind_count
      functions["_zsh_autosuggest_orig_${widget}"]="zle .${(q)widget}"
      zle -N "${prefix}${bind_count}-${widget}" "_zsh_autosuggest_orig_${widget}"
      ;;
    *)
      return 1
      ;;
  esac

  original_widget="${prefix}${bind_count}-${widget}"
  bound_widget="_zsh_autosuggest_bound_${bind_count}_${widget}"
  functions[$bound_widget]="_zshguy_test_autosuggest_invoke ${(q)original_widget} \"\$@\""
  zle -N -- "$widget" "$bound_widget"
}

_zshguy_test_autosuggest_bind_widgets() {
  emulate -L zsh

  typeset -g ZSHGUY_TEST_AUTOSUGGEST_DEPTH=0
  _zshguy_test_autosuggest_bind_widget accept-line
  _zshguy_test_autosuggest_bind_widget backward-delete-char
}

_zshguy_test_abbr_accept_line() {
  emulate -L zsh

  if [[ $BUFFER == "zzq" ]]; then
    BUFFER="print -r -- '__ABBR_''OK__'"
    CURSOR=${#BUFFER}
  fi

  zle .accept-line
}

zle -N accept-line _zshguy_test_abbr_accept_line
add-zsh-hook precmd _zshguy_test_autosuggest_bind_widgets
