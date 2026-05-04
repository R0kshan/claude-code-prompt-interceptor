FROM python:3.11-slim

RUN apt-get update && apt-get install -y \
    curl \
    gnupg \
    build-essential \
    libffi-dev \
    libssl-dev \
    python3-dev \
    gcc \
    && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir 'litellm[proxy]>=1.83.0' flask requests
RUN pip install --no-cache-dir mitmproxy


RUN npm install -g @anthropic-ai/claude-code

RUN mkdir -p /root/.claude
COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh

WORKDIR /workspace
COPY dump_proxy.py /workspace/dump_proxy.py

ENTRYPOINT ["/entrypoint.sh"]