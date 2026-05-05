# Ready to use Claude Code Prompt Interceptor

A ready to use docker solution (using [LiteLLM](https://docs.litellm.ai/docs/providers/github) and [mitmproxy](https://mitmproxy.org/)) to intercept, inspect, and understand the system prompt that Claude Code sends to the Anthropic Messages API on every request.

## What this repository is for

### Knowledge

Understanding what is actually being sent by Claude at every request and therefore what generates so many tokens. Knowing how Claude's system prompt is structured can also help write better CLAUDE.md files, custom prompts, and skills.
Claude Code sends a large system prompt (~26,000 characters (as of version 2.1.126)) during the first request (based on dump files). To this date, and to my knowledge, this prompt is not published in any official Anthropic documentation. A way to obtain it is to intercept the HTTP traffic between Claude Code and the API. This repository documents that method.

On free-tier models (e.g. GitHub Models API, which enforces an 8,000 token limit per request), Claude Code's system prompt alone exceeds the allowed context window, making Claude Code unusable. This repository helps understand what goes on under the hood of each request.

For testing purposes, it is possible to override this system prompt with the claude code parameter `--system-prompt`, however note that this would change Claude Code's behavior and effectiveness which is not recommended for serious usage.

---

## How it works

```
Claude Code → mitmproxy (port 5000) → LiteLLM (port 4000) → GitHub Models API
```

[mitmproxy](https://mitmproxy.org/) is an open-source man-in-the-middle HTTP proxy. It sits between Claude Code and LiteLLM, intercepts every outgoing API request, and writes the full payload to disk before forwarding it upstream.

- **Port 5000** — mitmproxy listens here. Claude Code is configured to send requests here via `ANTHROPIC_BASE_URL`.
- **Port 4000** — LiteLLM listens here. It translates Anthropic API format to the GitHub Models API format and forwards requests.
- **`dump_proxy.py`** — a mitmproxy addon script that extracts and saves each intercepted request to `/workspace/dumps/`.

Each intercepted request produces numbered files:

- `001_raw.txt` — raw HTTP bytes
- `001_full.json` — complete request payload
- `001_system.txt` — extracted Claude system prompt text
- `001_messages.txt` — conversation history including your user prompts

### Models used in this example

This example uses [GitHub Models](https://github.com/marketplace/models) free tier via LiteLLM. GitHub Models exposes OpenAI-compatible models (e.g. `gpt-4o-mini`) for free with a per-request token limit of ~8,000 tokens. LiteLLM acts as a translation layer, converting Anthropic API calls from Claude Code into the format GitHub Models expects.

You will need a GitHub personal access token with `models:read` permission set as the `GITHUB_API_KEY` environnement variable.

The models used can be overridden at runtime via environment variables — `MODEL_ONE`, `MODEL_TWO`, and `MODEL_THREE` — allowing you to swap in any model supported by LiteLLM's GitHub Models provider without rebuilding the image.

---

## How to use

The examples use `podman` but `docker` works identically.

### Build the image

```bash
podman build . -t claude-code-prompt-interceptor
```

### Run the image

In a first terminal, start the container:

```bash
podman run -e GITHUB_API_KEY=<your-token> --name my-interceptor -it claude-code-prompt-interceptor /bin/bash
```

In a second terminal, open a shell inside the running container:

```bash
podman exec -it $(podman ps -q --filter "name=my-interceptor") /bin/bash
```

Then start Claude Code:

```bash
claude
```

> **Note:** Run `/status` inside Claude Code to confirm it is targeting port 5000 where mitmproxy is listening.

### Trigger the interception

Type anything in Claude Code, for example `hi`. Depending on the model's context
limit, you may see the following error — this is expected:

> litellm.exceptions.APIError: APIError: GithubException - Request body too large for gpt-4o-mini model. Max size: 8000 tokens. INFO: "POST /v1/messages?beta=true HTTP/1.1" 413 Request Entity Too Large

Whether or not you receive this error, mitmproxy will have intercepted the request before it was rejected.

### Retrieve the dumps

Copy the intercepted files from the container to your local machine:

```bash
podman cp $(podman ps -q --filter "name=my-interceptor"):/workspace/dumps ./dumps
```

### Test the proxy directly with curl

You can also send a request manually without Claude Code to verify the proxy chain is working:

```bash
# curl → mitmproxy (5000) → LiteLLM (4000) → GitHub Models
curl -X POST http://localhost:5000/v1/messages \
     -H "Content-Type: application/json" \
     -d '{
       "model": "model-one",
       "max_tokens": 1024,
       "system": "You are a helpful assistant.",
       "messages": [{"role": "user", "content": "Hello"}]
     }'
```

---

## Disclaimer

This repository is for educational and interoperability purposes. The intercepted system prompt is Anthropic's intellectual property. Do not republish it verbatim. This tool does not modify or bypass any security controls — it only reads traffic from your own local process.

The system prompt content changes with each Claude Code release and reflects the version captured at time of interception (`cc_version` is visible in the raw request headers).
