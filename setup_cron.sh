#!/bin/bash
#
# setup_cron.sh - Set up the daily briefing cron job and listener launchd service
#

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "============================================="
echo "  Daily Automation Setup"
echo "============================================="
echo ""

# -------------------------------------------------------
# Option 1: Cron job for daily briefing
# -------------------------------------------------------
echo "Setting up daily briefing cron job..."
echo ""

# Check if cron job already exists
if crontab -l 2>/dev/null | grep -q "run_daily_briefing.sh"; then
    echo "  Cron job already exists:"
    crontab -l | grep "run_daily_briefing"
    echo ""
    read -p "  Replace it? (y/n): " replace
    if [ "$replace" != "y" ]; then
        echo "  Skipped"
        echo ""
    else
        # Remove old entry and add new
        crontab -l 2>/dev/null | grep -v "run_daily_briefing.sh" | crontab -
    fi
fi

if ! crontab -l 2>/dev/null | grep -q "run_daily_briefing.sh"; then
    read -p "  What hour should the briefing run? (0-23, default 9): " HOUR
    HOUR=${HOUR:-9}

    # Add cron job
    (crontab -l 2>/dev/null; echo "0 $HOUR * * * cd $SCRIPT_DIR && ./run_daily_briefing.sh >> logs/daily_briefing.log 2>&1") | crontab -

    echo "  Cron job added: runs daily at ${HOUR}:00"
    echo "  Logs: $SCRIPT_DIR/logs/daily_briefing.log"
fi

echo ""

# -------------------------------------------------------
# Option 2: Launchd service for Q&A listener (macOS)
# -------------------------------------------------------
if [ "$(uname)" = "Darwin" ]; then
    echo "Setting up Q&A listener as macOS service..."
    echo ""

    PLIST_NAME="com.slack-briefing.qa-listener"
    PLIST_PATH="$HOME/Library/LaunchAgents/${PLIST_NAME}.plist"

    if [ -f "$PLIST_PATH" ]; then
        echo "  Launchd service already exists"
        read -p "  Replace it? (y/n): " replace_plist
        if [ "$replace_plist" = "y" ]; then
            launchctl unload "$PLIST_PATH" 2>/dev/null
            rm "$PLIST_PATH"
        else
            echo "  Skipped"
            echo ""
            echo "============================================="
            echo "  Setup Complete!"
            echo "============================================="
            exit 0
        fi
    fi

    read -p "  Install Q&A listener as auto-start service? (y/n): " install_service
    if [ "$install_service" = "y" ]; then
        mkdir -p "$HOME/Library/LaunchAgents"
        mkdir -p "$SCRIPT_DIR/logs"

        cat > "$PLIST_PATH" << PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${PLIST_NAME}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${SCRIPT_DIR}/start_listener.sh</string>
    </array>
    <key>WorkingDirectory</key>
    <string>${SCRIPT_DIR}</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>${SCRIPT_DIR}/logs/qa_listener_launchd.log</string>
    <key>StandardErrorPath</key>
    <string>${SCRIPT_DIR}/logs/qa_listener_launchd.log</string>
</dict>
</plist>
PLIST_EOF

        launchctl load "$PLIST_PATH"
        echo "  Service installed and started"
        echo "  The Q&A listener will auto-start on login"
        echo ""
        echo "  Manage with:"
        echo "    launchctl stop $PLIST_NAME    # stop"
        echo "    launchctl start $PLIST_NAME   # start"
        echo "    launchctl unload $PLIST_PATH  # remove"
        echo "    tail -f logs/qa_listener_launchd.log  # logs"
    else
        echo "  Skipped. Run manually with: ./start_listener.sh --bg"
    fi
fi

echo ""
echo "============================================="
echo "  Automation Setup Complete!"
echo "============================================="
echo ""
echo "  Daily briefing: cron runs at ${HOUR:-9}:00 AM"
echo "  Q&A listener: $([ -f "$PLIST_PATH" ] && echo 'auto-starts on login' || echo 'run manually with ./start_listener.sh')"
echo ""
