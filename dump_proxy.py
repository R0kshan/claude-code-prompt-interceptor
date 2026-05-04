import json
import os
import sys
from mitmproxy import http
from mitmproxy.net.http import http1

BASE_DIR = "/workspace/dumps"
os.makedirs(BASE_DIR, exist_ok=True)

request_count = 0

def request(flow: http.HTTPFlow):
    global request_count
    request_count += 1
    seq = request_count

    print(f"---> INTERCEPTED #{seq}: {flow.request.method} {flow.request.url}", file=sys.stdout)

    try:
        # Save raw request
        raw_bytes = http1.assemble_request(flow.request)
        with open(os.path.join(BASE_DIR, f"{seq:03d}_raw.txt"), "wb") as f:
            f.write(raw_bytes)

        # Save full JSON + extract system/messages
        if flow.request.content:
            data = json.loads(flow.request.content)

            with open(os.path.join(BASE_DIR, f"{seq:03d}_full.json"), "w") as f:
                json.dump(data, f, indent=2)

            # System prompt
            system_content = data.get("system")
            if system_content:
                with open(os.path.join(BASE_DIR, f"{seq:03d}_system.txt"), "w") as f:
                    if isinstance(system_content, list):
                        text = "\n".join([b.get("text", "") for b in system_content if b.get("type") == "text"])
                        f.write(text)
                    else:
                        f.write(str(system_content))

            # User prompts
            messages = data.get("messages", [])
            with open(os.path.join(BASE_DIR, f"{seq:03d}_messages.txt"), "w") as f:
                for m in messages:
                    role = m.get("role", "unknown")
                    content = m.get("content", "")
                    if isinstance(content, list):
                        content = "\n".join([b.get("text", str(b)) for b in content])
                    f.write(f"[{role}]\n{content}\n\n---\n\n")

            print(f"---> #{seq} saved: {len(messages)} messages, system={'yes' if system_content else 'no'}", file=sys.stdout)

    except Exception as e:
        print(f"!!! ERROR #{seq}: {str(e)}", file=sys.stdout)