# zshguy.plugin.zsh - canonical plugin entrypoint

emulate -L zsh
setopt local_options no_unset

if (( ${+parameters[_zshguy_plugin_loaded]} )); then
  return 0
fi

source "${${(%):-%N}:A:h}/lib/zshguy-core.zsh" || return 1

if [[ -o interactive ]]; then
  _zshguy_clear_state
  _zshguy_capture_original_widget accept-line zshguy-orig-accept-line _zshguy_orig_accept_line_widget || return 1
  _zshguy_capture_original_widget send-break zshguy-orig-send-break _zshguy_orig_send_break_widget || return 1
  _zshguy_capture_original_widget backward-delete-char zshguy-orig-backward-delete-char _zshguy_orig_backward_delete_char_widget || return 1
  _zshguy_capture_original_widget vi-backward-delete-char zshguy-orig-vi-backward-delete-char _zshguy_orig_vi_backward_delete_char_widget || return 1
  _zshguy_capture_original_widget backward-kill-word zshguy-orig-backward-kill-word _zshguy_orig_backward_kill_word_widget || return 1
  _zshguy_capture_original_widget vi-backward-kill-word zshguy-orig-vi-backward-kill-word _zshguy_orig_vi_backward_kill_word_widget || return 1
  _zshguy_capture_original_widget backward-kill-line zshguy-orig-backward-kill-line _zshguy_orig_backward_kill_line_widget || return 1
  _zshguy_capture_original_widget kill-whole-line zshguy-orig-kill-whole-line _zshguy_orig_kill_whole_line_widget || return 1

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
