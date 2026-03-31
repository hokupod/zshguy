# zshguy.plugin.zsh - canonical plugin entrypoint

emulate -L zsh
setopt local_options no_unset

if (( ${+parameters[_zshguy_plugin_loaded]} )); then
  return 0
fi

source "${${(%):-%N}:A:h}/lib/zshguy-core.zsh" || return 1

if [[ -o interactive ]]; then
  _zshguy_clear_state
  typeset -g _zshguy_orig_accept_line_widget="zshguy-orig-accept-line"
  typeset -g _zshguy_orig_send_break_widget="zshguy-orig-send-break"
  typeset -g _zshguy_orig_backward_delete_char_widget="zshguy-orig-backward-delete-char"
  typeset -g _zshguy_orig_vi_backward_delete_char_widget="zshguy-orig-vi-backward-delete-char"
  typeset -g _zshguy_orig_backward_kill_word_widget="zshguy-orig-backward-kill-word"
  typeset -g _zshguy_orig_vi_backward_kill_word_widget="zshguy-orig-vi-backward-kill-word"
  typeset -g _zshguy_orig_backward_kill_line_widget="zshguy-orig-backward-kill-line"
  typeset -g _zshguy_orig_kill_whole_line_widget="zshguy-orig-kill-whole-line"

  zle -A accept-line "$_zshguy_orig_accept_line_widget"
  zle -A send-break "$_zshguy_orig_send_break_widget"
  zle -A backward-delete-char "$_zshguy_orig_backward_delete_char_widget"
  zle -A vi-backward-delete-char "$_zshguy_orig_vi_backward_delete_char_widget"
  zle -A backward-kill-word "$_zshguy_orig_backward_kill_word_widget"
  zle -A vi-backward-kill-word "$_zshguy_orig_vi_backward_kill_word_widget"
  zle -A backward-kill-line "$_zshguy_orig_backward_kill_line_widget"
  zle -A kill-whole-line "$_zshguy_orig_kill_whole_line_widget"

  zle -N zshguy-widget _zshguy_widget
  zle -N zshguy-accept-line _zshguy_accept_line
  zle -N zshguy-send-break _zshguy_send_break
  zle -N zshguy-backward-delete-char _zshguy_backward_delete_char
  zle -N zshguy-vi-backward-delete-char _zshguy_vi_backward_delete_char
  zle -N zshguy-backward-kill-word _zshguy_backward_kill_word
  zle -N zshguy-vi-backward-kill-word _zshguy_vi_backward_kill_word
  zle -N zshguy-backward-kill-line _zshguy_backward_kill_line
  zle -N zshguy-kill-whole-line _zshguy_kill_whole_line
  zle -A zshguy-accept-line accept-line
  zle -A zshguy-send-break send-break
  zle -A zshguy-backward-delete-char backward-delete-char
  zle -A zshguy-vi-backward-delete-char vi-backward-delete-char
  zle -A zshguy-backward-kill-word backward-kill-word
  zle -A zshguy-vi-backward-kill-word vi-backward-kill-word
  zle -A zshguy-backward-kill-line backward-kill-line
  zle -A zshguy-kill-whole-line kill-whole-line
fi

typeset -g _zshguy_plugin_loaded=1
