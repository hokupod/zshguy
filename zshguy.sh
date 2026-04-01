# zshguy.sh - compatibility wrapper for the canonical plugin entrypoint
# Usage: source /path/to/zshguy.sh

source "${${(%):-%N}:A:h}/zshguy.plugin.zsh"
