#!/bin/bash
#
# Starts everything the Teleport app needs on the Mac:
#
#   1. pymobiledevice3's tunnel daemon, which needs root to create the interface
#      the iPhone's developer services live behind on iOS 17+.
#   2. teleportd.py, which the app talks to and which holds the location channel open.
#
# Leave this running while you use the app. Ctrl-C restores the real GPS.

set -euo pipefail

VENV="$HOME/.fake-location-venv"
PYTHON="$VENV/bin/python"
PMD3="$VENV/bin/pymobiledevice3"
TUNNELD_URL="http://127.0.0.1:49151"
TUNNELD_LOG="/tmp/teleport-tunneld.log"

if [[ ! -x "$PYTHON" ]]; then
    echo "error: no virtualenv at $VENV" >&2
    echo "create it with:" >&2
    echo "  python3 -m venv $VENV && $VENV/bin/pip install pymobiledevice3" >&2
    exit 1
fi

tunnel_is_up() {
    curl --silent --fail --max-time 2 "$TUNNELD_URL" >/dev/null 2>&1
}

started_tunnel=""

cleanup() {
    # Only tear down a tunnel this script started; one that was already running
    # may belong to something else.
    if [[ -n "$started_tunnel" ]]; then
        echo
        echo "Stopping the developer tunnel…"
        sudo kill "$started_tunnel" 2>/dev/null || true
    fi
}
trap cleanup EXIT

if tunnel_is_up; then
    echo "Developer tunnel already running."
else
    echo "The developer tunnel needs administrator rights to start."
    sudo -v
    sudo "$PMD3" remote tunneld >"$TUNNELD_LOG" 2>&1 &
    started_tunnel=$!

    printf "Waiting for the tunnel"
    for _ in $(seq 1 30); do
        if tunnel_is_up; then
            echo " — up."
            break
        fi
        printf "."
        sleep 1
    done

    if ! tunnel_is_up; then
        echo
        echo "error: the tunnel did not come up. Last log lines:" >&2
        tail -n 15 "$TUNNELD_LOG" >&2
        exit 1
    fi
fi

echo
echo "Plug in your iPhone, unlock it, and open Teleport."
echo "Both devices must be on the same Wi-Fi for the app to find this Mac."
echo

exec "$PYTHON" "$(dirname "$0")/teleportd.py"
