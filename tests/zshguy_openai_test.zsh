#!/usr/bin/env zsh

emulate -LR zsh
setopt no_unset pipefail

source "${0:A:h:h}/zshguy.plugin.zsh" || exit 1
typeset -gi TESTS_PASSED=0 TESTS_FAILED=0

for dependency in curl jq; do
  if ! command -v "$dependency" >/dev/null 2>&1; then
    print -ru2 -- "$dependency is required to run OpenAI-compatible backend tests"
    exit 1
  fi
done

assert_eq() {
  [[ $1 == "$2" ]] && return 0
  print -ru2 -- "FAIL: $3 (expected: $1; actual: $2)"
  return 1
}

# All tests run in separate subshells, including their mocks and configuration.
setup() {
  typeset -g ZSHGUY_BACKEND=openai
  typeset -g ZSHGUY_BASE_URL=http://localhost:1234/v1
  typeset -g ZSHGUY_MODEL=test-model
  typeset -g ZSHGUY_API_KEY=''
  typeset -g ZSHGUY_DEBUG=0
  typeset -g mock_response='{"choices":[{"finish_reason":"stop","message":{"content":"pwd"}}]}'
  curl() {
    # Consume the request just as curl does, without making any network calls.
    local request=$(cat)
    print -r -- "$mock_response"
  }
}

expect_failure() {
  local expected=$1 output
  if output="$(_zshguy_run_model sys user)"; then
    print -ru2 -- "FAIL: request unexpectedly succeeded: $output"
    return 1
  fi
  assert_eq "$expected" "$output" "generation error"
}

test_request_preserves_json_and_headers() {
  local expected_system_prompt=$'system "quotes" \\ slash\n日本語\t*'
  local expected_user_prompt=$'user \'quotes\' $(echo injected) `pwd`\nnext'
  ZSHGUY_MODEL=$'model/"name"'
  ZSHGUY_BASE_URL=https://example.invalid/prefix/v1/
  ZSHGUY_API_KEY=test-token
  curl() {
    local -a args=("$@")
    local i request=$(cat)
    assert_eq --disable "$1" 'ignore curl config' || return 1
    assert_eq https://example.invalid/prefix/v1/chat/completions "${args[-1]}" 'endpoint' || return 1
    [[ ${args[(Ie)--fail]} -gt 0 ]] || return 1
    [[ ${args[(Ie)--globoff]} -gt 0 ]] || return 1
    [[ ${args[(Ie)--location]} -eq 0 ]] || return 1
    i=${args[(Ie)--connect-timeout]}
    assert_eq 10 "${args[i+1]}" 'connect timeout' || return 1
    i=${args[(Ie)--max-time]}
    assert_eq 120 "${args[i+1]}" 'request timeout' || return 1
    local content_header='Content-Type: application/json'
    local header_arg='@/dev/fd/3'
    local received_header arg
    [[ ${args[(Ie)$content_header]} -gt 0 ]] || return 1
    [[ ${args[(Ie)$header_arg]} -gt 0 ]] || return 1
    IFS= read -r received_header < /dev/fd/3 || return 1
    assert_eq 'Authorization: Bearer test-token' "$received_header" 'header via descriptor' || return 1
    for arg in "${args[@]}"; do
      [[ $arg != *test-token* ]] || return 1
    done
    i=${args[(Ie)--data-binary]}
    assert_eq '@-' "${args[i+1]}" 'JSON via stdin' || return 1
    jq -e --arg system "$expected_system_prompt" --arg user "$expected_user_prompt" --arg model "$ZSHGUY_MODEL" '
      .model == $model and .stream == false and
      .messages == [{role:"system",content:$system},{role:"user",content:$user}]
    ' <<< "$request" >/dev/null || return 1
    print -r -- "$mock_response"
  }
  local output
  output="$(_zshguy_run_model "$expected_system_prompt" "$expected_user_prompt")" || {
    print -ru2 -- "FAIL: request failed: $output"
    return 1
  }
  assert_eq pwd "$output" 'parsed command'
}

test_no_authentication_without_key() {
  unset ZSHGUY_API_KEY
  local OPENAI_API_KEY=unrelated-key
  curl() {
    local arg request=$(cat)
    for arg in "$@"; do
      if [[ $arg == Authorization:* ]]; then
        print -ru2 -- 'unexpected Authorization header'
        return 1
      fi
    done
    assert_eq http://localhost:1234/v1/chat/completions "${@[-1]}" 'endpoint without trailing slash' || return 1
    print -r -- "$mock_response"
  }
  local output
  output="$(_zshguy_run_model sys user)" || return 1
  assert_eq pwd "$output" 'unauthenticated response'
}

test_configuration_errors() {
  ZSHGUY_MODEL=''
  expect_failure 'ZSHGUY_BASE_URL and ZSHGUY_MODEL are required when ZSHGUY_BACKEND=openai' || return 1
  ZSHGUY_MODEL=test-model
  unset ZSHGUY_BASE_URL
  expect_failure 'ZSHGUY_BASE_URL and ZSHGUY_MODEL are required when ZSHGUY_BACKEND=openai' || return 1
  ZSHGUY_BASE_URL=file:///tmp/api
  expect_failure 'ZSHGUY_BASE_URL must start with http:// or https://' || return 1
  ZSHGUY_BASE_URL=http://localhost:1234/v1
  ZSHGUY_API_KEY=$'key\r\nX-Injected: true'
  expect_failure 'ZSHGUY_API_KEY must not contain newlines'
}

test_missing_dependencies() {
  # Exercise dependency checks directly so mktemp is not needed on this PATH.
  local path=() output
  if output="$(_zshguy_request_openai sys user 2>&1)"; then
    return 1
  fi
  assert_eq 'jq is required when ZSHGUY_BACKEND=openai' "$output" 'missing jq' || return 1
  unfunction curl
  if output="$(_zshguy_request_openai sys user 2>&1)"; then
    return 1
  fi
  assert_eq 'curl is required when ZSHGUY_BACKEND=openai' "$output" 'missing curl'
}

test_transport_errors() {
  local error_code
  for error_code in 7 22 28; do
    curl() {
      local request=$(cat)
      print -ru2 -- "curl: ($error_code) request failed"
      print -ru2 -- 'additional diagnostic line'
      # A body must never be mistaken for a generated command on HTTP failure.
      print -r -- "$mock_response"
      return "$error_code"
    }
    expect_failure "curl: ($error_code) request failed" || return 1
  done
}

test_rejects_invalid_responses() {
  local invalid
  local -a invalid_responses=(
    '' '<html>Bad gateway</html>' '{}' 'null' '[]'
    '{"error":{"message":"invalid API key"}}'
    '{"choices":[]}'
    '{"choices":[{"finish_reason":"stop","message":{"content":null}}]}'
    '{"choices":[{"finish_reason":"stop","message":{"content":""}}]}'
    '{"choices":[{"finish_reason":"stop","message":{"content":42}}]}'
    '{"choices":[{"finish_reason":"stop","message":{"content":[{"text":"pwd"}]}}]}'
    '{"choices":[{"finish_reason":"length","message":{"content":"rm"}}]}'
    '{"choices":[{"finish_reason":"content_filter","message":{"content":"pwd"}}]}'
    '{"error":{"message":"failed"},"choices":[{"message":{"content":"pwd"}}]}'
  )
  invalid_responses+=("$mock_response"$'\n'"$mock_response")
  for invalid in "${invalid_responses[@]}"; do
    mock_response=$invalid
    expect_failure 'API response must contain a complete, non-empty choices[0].message.content string' || return 1
  done
}

test_normalizes_and_validates_content() {
  mock_response='{"choices":[{"finish_reason":"stop","message":{"content":"<think>reasoning</think>\n```zsh\npwd\n```"}}]}'
  local output
  output="$(_zshguy_run_model sys user)" || return 1
  assert_eq pwd "$output" 'normalize model content' || return 1
  mock_response='{"choices":[{"finish_reason":"stop","message":{"content":"pwd\nThis is an explanation."}}]}'
  expect_failure 'model output was rejected by validation' || return 1
  mock_response='{"choices":[{"finish_reason":"stop","message":{"content":"   "}}]}'
  expect_failure 'model output was rejected by validation'
}

test_widget_preserves_buffer_on_failure() {
  local BUFFER='git checkout main'
  local -i CURSOR=13
  mock_response='{"error":{"message":"unauthorized"}}'
  _zshguy_begin_prompt_mode || return 1
  BUFFER='[zshguy] switch branches'
  if _zshguy_accept_line; then
    print -ru2 -- 'FAIL: widget accepted a failed request'
    return 1
  fi
  assert_eq 'git checkout main' "$BUFFER" 'original buffer' || return 1
  assert_eq 13 "$CURSOR" 'original cursor' || return 1
  assert_eq '' "$_zshguy_state" 'cleared prompt state'
}

test_widget_inserts_content() {
  local BUFFER='git checkout '
  local -i CURSOR=13
  mock_response='{"choices":[{"finish_reason":"stop","message":{"content":"main"}}]}'
  _zshguy_begin_prompt_mode || return 1
  BUFFER='[zshguy] main branch'
  _zshguy_accept_line || return 1
  assert_eq 'git checkout main' "$BUFFER" 'insertion buffer' || return 1
  assert_eq 17 "$CURSOR" 'insertion cursor'
}

test_widget_rejects_incomplete_completion_states() {
  local reason
  local BUFFER
  local -i CURSOR
  for reason in missing null tool_calls function_call error length content_filter; do
    mock_response="$(jq -cn --arg reason "$reason" '
      {choices:[{finish_reason:$reason,message:{content:"main"}}]}
      | if $reason == "missing" then del(.choices[0].finish_reason)
        elif $reason == "null" then .choices[0].finish_reason = null else . end
    ')" || return 1
    BUFFER='git checkout existing'
    CURSOR=13
    _zshguy_begin_prompt_mode || return 1
    BUFFER='[zshguy] main branch'
    if _zshguy_accept_line; then
      print -ru2 -- "FAIL: widget accepted finish_reason=$reason"
      return 1
    fi
    assert_eq 'git checkout existing' "$BUFFER" 'preserved buffer' || return 1
    assert_eq 13 "$CURSOR" 'preserved cursor' || return 1
    assert_eq '' "$_zshguy_state" 'cleared state' || return 1
  done
}

for test_name in \
  test_request_preserves_json_and_headers \
  test_no_authentication_without_key \
  test_configuration_errors \
  test_missing_dependencies \
  test_transport_errors \
  test_rejects_invalid_responses \
  test_normalizes_and_validates_content \
  test_widget_preserves_buffer_on_failure \
  test_widget_rejects_incomplete_completion_states \
  test_widget_inserts_content; do
  if (setup; "$test_name"); then
    (( ++TESTS_PASSED ))
    print -r -- "ok - $test_name"
  else
    (( ++TESTS_FAILED ))
    print -r -- "not ok - $test_name"
  fi
done

print -r -- ""
print -r -- "$TESTS_PASSED passed, $TESTS_FAILED failed"
(( TESTS_FAILED == 0 ))
