#!/usr/bin/env zsh

emulate -LR zsh
setopt errexit

typeset -r TEST_DIR="${0:A:h}"

zsh "$TEST_DIR/zshguy_test.zsh"
zsh "$TEST_DIR/zshguy_integration_test.zsh"
