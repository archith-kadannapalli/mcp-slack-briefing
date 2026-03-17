# Slack Daily Briefing Agent

An agentic daily briefing system that monitors Slack channels, generates AI-powered summaries using a **local LLM**, and answers follow-up questions — all without sending any data to external AI services.

Fork of [sodoityu/mcp-slack-briefing](https://github.com/sodoityu/mcp-slack-briefing), transformed into a fully automated, privacy-safe agentic system.

## What it does

1. **Collects** messages from your Slack channels via MCP (Model Context Protocol)
2. **Filters** for important messages (incidents, tickets, keywords, emojis)
3. **Summarizes** using a local Ollama LLM — no data leaves your machine
4. **Posts** the briefing to a Slack channel (header + threaded summary)
5. **Answers follow-up questions** in the briefing thread using the local LLM

## Quick Start

### Prerequisites

- macOS with Apple Silicon (M1/M2/M3) and 16GB RAM
- [Homebrew](https://brew.sh) installed

### 1. Clone and run setup

```bash
git clone <your-fork-url>
cd mcp-slack-briefing
chmod +x setup.sh && ./setup.sh
```

This installs Ollama, pulls the AI model, creates a Python venv, pulls the Slack MCP container, and creates config templates.

### 2. Get your Slack tokens

You need two tokens from your Slack browser session:

| Token | How to get it |
|-------|--------------|
| `xoxc-*` | Open Slack in browser > DevTools (F12) > Network tab > find a request to `api.slack.com` > look for `token` in the request body |
| `xoxd-*` | DevTools > Application > Cookies > find the cookie named `d` |

### 3. Configure

Edit `.mcp.json` — add your Slack tokens:

```json
{
  "mcpServers": {
    "slack": {
      "env": {
        "SLACK_XOXC_TOKEN": "xoxc-YOUR-ACTUAL-TOKEN",
        "SLACK_XOXD_TOKEN": "xoxd-YOUR-ACTUAL-TOKEN",
        "SLACK_WORKSPACE_URL": "https://your-workspace.slack.com"
      }
    }
  }
}
```

Edit `.env` — add your channel IDs:

```bash
# Right-click a channel in Slack > "View channel details" > ID at bottom
BRIEFING_CHANNEL_ID=C04XXXXXXXX
MONITORED_CHANNELS='[{"id":"C04XXXXXXXX","name":"your-channel"},{"id":"C01XXXXXXXX","name":"another-channel"}]'
```

### 4. Test

```bash
source venv/bin/activate
set -a; source .env; set +a

# Test collection (fetches messages from your channels)
python daily_briefing.py 24 briefing_test.txt false

# Test full pipeline (collect + summarize + post to Slack)
./run_daily_briefing.sh
```

### 5. Start Q&A listener

After a briefing is posted, start the listener to answer follow-up questions:

```bash
./start_listener.sh          # foreground (Ctrl+C to stop)
./start_listener.sh --bg     # background (logs to logs/qa_listener.log)
./stop_listener.sh           # stop background listener
```

Then reply in the briefing thread in Slack with any question — the bot answers within 10 seconds.

### 6. Automate (optional)

```bash
./setup_cron.sh
```

This sets up:
- A **cron job** to run the briefing pipeline daily at your chosen time
- A **launchd service** (macOS) to keep the Q&A listener running and auto-start on login

## How it works

```
Cron (daily)                    Your Machine
     |                    (everything runs here)
     v
daily_briefing.py -----> Slack MCP (Podman) -----> Slack API
     |                                              |
     v                                              v
briefing_YYYY-MM-DD.txt              Monitored Channels
     |
     v
ollama_summarizer.py --> Ollama (localhost:11434)
     |
     v
briefing_summary_YYYY-MM-DD.txt
     |
     v
post_summary_to_slack.py ---------> Slack Channel
     |                               |
     v                               v
qa_listener.py (polls every 10s)   User replies in thread
     |                               |
     v                               v
Ollama (generates answer) -------> Reply posted in thread
```

## Privacy & Security

No Slack data ever leaves your machine. All AI processing happens locally via Ollama.

| Safeguard | What it does |
|-----------|-------------|
| S1 - Channel allowlist | Only monitors channels you explicitly list in `.env` |
| S2 - Context scoping | Q&A answers only reference the current briefing, not all of Slack |
| S3/S4 - Access control | Channel search restricted to the allowlist |
| S5 - Thread-only replies | Bot never posts top-level messages, only in-thread |
| S6 - Local LLM only | Endpoint validated as localhost — external URLs blocked |
| S7 - No hardcoded tokens | All credentials in `.env` / `.mcp.json`, both gitignored |
| S8 - PII sanitization | Emails, phone numbers, IPs stripped before LLM sees them |

## File Structure

```
mcp-slack-briefing/
├── setup.sh                  # One-time setup (run first)
├── run_daily_briefing.sh     # Full pipeline: collect + summarize + post
├── start_listener.sh         # Start Q&A listener
├── stop_listener.sh          # Stop Q&A listener
├── setup_cron.sh             # Set up daily cron + launchd service
├── daily_briefing.py         # Message collection from Slack via MCP
├── ollama_summarizer.py      # Local Ollama summarization + Q&A
├── post_summary_to_slack.py  # Post briefing to Slack channel
├── qa_listener.py            # Poll briefing thread, answer questions
├── safeguards.py             # Security checks (S1-S8)
├── .env.example              # Environment config template
├── .mcp.json.example         # MCP/Slack config template
├── requirements.txt          # Python dependencies
├── CLAUDE.md                 # AI assistant instructions
├── AGENTIC_DESIGN.md         # Design document
└── README.md                 # This file
```

## Upgrading to OpenShift

When ready to move from local Ollama to a shared OpenShift deployment:

1. Deploy Ollama/vLLM/RHOAI on your cluster
2. Update two env vars in `.env`:
   ```bash
   OLLAMA_BASE_URL=https://llm.apps.your-cluster.internal
   OLLAMA_MODEL=your-deployed-model
   ```
3. Update `ALLOWED_LLM_HOSTS` in `safeguards.py` to include your cluster hostname
4. Everything else stays the same

## License

MIT License — based on [sodoityu/mcp-slack-briefing](https://github.com/sodoityu/mcp-slack-briefing)
