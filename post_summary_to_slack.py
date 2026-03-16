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
