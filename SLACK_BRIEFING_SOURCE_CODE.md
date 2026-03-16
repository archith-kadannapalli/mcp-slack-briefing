# Slack Daily Briefing System - Complete Source Code

## Overview
This document contains all source code and configuration files for the Slack Daily Briefing system.

---

## Table of Contents
1. [Configuration Files](#1-configuration-files)
2. [Main Python Scripts](#2-main-python-scripts)
3. [Automation Scripts](#3-automation-scripts)
4. [Supporting Tools](#4-supporting-tools)
5. [Dependencies](#5-dependencies)
6. [Setup Documentation](#6-setup-documentation)

---

## 1. Configuration Files

### 1.1 `.mcp.json` - MCP Server Configuration

**Path**: `/home/jayu/asksre/ask-sre/.mcp.json`

```json
{
  "mcpServers": {
    "ask-sre": {
      "type": "stdio",
      "command": "poetry",
      "args": [
        "run",
        "ask-sre",
        "mcp"
      ],
      "env": {}
    },
    "slack": {
      "command": "podman",
      "args": [
        "run",
        "-i",
        "--rm",
        "-e",
        "SLACK_XOXC_TOKEN",
        "-e",
        "SLACK_XOXD_TOKEN",
        "-e",
        "LOGS_CHANNEL_ID",
        "-e",
        "MCP_TRANSPORT",
        "quay.io/redhat-ai-tools/slack-mcp"
      ],
      "env": {
        "SLACK_XOXC_TOKEN": "<your-xoxc-token>",
        "SLACK_XOXD_TOKEN": "<your-xoxd-token>",
        "SLACK_WORKSPACE_URL": "https://redhat.enterprise.slack.com",
        "LOGS_CHANNEL_ID": "C0AKQ7SD0RZ",
        "MCP_TRANSPORT": "stdio"
      }
    }
  }
}
```

**Description**:
- Configures two MCP servers: `ask-sre` (custom) and `slack` (containerized)
- Slack server runs in Podman container with environment variables
- Tokens should be replaced with actual values from Slack session

**How to Get Slack Tokens**:
1. Open Slack in browser
2. Login to workspace
3. Open DevTools → Network tab
4. Look for requests to `api.slack.com`
5. Find `xoxc-*` token in cookies
6. Find `xoxd-*` token in requests

---

## 2. Main Python Scripts

### 2.1 `daily_briefing.py` - Core Collection Script

**Path**: `/home/jayu/asksre/ask-sre/daily_briefing.py`

```python
#!/usr/bin/env python3
"""
Daily Briefing Generator - Collects important Slack messages from multiple channels.
Claude Code will then summarize them into a formatted daily briefing.
"""
import asyncio
import json
import sys
import re
from datetime import datetime, timedelta
from typing import List, Dict, Any

# Try to import required packages
try:
    from mcp import ClientSession, StdioServerParameters
    from mcp.client.stdio import stdio_client
except ImportError:
    print("Error: MCP SDK not installed.")
    print("Install it with: poetry add mcp")
    sys.exit(1)

# Anthropic not needed - Claude Code will do the summarization!


class DailyBriefing:
    def __init__(self, config_path: str = '.mcp.json'):
        """Initialize the daily briefing generator."""
        with open(config_path, 'r') as f:
            config = json.load(f)

        self.slack_config = config['mcpServers']['slack']

    async def fetch_channel_history(
        self,
        channel_id: str,
        channel_name: str,
        hours_back: int = 24
    ) -> List[str]:
        """Fetch messages from a channel for the last N hours."""
        oldest_date = (datetime.now() - timedelta(hours=hours_back)).strftime("%Y-%m-%d")

        server_params = StdioServerParameters(
            command=self.slack_config['command'],
            args=self.slack_config['args'],
            env=self.slack_config['env']
        )

        messages = []

        async with stdio_client(server_params) as (read, write):
            async with ClientSession(read, write) as session:
                await session.initialize()

                # Call get_channel_history
                result = await session.call_tool(
                    "get_channel_history",
                    arguments={
                        "channel_id": channel_id,
                        "oldest": oldest_date,
                        "limit": 1000,
                        "include_threads": False
                    }
                )

                # Parse results
                if result.content:
                    for content_item in result.content:
                        if hasattr(content_item, 'text'):
                            try:
                                data = json.loads(content_item.text)
                                if isinstance(data, dict) and 'result' in data:
                                    msgs = data['result']
                                elif isinstance(data, list):
                                    msgs = data
                                else:
                                    msgs = [content_item.text]
                            except json.JSONDecodeError:
                                # Skip log messages
                                if content_item.text.startswith(("Retrieved", "Getting")):
                                    continue
                                msgs = [content_item.text]

                            messages.extend(msgs)

        return messages

    def filter_important_messages(self, messages: List[str]) -> List[str]:
        """Filter messages based on importance indicators."""
        # Ticket/Issue patterns
        ticket_patterns = [
            r'ITN-2026-\d+',
            r'ARO-\d+',
            r'SREP-\d+',
            r'OHSS-\d+',
            r'OCPBUGS-\d+',
            r'PR #\d+',
            r'MR #\d+',
        ]

        # Important keywords
        important_keywords = [
            'BUG', 'ISSUE', 'Incidents', 'incident', 'stuck', 'upgrade',
            'Blocked', 'blocked', 'paused', 'error', 'warning',
            'ASAP', 'urgent', 'critical', 'outage', 'failed', 'failure',
            'crash', 'down', 'investigating', 'escalate', 'priority',
            'emergency', 'hotfix', 'rollback', 'degraded', 'alert'
        ]

        # Important emojis
        important_emojis = ['🔥', '⚠️', '🚨', '❌', '⛔', '🔴', '🟡', '🆘']

        filtered = []
        for msg in messages:
            msg_lower = msg.lower()

            # Check for ticket/issue references
            has_ticket = any(re.search(pattern, msg, re.IGNORECASE) for pattern in ticket_patterns)

            # Check for important keywords
            has_keyword = any(keyword.lower() in msg_lower for keyword in important_keywords)

            # Check for important emojis
            has_emoji = any(emoji in msg for emoji in important_emojis)

            if has_ticket or has_keyword or has_emoji:
                filtered.append(msg)

        return filtered

    def format_messages_for_review(
        self,
        channels_data: Dict[str, List[str]],
        start_date: str,
        end_date: str
    ) -> str:
        """Format messages for Claude Code to review and summarize."""
        output = f"# 📊 Collected Slack Messages for Review\n"
        output += f"**Period:** {start_date} to {end_date}\n\n"

        # Add channel emoji mapping
        channel_emojis = {
            'forum-rosa-support': '🔵',
            'team-rosa-hcp-platform': '🟣',
            'hcm-aro-hcp-triage': '🔴',
            'forum-aro-eng': '🟠'
        }

        total_messages = 0
        for channel_name, messages in channels_data.items():
            emoji = channel_emojis.get(channel_name, '📢')
            total_messages += len(messages)

            output += f"\n{'═' * 80}\n"
            output += f"{emoji} **Channel: #{channel_name}**\n"
            output += f"{'═' * 80}\n"
            output += f"**Important messages found:** {len(messages)}\n\n"

            if messages:
                for i, msg in enumerate(messages, 1):
                    # Add visual separator
                    output += f"───────────────────────────────────────────────────────────────\n"

                    # Extract severity if present
                    severity = ""
                    if any(x in msg for x in ['critical', 'CRITICAL', '🔴', 'blocked', 'BLOCKED']):
                        severity = "🔴 "
                    elif any(x in msg for x in ['warning', 'WARNING', '🟡', 'degraded']):
                        severity = "🟡 "
                    elif any(x in msg for x in ['incident', 'INCIDENT', 'ITN-', '🚨']):
                        severity = "🚨 "
                    elif any(x in msg for x in ['urgent', 'URGENT', 'ASAP']):
                        severity = "⚠️ "

                    output += f"{severity}**Message {i}:**\n"
                    output += f"{msg}\n\n"
            else:
                output += f"_No important messages in this period._\n\n"

        output += f"\n{'═' * 80}\n"
        output += f"**📈 Summary Statistics**\n"
        output += f"{'═' * 80}\n"
        output += f"- Total channels monitored: {len(channels_data)}\n"
        output += f"- Total important messages: {total_messages}\n"
        output += f"- Period: {start_date} to {end_date}\n\n"

        if total_messages == 0:
            output += "\n⚠️ **No important messages found in the specified channels during this period.**\n"
        else:
            output += f"\n✅ **Ready for Claude Code to summarize!**\n"
            output += f"📝 Please review the messages above and create a Daily Briefing summary.\n"

        return output

    async def post_to_slack(
        self,
        channel_id: str,
        header_message: str,
        detailed_summary: str
    ) -> bool:
        """Post the briefing to a Slack channel with summary as threaded reply."""
        server_params = StdioServerParameters(
            command=self.slack_config['command'],
            args=self.slack_config['args'],
            env=self.slack_config['env']
        )

        async with stdio_client(server_params) as (read, write):
            async with ClientSession(read, write) as session:
                await session.initialize()

                print("  📤 Posting header message...")

                # Post header message first
                await session.call_tool(
                    "post_message",
                    arguments={
                        "channel_id": channel_id,
                        "message": header_message,
                        "skip_log": True
                    }
                )

                # Small delay to ensure message is posted
                await asyncio.sleep(1)

                # Get the latest message to extract timestamp
                history_result = await session.call_tool(
                    "get_channel_history",
                    arguments={
                        "channel_id": channel_id,
                        "limit": 5
                    }
                )

                # Extract timestamp from the most recent message
                thread_ts = None
                if history_result.content:
                    for content_item in history_result.content:
                        if hasattr(content_item, 'text'):
                            try:
                                data = json.loads(content_item.text)
                                if isinstance(data, dict) and 'result' in data:
                                    messages = data['result']
                                    if messages:
                                        # First message should be our header
                                        first_msg = messages[0]
                                        # Extract timestamp from format: [1773226074.264849] @user: message
                                        if first_msg.startswith('['):
                                            thread_ts = first_msg.split(']')[0].strip('[')
                                            print(f"  ✅ Header posted (timestamp: {thread_ts})")
                                            break
                            except:
                                pass

                # Post detailed summary as a threaded reply
                if thread_ts:
                    print("  📝 Posting detailed summary as threaded reply...")
                    await session.call_tool(
                        "post_message",
                        arguments={
                            "channel_id": channel_id,
                            "message": detailed_summary,
                            "thread_ts": thread_ts,
                            "skip_log": True
                        }
                    )
                    print("  ✅ Threaded reply posted successfully!")
                else:
                    # Fallback: post as regular message if we couldn't get timestamp
                    print("  ⚠️  Warning: Could not get timestamp, posting as separate message")
                    await session.call_tool(
                        "post_message",
                        arguments={
                            "channel_id": channel_id,
                            "message": detailed_summary,
                            "skip_log": True
                        }
                    )

                return True

    async def create_briefing(
        self,
        channels: List[Dict[str, str]],
        hours_back: int = 24,
        post_to_channel: str = None,
        output_file: str = None,
        use_friendly_dates: bool = True
    ) -> str:
        """Create the daily briefing."""
        end_date = datetime.now()
        start_date = end_date - timedelta(hours=hours_back)

        # Create friendly date strings
        if use_friendly_dates and hours_back == 24:
            # For 24-hour briefings, show as "Yesterday to Today"
            if start_date.date() == (end_date - timedelta(days=1)).date():
                date_range_str = f"{start_date.strftime('%b %d')} (yesterday) to {end_date.strftime('%b %d')} (today)"
            else:
                date_range_str = f"{start_date.strftime('%b %d')} to {end_date.strftime('%b %d')}"
        else:
            date_range_str = f"{start_date.strftime('%b %d')} to {end_date.strftime('%b %d')}"

        print(f"📊 Daily Briefing Generator")
        print(f"{'=' * 80}")
        print(f"Period: {date_range_str}")
        print(f"Time range: {start_date.strftime('%Y-%m-%d %H:%M')} to {end_date.strftime('%Y-%m-%d %H:%M')}")
        print(f"Channels: {', '.join([c['name'] for c in channels])}")
        print(f"{'=' * 80}\n")

        # Fetch messages from all channels
        all_channels_data = {}

        for channel in channels:
            print(f"📥 Fetching messages from #{channel['name']}...", end=" ")
            try:
                messages = await self.fetch_channel_history(
                    channel['id'],
                    channel['name'],
                    hours_back
                )

                # Filter for important messages
                important = self.filter_important_messages(messages)

                print(f"✅ {len(messages)} total, {len(important)} important")
                all_channels_data[channel['name']] = important
            except Exception as e:
                print(f"❌ Error: {e}")
                all_channels_data[channel['name']] = []

        print(f"\n📝 Formatting messages for review...\n")

        # Format messages for Claude Code to review
        formatted_output = self.format_messages_for_review(
            all_channels_data,
            start_date.strftime("%Y-%m-%d"),
            end_date.strftime("%Y-%m-%d")
        )

        full_briefing = formatted_output

        # Save to file
        if output_file:
            with open(output_file, 'w') as f:
                f.write(full_briefing)
            print(f"💾 Saved to: {output_file}\n")

        # Store formatted output for manual posting
        self._last_briefing_data = {
            'formatted_output': full_briefing,
            'start_date': start_date.strftime("%Y-%m-%d"),
            'end_date': end_date.strftime("%Y-%m-%d"),
            'date_range_str': date_range_str,
            'hours_back': hours_back,
            'channels': channels
        }

        return full_briefing

    async def post_briefing_to_slack(
        self,
        channel_id: str,
        summary_text: str,
        start_date: str,
        end_date: str
    ):
        """Post a briefing summary to Slack with header + threaded detail."""
        # Create short header message
        header = f"""📋 Daily Briefing — {start_date} to {end_date}
✅ Summary ready! See thread for details 👇"""

        # Post to Slack (header + threaded summary)
        print(f"\n📤 Posting to Slack channel {channel_id}...")
        try:
            await self.post_to_slack(channel_id, header, summary_text)
            print(f"\n✅ Posted to Slack successfully!\n")
        except Exception as e:
            print(f"\n❌ Error posting to Slack: {e}\n")


async def main():
    """Main function."""
    # Channel configuration
    channels = [
        {"id": "CCX9DB894", "name": "forum-rosa-support"},
        {"id": "C0A9G5A7TLH", "name": "team-rosa-hcp-platform"},
        {"id": "C099PKYT1M2", "name": "hcm-aro-hcp-triage"},
        {"id": "CCV9YF9PD", "name": "forum-aro-eng"},
    ]

    # Target channel for posting
    post_channel = "C04F0GWTD9B"  # cee-mcs-china

    # Parse command line arguments
    hours_back = 24
    output_file = f"briefing_{datetime.now().strftime('%Y-%m-%d')}.txt"
    post_to_slack = True

    if len(sys.argv) > 1:
        hours_back = int(sys.argv[1])
    if len(sys.argv) > 2:
        output_file = sys.argv[2]
    if len(sys.argv) > 3:
        post_to_slack = sys.argv[3].lower() in ['true', 'yes', '1']

    # Create briefing
    briefing = DailyBriefing()
    summary = await briefing.create_briefing(
        channels=channels,
        hours_back=hours_back,
        post_to_channel=post_channel if post_to_slack else None,
        output_file=output_file
    )

    print(f"{'=' * 80}")
    print(summary)
    print(f"{'=' * 80}")
    print("\n✅ Daily briefing generated successfully!")


if __name__ == "__main__":
    print(f"{'=' * 80}")
    print("Daily Briefing Generator for ROSA/ARO/HCP")
    print(f"{'=' * 80}")
    print(f"Usage: {sys.argv[0]} [hours_back] [output_file] [post_to_slack]")
    print(f"Example: {sys.argv[0]} 24 briefing.txt true")
    print(f"{'=' * 80}\n")

    asyncio.run(main())
```

**Usage**:
```bash
# Default: Collect last 24 hours
poetry run python daily_briefing.py

# Custom time range and output
poetry run python daily_briefing.py 48 briefing_2days.txt false

# Parameters: [hours_back] [output_file] [post_to_slack]
```

---

### 2.2 `post_summary_to_slack.py` - Slack Posting Script

**Path**: `/home/jayu/asksre/ask-sre/post_summary_to_slack.py`

```python
#!/usr/bin/env python3
"""
Post a briefing summary to Slack with header + threaded reply.
Usage: python post_summary_to_slack.py <summary_file> <start_date> <end_date> [channel_id]
"""
import asyncio
import json
import sys
from datetime import datetime

try:
    from mcp import ClientSession, StdioServerParameters
    from mcp.client.stdio import stdio_client
except ImportError:
    print("Error: MCP SDK not installed.")
    sys.exit(1)


async def post_briefing(channel_id: str, start_date: str, end_date: str, summary: str):
    """Post briefing with header message + threaded summary."""
    # Load Slack config
    with open('.mcp.json', 'r') as f:
        config = json.load(f)

    slack_config = config['mcpServers']['slack']

    server_params = StdioServerParameters(
        command=slack_config['command'],
        args=slack_config['args'],
        env=slack_config['env']
    )

    async with stdio_client(server_params) as (read, write):
        async with ClientSession(read, write) as session:
            await session.initialize()

            # Create header
            header = f"""📋 Daily Briefing — {start_date} to {end_date}
✅ Summary ready! See thread for details 👇"""

            print("📤 Posting header message...")

            # Post header message
            await session.call_tool(
                "post_message",
                arguments={
                    "channel_id": channel_id,
                    "message": header,
                    "skip_log": True
                }
            )

            # Small delay
            await asyncio.sleep(1)

            # Get latest message timestamp
            history_result = await session.call_tool(
                "get_channel_history",
                arguments={
                    "channel_id": channel_id,
                    "limit": 3
                }
            )

            thread_ts = None
            if history_result.content:
                for content_item in history_result.content:
                    if hasattr(content_item, 'text'):
                        try:
                            data = json.loads(content_item.text)
                            if isinstance(data, dict) and 'result' in data:
                                messages = data['result']
                                if messages:
                                    first_msg = messages[0]
                                    if first_msg.startswith('['):
                                        thread_ts = first_msg.split(']')[0].strip('[')
                                        print(f"✅ Header posted (timestamp: {thread_ts})")
                                        break
                        except:
                            pass

            if thread_ts:
                print("📝 Posting detailed summary as threaded reply...")
                await session.call_tool(
                    "post_message",
                    arguments={
                        "channel_id": channel_id,
                        "message": summary,
                        "thread_ts": thread_ts,
                        "skip_log": True
                    }
                )
                print("✅ Threaded reply posted successfully!")
            else:
                print("⚠️  Could not get timestamp, posting as separate message...")
                await session.call_tool(
                    "post_message",
                    arguments={
                        "channel_id": channel_id,
                        "message": summary,
                        "skip_log": True
                    }
                )


if __name__ == "__main__":
    if len(sys.argv) < 4:
        print("Usage: python post_summary_to_slack.py <summary_file> <start_date> <end_date> [channel_id]")
        print("Example: python post_summary_to_slack.py briefing_summary.txt 2026-03-10 2026-03-11 C04F0GWTD9B")
        sys.exit(1)

    summary_file = sys.argv[1]
    start_date = sys.argv[2]
    end_date = sys.argv[3]
    channel_id = sys.argv[4] if len(sys.argv) > 4 else "C04F0GWTD9B"

    # Read summary from file
    with open(summary_file, 'r') as f:
        summary_content = f.read()

    print(f"Posting to channel: {channel_id}")
    print(f"Date range: {start_date} to {end_date}\n")

    asyncio.run(post_briefing(channel_id, start_date, end_date, summary_content))
```

**Usage**:
```bash
poetry run python post_summary_to_slack.py briefing_summary_2026-03-11.txt 2026-03-10 2026-03-11 C04F0GWTD9B
```

---

## 3. Automation Scripts

### 3.1 `run_daily_briefing.sh` - Cron Runner Script

**Path**: `/home/jayu/asksre/ask-sre/run_daily_briefing.sh`

```bash
#!/bin/bash
#
# Daily Briefing Runner Script
# This script runs the daily briefing and posts to Slack
#

# Set working directory
cd /home/jayu/asksre/ask-sre

# Export API key if needed (uncomment and set your key)
# export ANTHROPIC_API_KEY="your-api-key-here"

# Set date for filename
DATE=$(date +%Y-%m-%d)

# Run the collection script
echo "$(date): Running daily briefing collection..."
poetry run python daily_briefing.py 24 "briefing_${DATE}.txt" false

# Check if collection succeeded
if [ $? -eq 0 ]; then
    echo "$(date): Collection completed successfully"
    echo "$(date): Output saved to briefing_${DATE}.txt"

    # Send Slack DM notification
    echo "$(date): Sending notification to Slack..."
    poetry run python - <<'PYTHON_EOF'
import asyncio, json
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client
from datetime import datetime

async def send_notification():
    with open('.mcp.json') as f:
        config = json.load(f)

    params = StdioServerParameters(
        command=config['mcpServers']['slack']['command'],
        args=config['mcpServers']['slack']['args'],
        env=config['mcpServers']['slack']['env']
    )

    async with stdio_client(params) as (r, w):
        async with ClientSession(r, w) as session:
            await session.initialize()

            # Send DM to user
            date_str = datetime.now().strftime('%B %d, %Y')
            message = f"""📋 Daily Briefing Ready for Review

Date: {date_str}
Status: ✅ Collection completed successfully

The daily briefing has been collected from:
• #forum-rosa-support
• #team-rosa-hcp-platform
• #hcm-aro-hcp-triage
• #forum-aro-eng

To review and post:
1. Open Claude Code
2. Say "Create today's daily briefing"
3. Review the summary
4. Approve posting to #cee-mcs-china

File: briefing_{datetime.now().strftime('%Y-%m-%d')}.txt"""

            await session.call_tool(
                'send_dm',
                arguments={
                    'user_id': 'U04601MFNTV',
                    'message': message
                }
            )
            print("DM notification sent successfully")

asyncio.run(send_notification())
PYTHON_EOF

    if [ $? -eq 0 ]; then
        echo "$(date): Notification sent successfully"
    else
        echo "$(date): Warning: Notification failed (briefing still collected)"
    fi

else
    echo "$(date): Collection failed!"
    exit 1
fi

echo "$(date): Daily briefing job completed"
```

**Setup**:
```bash
# Make executable
chmod +x run_daily_briefing.sh

# Test manually
./run_daily_briefing.sh

# Add to cron
crontab -e
# Add: 0 23 * * * /home/jayu/asksre/ask-sre/run_daily_briefing.sh >> /home/jayu/asksre/ask-sre/logs/daily_briefing.log 2>&1
```

---

## 4. Supporting Tools

### 4.1 `search_sfdc_cases.py` - Red Hat Support Case Search

**Path**: `/home/jayu/asksre/ask-sre/search_sfdc_cases.py`

```python
#!/usr/bin/env python3
"""
Search Red Hat Support Cases (SFDC) and save results for AI analysis
Based on: https://access.redhat.com/articles/3626371
"""
import requests
import json
import sys
from datetime import datetime


class SFDCSearcher:
    def __init__(self, offline_token):
        self.offline_token = offline_token
        self.access_token = None
        self.base_url = "https://api.access.redhat.com/support/v1"

    def get_access_token(self):
        """Get access token from offline token"""
        url = "https://sso.redhat.com/auth/realms/redhat-external/protocol/openid-connect/token"
        payload = {
            'grant_type': 'refresh_token',
            'client_id': 'rhsm-api',
            'refresh_token': self.offline_token
        }
        try:
            response = requests.post(url, data=payload, timeout=30)
            response.raise_for_status()
            self.access_token = response.json()['access_token']
            return self.access_token
        except Exception as e:
            print(f"Error getting access token: {e}", file=sys.stderr)
            sys.exit(1)

    def search_cases(self, keyword=None, status=None, severity=None, limit=20):
        """
        Search support cases

        Args:
            keyword: Search keyword (searches summary, description)
            status: Case status (e.g., 'Waiting on Red Hat', 'Closed')
            severity: Case severity (1-4)
            limit: Max number of results
        """
        if not self.access_token:
            self.get_access_token()

        headers = {'Authorization': f'Bearer {self.access_token}'}

        # Build query parameters
        params = {
            'count': limit,
            'start': 0
        }

        # Add filters if provided
        if keyword:
            params['keyword'] = keyword
        if status:
            params['status'] = status
        if severity:
            params['severity'] = severity

        try:
            url = f"{self.base_url}/cases"
            print(f"Searching cases with params: {params}", file=sys.stderr)

            response = requests.get(url, headers=headers, params=params, timeout=60)
            response.raise_for_status()

            data = response.json()

            # Handle different response formats
            if isinstance(data, list):
                return {'cases': data, 'total': len(data)}
            elif isinstance(data, dict):
                cases = data.get('case', data.get('cases', []))
                if not isinstance(cases, list):
                    cases = [cases] if cases else []
                return {'cases': cases, 'total': len(cases)}
            else:
                return {'cases': [], 'total': 0}

        except requests.exceptions.HTTPError as e:
            print(f"HTTP Error: {e.response.status_code}", file=sys.stderr)
            print(f"Response: {e.response.text[:500]}", file=sys.stderr)
            return {'cases': [], 'total': 0}
        except Exception as e:
            print(f"Error searching cases: {e}", file=sys.stderr)
            return {'cases': [], 'total': 0}

    def format_results(self, data):
        """Format search results for display"""
        cases = data.get('cases', [])
        total = data.get('total', 0)

        lines = []
        lines.append(f"Found {total} cases (showing {len(cases)})")
        lines.append("=" * 80)

        for case in cases:
            case_number = case.get('caseNumber', case.get('case_number', case.get('id', 'N/A')))
            summary = case.get('summary', case.get('subject', 'N/A'))
            status = case.get('status', 'N/A')
            severity = case.get('severity', case.get('severityCode', 'N/A'))

            created = case.get('createdDate', case.get('created_date', ''))
            if created:
                created = created[:10]

            updated = case.get('lastModifiedDate', case.get('last_modified_date', ''))
            if updated:
                updated = updated[:10]

            account = case.get('accountNumber', case.get('account_number', 'N/A'))
            product = case.get('product', case.get('productCode', 'N/A'))

            lines.append(f"\n🎫 Case {case_number}: {summary}")
            lines.append(f"   Status: {status} | Severity: {severity} | Product: {product}")
            if created:
                lines.append(f"   Created: {created} | Updated: {updated}")
            lines.append(f"   Account: {account}")
            lines.append(f"   URL: https://access.redhat.com/support/cases/{case_number}")

            description = case.get('description', case.get('issue', ''))
            if description:
                preview = description[:200].replace('\n', ' ').replace('\r', ' ')
                lines.append(f"   Description: {preview}...")

        lines.append("\n" + "=" * 80)
        return "\n".join(lines)


def main():
    if len(sys.argv) < 2:
        print("Usage: python search_sfdc_cases.py <keyword> [--status STATUS] [--severity N] [--limit N] [--output FILE]")
        print("\nExamples:")
        print("  python search_sfdc_cases.py 'upgrade stuck' --limit 20 --output cases.txt")
        print("  python search_sfdc_cases.py 'network error' --severity 2 --output urgent_cases.txt")
        sys.exit(1)

    # Offline token (replace with your own)
    offline_token = "YOUR_OFFLINE_TOKEN_HERE"

    # Parse arguments
    keyword = sys.argv[1]
    status = None
    severity = None
    limit = 20
    output_file = None

    i = 2
    while i < len(sys.argv):
        if sys.argv[i] == '--status' and i + 1 < len(sys.argv):
            status = sys.argv[i + 1]
            i += 2
        elif sys.argv[i] == '--severity' and i + 1 < len(sys.argv):
            severity = sys.argv[i + 1]
            i += 2
        elif sys.argv[i] == '--limit' and i + 1 < len(sys.argv):
            limit = int(sys.argv[i + 1])
            i += 2
        elif sys.argv[i] == '--output' and i + 1 < len(sys.argv):
            output_file = sys.argv[i + 1]
            i += 2
        else:
            i += 1

    # Create searcher and search
    searcher = SFDCSearcher(offline_token)
    results = searcher.search_cases(keyword, status, severity, limit)

    # Format and print results
    output = searcher.format_results(results)
    print(output)

    # Save to file if requested
    if output_file:
        with open(output_file, 'w') as f:
            f.write(f"Red Hat Support Cases Search Results\n")
            f.write(f"Keyword: {keyword}\n")
            if status:
                f.write(f"Status: {status}\n")
            if severity:
                f.write(f"Severity: {severity}\n")
            f.write(f"Search date: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
            f.write(f"\n{output}\n")
            f.write("\n\n" + "=" * 80 + "\n")
            f.write("RAW JSON DATA (for AI analysis):\n")
            f.write("=" * 80 + "\n")
            f.write(json.dumps(results, indent=2))

        print(f"\n✅ Results saved to {output_file}")


if __name__ == "__main__":
    main()
```

---

### 4.2 `search_jira.py` - Jira Ticket Search

**Path**: `/home/jayu/asksre/ask-sre/search_jira.py`

```python
#!/usr/bin/env python3
"""
Search Jira tickets for similar symptoms across multiple fields
"""
import requests
import sys
import json
from typing import List, Dict


class JiraSearcher:
    def __init__(self, bearer_token: str):
        self.base_url = "https://issues.redhat.com/rest/api/2"
        self.headers = {
            "Authorization": f"Bearer {bearer_token}",
            "Content-Type": "application/json"
        }

    def search_issues(self, search_terms: List[str], projects: List[str] = None, max_results: int = 20, skip_comments: bool = False) -> Dict:
        """
        Search for issues containing the search terms in summary, description, or comments
        """
        # Build JQL query
        search_conditions = []
        for term in search_terms:
            escaped_term = term.replace('"', '\\"')
            if skip_comments:
                search_conditions.append(
                    f'(summary ~ "{escaped_term}" OR description ~ "{escaped_term}")'
                )
            else:
                search_conditions.append(
                    f'(summary ~ "{escaped_term}" OR description ~ "{escaped_term}" OR comment ~ "{escaped_term}")'
                )

        jql_parts = []

        if projects:
            project_filter = " OR ".join([f'project = {p}' for p in projects])
            jql_parts.append(f"({project_filter})")

        if search_conditions:
            jql_parts.append(f"({' OR '.join(search_conditions)})")

        jql = " AND ".join(jql_parts)
        jql += " ORDER BY updated DESC"

        params = {
            "jql": jql,
            "maxResults": max_results,
            "fields": "summary,description,status,priority,assignee,created,updated,components,labels"
        }

        print(f"\nJQL Query: {jql}\n", file=sys.stderr)

        try:
            response = requests.get(
                f"{self.base_url}/search",
                headers=self.headers,
                params=params,
                timeout=60
            )
            response.raise_for_status()
            return response.json()
        except requests.exceptions.RequestException as e:
            print(f"Error searching Jira: {e}", file=sys.stderr)
            if hasattr(e.response, 'text'):
                print(f"Response: {e.response.text}", file=sys.stderr)
            return {"issues": []}

    def format_results(self, results: Dict) -> str:
        """Format search results for display"""
        issues = results.get('issues', [])
        total = results.get('total', 0)

        output = []
        output.append(f"Found {total} matching issues (showing {len(issues)}):\n")
        output.append("=" * 80)

        for issue in issues:
            key = issue['key']
            fields = issue['fields']
            summary = fields.get('summary', 'N/A')
            status = fields.get('status', {}).get('name', 'N/A')
            priority = fields.get('priority', {}).get('name', 'N/A')
            assignee = fields.get('assignee', {})
            assignee_name = assignee.get('displayName', 'Unassigned') if assignee else 'Unassigned'
            updated = fields.get('updated', 'N/A')[:10]

            components = fields.get('components', [])
            component_names = [c['name'] for c in components] if components else []

            labels = fields.get('labels', [])

            output.append(f"\n🔗 {key}: {summary}")
            output.append(f"   Status: {status} | Priority: {priority} | Assignee: {assignee_name}")
            output.append(f"   Updated: {updated}")
            if component_names:
                output.append(f"   Components: {', '.join(component_names)}")
            if labels:
                output.append(f"   Labels: {', '.join(labels)}")
            output.append(f"   URL: https://issues.redhat.com/browse/{key}")

            description = fields.get('description', '')
            if description:
                desc_preview = description[:200].replace('\n', ' ')
                output.append(f"   Description: {desc_preview}...")

        output.append("\n" + "=" * 80)
        return "\n".join(output)


def main():
    if len(sys.argv) < 2:
        print("Usage: python search_jira.py <search_term> [search_term2] ... [--projects PROJECT1,PROJECT2] [--output FILE] [--skip-comments]")
        print("\nExamples:")
        print("  python search_jira.py 'upgrade stuck' 'etcd timeout'")
        print("  python search_jira.py 'network error' --projects OHSS,OCPBUGS")
        sys.exit(1)

    # Bearer token (replace with your own)
    BEARER_TOKEN = "YOUR_JIRA_BEARER_TOKEN"

    # Parse arguments
    search_terms = []
    projects = None
    output_file = None
    skip_comments = False

    i = 1
    while i < len(sys.argv):
        if sys.argv[i] == '--projects':
            if i + 1 < len(sys.argv):
                projects = sys.argv[i + 1].split(',')
                i += 2
        elif sys.argv[i] == '--output':
            if i + 1 < len(sys.argv):
                output_file = sys.argv[i + 1]
                i += 2
        elif sys.argv[i] == '--skip-comments':
            skip_comments = True
            i += 1
        else:
            search_terms.append(sys.argv[i])
            i += 1

    if not search_terms:
        print("Error: No search terms provided")
        sys.exit(1)

    searcher = JiraSearcher(BEARER_TOKEN)
    results = searcher.search_issues(search_terms, projects, skip_comments=skip_comments)

    output = searcher.format_results(results)
    print(output)

    if output_file:
        with open(output_file, 'w') as f:
            f.write(f"Search terms: {', '.join(search_terms)}\n")
            if projects:
                f.write(f"Projects: {', '.join(projects)}\n")
            f.write(f"Search scope: {'Summary and Description only' if skip_comments else 'Summary, Description, and Comments'}\n")
            f.write(f"\n{output}\n")
            f.write("\n\n" + "="*80 + "\n")
            f.write("RAW DATA FOR AI ANALYSIS:\n")
            f.write("="*80 + "\n")
            f.write(json.dumps(results, indent=2))
        print(f"\n✅ Results saved to {output_file}")


if __name__ == "__main__":
    main()
```

---

## 5. Dependencies

### 5.1 `pyproject.toml` - Poetry Dependencies

**Path**: `/home/jayu/asksre/ask-sre/pyproject.toml`

```toml
[project]
name = "ask-sre"
version = "0.1.0"
description = "Ask SRE is a MCP server which queries the SRE knowledge base"
authors = [{name = "Team Thor", email = "sd-sre-platform-team-thor@redhat.com"}]
readme = "README.md"
requires-python = ">=3.12"

[tool.poetry.dependencies]
python = "^3.12"
python-dotenv = "^1.0.0"
cyclopts = "^3.24.0"
fastmcp = "^2.13"
sentence-transformers = "^3.3.0"
requests = "^2.32.0"
ragas = "^0.3.7"
claude-agent-sdk = "^0.1.4"
rich = "^14.2.0"
psycopg = {extras = ["binary", "pool"], version = "^3.2.0"}
pgvector = "^0.3.0"
boto3 = "^1.41.2"
pyjwt = {extras = ["crypto"], version = "^2.10.1"}
mcp = "^1.26.0"
anthropic = "^0.84.0"

[tool.poetry.group.dev.dependencies]
ruff = "^0.8.0"
mypy = "^1.11.0"
black = "^24.10.0"
types-requests = "^2.32.0"
types-pyyaml = "^6.0.0"
pytest = "^8.0.0"
pytest-mock = "^3.12.0"
pytest-env = "^1.1.0"
pytest-cov = "^4.1.0"
pytest-asyncio = "^1.2.0"

[build-system]
requires = ["poetry-core"]
build-backend = "poetry.core.masonry.api"

[project.scripts]
ask-sre = "ask_sre.cli:app"
```

**Installation**:
```bash
# Install all dependencies
poetry install

# Or using pip
pip install mcp anthropic requests python-dotenv
```

---

## 6. Setup Documentation

### 6.1 Cron Setup Guide (from `CRON_SETUP.md`)

**Key Steps**:

1. **Check Server Timezone**:
```bash
timedatectl
TZ='Australia/Brisbane' date
```

2. **Edit Crontab**:
```bash
crontab -e
```

3. **Add Cron Entry** (for 9 AM Brisbane = 11 PM previous day UTC):
```cron
0 23 * * * /home/jayu/asksre/ask-sre/run_daily_briefing.sh >> /home/jayu/asksre/ask-sre/logs/daily_briefing.log 2>&1
```

4. **Create Log Directory**:
```bash
mkdir -p /home/jayu/asksre/ask-sre/logs
```

5. **Test Manual Execution**:
```bash
/home/jayu/asksre/ask-sre/run_daily_briefing.sh
```

6. **Monitor Logs**:
```bash
tail -f /home/jayu/asksre/ask-sre/logs/daily_briefing.log
```

---

## File Structure Summary

```
/home/jayu/asksre/ask-sre/
├── .mcp.json                       # MCP server configuration
├── daily_briefing.py               # Main collection script
├── post_summary_to_slack.py        # Slack posting script
├── run_daily_briefing.sh           # Cron automation script
├── search_sfdc_cases.py            # SFDC case search tool
├── search_jira.py                  # Jira ticket search tool
├── pyproject.toml                  # Python dependencies
├── CRON_SETUP.md                   # Cron setup guide
├── SLACK_BRIEFING_SHOWCASE.md      # Technical documentation (this showcase)
├── SLACK_BRIEFING_SOURCE_CODE.md   # Complete source code (this file)
└── logs/
    └── daily_briefing.log          # Automation logs
```

---

## Quick Start Guide

### 1. Install Dependencies
```bash
cd /home/jayu/asksre/ask-sre
poetry install
```

### 2. Configure Slack Tokens
Edit `.mcp.json` and add your Slack tokens:
- `SLACK_XOXC_TOKEN`
- `SLACK_XOXD_TOKEN`

### 3. Test Collection Manually
```bash
poetry run python daily_briefing.py
```

### 4. Setup Cron (Optional)
```bash
crontab -e
# Add: 0 23 * * * /home/jayu/asksre/ask-sre/run_daily_briefing.sh >> /home/jayu/asksre/ask-sre/logs/daily_briefing.log 2>&1
```

### 5. Generate Summary with Claude Code
```
User: "Create today's daily briefing"
Claude: [Reads briefing file, generates summary]
User: "Post it to Slack"
Claude: [Uses post_summary_to_slack.py]
```

---

## Example Output

See `briefing_summary_2026-03-11.txt` for an example of AI-generated summary format.

---

**End of Source Code Documentation**
