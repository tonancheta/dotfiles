#!/usr/bin/env bash
set -euo pipefail

if [ -z "${DEEPSEEK_API_KEY:-}" ]; then
  echo "Error: DEEPSEEK_API_KEY is not set. Run: export DEEPSEEK_API_KEY=sk-..." >&2
  exit 1
fi

if [ "$#" -lt 2 ]; then
  echo "Usage: deepseek.sh <deepseek-chat|deepseek-reasoner> <prompt text>" >&2
  exit 1
fi

MODEL="$1"
shift
PROMPT="$*"

curl -sS https://api.deepseek.com/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${DEEPSEEK_API_KEY}" \
  -d "$(jq -n --arg model "$MODEL" --arg prompt "$PROMPT" \
        '{model: $model, messages: [{role: "user", content: $prompt}], stream: false}')" \
  | jq -r '
      if .error then
        "DeepSeek API error: " + (.error.message // (.error | tostring))
      else
        .choices[0].message.content
      end
    '
