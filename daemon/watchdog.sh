#!/bin/bash
# Hourly health check for claude-usage-daemon.
# Restarts the service if it's dead or hasn't sent a payload recently
# (silent staleness — e.g. an empty/expired token — doesn't crash the
# process, it just stops producing good data, so "is it running" alone
# isn't enough).
set -u

SERVICE="claude-usage-daemon.service"
STALE_AFTER_SECS=300  # poll interval is 60s; 5 missed cycles = stale

notify() {
    command -v notify-send >/dev/null 2>&1 && notify-send -u critical "Clawdmeter" "$1"
}

restart_and_check() {
    systemctl --user restart "$SERVICE"
    sleep 5
    if systemctl --user is-active --quiet "$SERVICE"; then
        notify "Watchdog restarted the daemon after: $1"
    else
        notify "Watchdog FAILED to recover the daemon after: $1 — check journalctl --user -u $SERVICE"
    fi
}

if ! systemctl --user is-active --quiet "$SERVICE"; then
    restart_and_check "service was inactive"
    exit 0
fi

last_send=$(journalctl --user -u "$SERVICE" -n 50 --no-pager 2>/dev/null \
    | grep -F 'Sending:' | tail -1 \
    | grep -oE '^[A-Za-z]{3} [0-9]{2} [0-9:]{8}')

if [ -z "$last_send" ]; then
    restart_and_check "no successful send found in recent logs"
    exit 0
fi

last_epoch=$(date -d "$last_send" +%s 2>/dev/null || echo 0)
now_epoch=$(date +%s)
age=$(( now_epoch - last_epoch ))

if [ "$age" -gt "$STALE_AFTER_SECS" ]; then
    restart_and_check "last successful send was ${age}s ago"
fi
