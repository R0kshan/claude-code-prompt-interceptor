#!/bin/bash
set -e

# 1. Configuration Variables (Override these via 'podman run -e ...')

## Configuration for Claude settings
export MODEL_ONE=${MODEL_ONE:-"gpt-4o-mini"}
export MODEL_TWO=${MODEL_TWO:-"gpt-4o-mini"}
export MODEL_THREE=${MODEL_THREE:-"gpt-4o-mini"}
export CLAUDE_CODE_ENABLE_TELEMETRY=${CLAUDE_CODE_ENABLE_TELEMETRY:-"0"}
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=${CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC:-"1"}

## Configuration for LiteLLM server
export LITELLM_SERVER_PORT=${LITELLM_SERVER_PORT:-"4000"}

# 2. Generate Claude settings

echo '{"hasCompletedOnboarding": true, "primaryApiKey": "dummy", "fastContext": true}' > /root/.claude.json

cat <<EOF > /root/.claude/settings.json
{
    "env": {
        "ANTHROPIC_BASE_URL": "http://localhost:5000",
        "ANTHROPIC_DEFAULT_OPUS_MODEL": "model-one",
        "ANTHROPIC_DEFAULT_SONNET_MODEL": "model-two",
        "ANTHROPIC_DEFAULT_HAIKU_MODEL": "model-three",
        "ANTHROPIC_API_KEY": "none",
        "CLAUDE_CODE_ENABLE_TELEMETRY": "${CLAUDE_CODE_ENABLE_TELEMETRY}",
        "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "${CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC}"
    }
}
EOF

# 3. Generate LiteLLM Config (ensure you have `GITHUB_API_KEY` in your .env)
cat <<EOF > /workspace/litellm-config.yaml
litellm_settings:
  drop_params: true
  request_timeout: 60
  set_fastapi_logging: false
  stream_response: true

model_list:
  - model_name: model-one
    litellm_params:
      model: github/${MODEL_ONE}
      api_key: "os.environ/GITHUB_API_KEY"
      # FORCE LIMITS TO STAY UNDER THE 8K SHIELD
      max_tokens: 1000
      drop_params: true

  - model_name: model-two
    litellm_params:
      model: github/${MODEL_TWO}
      api_key: "os.environ/GITHUB_API_KEY"
      # FORCE LIMITS TO STAY UNDER THE 8K SHIELD
      max_tokens: 1000
      drop_params: true

  - model_name: model-three
    litellm_params:
      model: github/${MODEL_THREE}
      api_key: "os.environ/GITHUB_API_KEY"
      # FORCE LIMITS TO STAY UNDER THE 8K SHIELD
      max_tokens: 1000
      drop_params: true

EOF

# 4. Start the Interceptor (mitmdump)
# -s: points to your python script
# --mode reverse: tells it to forward traffic to LiteLLM (Port 4000)
# -p 5000: sets the entry port for Claude Code
echo "Starting mitmproxy interceptor on port 5000..."
# Start mitmdump with absolute path to script and capture its logs
mitmdump -s /workspace/dump_proxy.py \
         --mode reverse:http://localhost:4000 \
         -p 5000 \
         --set termlog_verbosity=debug > /workspace/mitmproxy.log 2>&1 &

# 5. Start LiteLLM Proxy in the background
echo "Starting LiteLLM Proxy on port 4000..."
litellm --config /workspace/litellm-config.yaml --port 4000 --detailed_debug

# 6. Wait for LiteLLM to be ready
echo "Waiting for LiteLLM to be ready on port 4000..."
MAX_RETRIES=30
RETRY_COUNT=0

until $(curl --output /dev/null --silent --fail http://localhost:4000/health/readiness); do
    if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
      echo "LiteLLM failed to start within $MAX_RETRIES seconds."
      exit 1
    fi
    echo "LiteLLM is still starting... ($RETRY_COUNT/$MAX_RETRIES)"
    RETRY_COUNT=$((RETRY_COUNT+1))
    sleep 1
done

echo "LiteLLM Proxy is UP!"