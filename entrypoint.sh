#!/usr/bin/env bash
set -Eeuo pipefail

# Read Docker secrets without placing their contents in image layers or
# docker-compose environment configuration.
read_secret() {
    local name="$1" file_var="${1}_FILE" file="${!file_var:-}"
    if [[ -n "$file" ]]; then
        [[ -r "$file" ]] || { echo "Secret file is not readable: $file" >&2; exit 1; }
        printf -v "$name" '%s' "$(<"$file")"
    fi
}

read_secret TWS_USERID
read_secret TWS_PASSWORD
read_secret VNC_SERVER_PASSWORD

[[ -n "${TWS_USERID:-}" ]] || { echo 'TWS_USERID_FILE must provide an IBKR username' >&2; exit 1; }
[[ -n "${TWS_PASSWORD:-}" ]] || { echo 'TWS_PASSWORD_FILE must provide an IBKR password' >&2; exit 1; }
[[ -n "${VNC_SERVER_PASSWORD:-}" ]] || { echo 'VNC_SERVER_PASSWORD_FILE must provide a VNC password' >&2; exit 1; }
[[ ${#VNC_SERVER_PASSWORD} -le 8 ]] || { echo 'x11vnc supports VNC passwords up to 8 characters' >&2; exit 1; }

case "${TRADING_MODE:-paper}" in
    paper|live) TRADING_MODE="${TRADING_MODE:-paper}" ;;
    *) echo 'TRADING_MODE must be paper or live' >&2; exit 1 ;;
esac

# IBC consumes its configuration file at startup. Keep the credential-bearing
# file in the container's writable layer with owner-only permissions.
umask 077
mkdir -p "$HOME/.ibc" "$HOME/.vnc" /data/settings
IBC_PID=
LIVE_FORWARD_PID=
PAPER_FORWARD_PID=
VNC_FORWARD_PID=
VNC_PID=
XVFB_PID=
IBC_CONFIG="$HOME/.ibc/config.ini"
cat > "$IBC_CONFIG" <<EOF
IbLoginId=${TWS_USERID}
IbPassword=${TWS_PASSWORD}
TradingMode=${TRADING_MODE}
ReadOnlyApi=${READ_ONLY_API:-no}
AcceptNonBrokerageAccountWarning=yes
SecondFactorAuthenticationTimeout=${TWOFA_TIMEOUT:-180}
ExistingSessionDetectedAction=primary
EOF
unset TWS_USERID TWS_PASSWORD

if [[ ! -f /data/settings/jts.ini ]]; then
    cp "$TWS_PATH/jts.ini.tmpl" /data/settings/jts.ini
    chmod 600 /data/settings/jts.ini
fi

# x11vnc's password file avoids putting the VNC password in its process args.
x11vnc -storepasswd "$VNC_SERVER_PASSWORD" "$HOME/.vnc/passwd" >/dev/null
unset VNC_SERVER_PASSWORD

Xvfb "$DISPLAY" -screen 0 "${SCREEN_SIZE:-1280x800x24}" -nolisten tcp &
XVFB_PID=$!
cleanup() {
    kill "$IBC_PID" "$LIVE_FORWARD_PID" "$PAPER_FORWARD_PID" "$VNC_FORWARD_PID" "$VNC_PID" "$XVFB_PID" 2>/dev/null || true
    wait 2>/dev/null || true
}
trap cleanup TERM INT

for _ in $(seq 1 50); do
    [[ -S /tmp/.X11-unix/X1 ]] && break
    sleep 0.1
done

x11vnc -display "$DISPLAY" -rfbauth "$HOME/.vnc/passwd" -forever -shared \
    -localhost -rfbport 5900 -noxdamage &
VNC_PID=$!
socat TCP-LISTEN:5901,bind=0.0.0.0,reuseaddr,fork TCP:127.0.0.1:5900 &
VNC_FORWARD_PID=$!

# IB Gateway listens on loopback inside the container. Forward through socat
# so Docker can publish the service to localhost on the host.
socat TCP-LISTEN:4003,bind=0.0.0.0,reuseaddr,fork TCP:127.0.0.1:4001 &
LIVE_FORWARD_PID=$!
socat TCP-LISTEN:4004,bind=0.0.0.0,reuseaddr,fork TCP:127.0.0.1:4002 &
PAPER_FORWARD_PID=$!

exec /opt/ibc/scripts/ibcstart.sh "$IB_GATEWAY_VERSION" -g \
    "--tws-path=$TWS_PATH" \
    "--ibc-path=$IBC_PATH" \
    "--ibc-ini=$IBC_CONFIG" \
    "--on2fatimeout=${TWOFA_TIMEOUT_ACTION:-exit}" \
    "--tws-settings-path=/data/settings" &
IBC_PID=$!
wait "$IBC_PID"
