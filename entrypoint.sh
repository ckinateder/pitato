#!/bin/sh
# Renders Pi's custom-provider config from env, then starts Pi.
# A real API key is NOT written to disk: models.json references $PI_API_KEY
# and Pi interpolates it from the environment.
set -eu

for var in PI_BASE_URL PI_MODEL; do
    eval "value=\${$var:-}"
    [ -n "$value" ] || { echo "error: $var is required" >&2; exit 1; }
done

# PI_API_KEY may be blank (e.g. local models). Pi still wants a key, so use a placeholder.
if [ -n "${PI_API_KEY:-}" ]; then
    api_key='$PI_API_KEY'
else
    api_key='none'
fi

# Values are embedded in JSON below; refuse characters that would break it.
for value in "$PI_BASE_URL" "$PI_MODEL"; do
    case "$value" in
        *\"* | *\\*) echo "error: PI_BASE_URL/PI_MODEL must not contain \" or \\" >&2; exit 1 ;;
    esac
done

# Without "reasoning": true Pi treats the model as non-thinking and disables /thinking.
# Set PI_REASONING=0 for models that reject reasoning_effort.
if [ "${PI_REASONING:-1}" = "0" ]; then reasoning=false; else reasoning=true; fi

mkdir -p "$PI_CODING_AGENT_DIR"
cat > "$PI_CODING_AGENT_DIR/models.json" <<EOF
{
  "providers": {
    "custom": {
      "baseUrl": "$PI_BASE_URL",
      "api": "openai-completions",
      "apiKey": "$api_key",
      "models": [{ "id": "$PI_MODEL", "reasoning": $reasoning }]
    }
  }
}
EOF

# Plan mode ships as an example extension; load the image's read-only copy.
# /review is a prompt template baked into the image for the same reason.
# rtk.ts rewrites bash calls through rtk to cut output tokens; rtk.md tells the model how to recall what it elides.
exec pi --extension /opt/pi/examples/extensions/plan-mode/index.ts \
    --extension /opt/rtk/rtk.ts \
    --append-system-prompt /opt/prompts/rtk.md \
    --prompt-template /opt/prompts/review.md \
    --provider custom --model "$PI_MODEL" "$@"
