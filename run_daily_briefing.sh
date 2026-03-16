#!/bin/bash
#
# Daily Briefing Runner Script
# This script runs the daily briefing and posts to Slack
#

# Set working directory
cd /home/YOUR_USER/path/to/mcp-slack-briefing

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

            # Send DM to user - UPDATE WITH YOUR USER ID
            date_str = datetime.now().strftime('%B %d, %Y')
            message = f"""📋 Daily Briefing Ready for Review

Date: {date_str}
Status: ✅ Collection completed successfully

The daily briefing has been collected from:
• #your-channel-1
• #your-channel-2
• #your-channel-3
• #your-channel-4

To review and post:
1. Open Claude Code
2. Say "Create today's daily briefing"
3. Review the summary
4. Approve posting to #your-target-channel

File: briefing_{datetime.now().strftime('%Y-%m-%d')}.txt"""

            await session.call_tool(
                'send_dm',
                arguments={
                    'user_id': 'U0XXXXXXXXX',  # UPDATE WITH YOUR SLACK USER ID
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
