#!/bin/sh
# Run from repo root (~/rapidvoice/rapidvoice). Recreates LiveKit + egress after Redis/config changes.
set -e
cd "$(dirname "$0")/.."

echo "Starting Redis..."
docker compose up -d redis

echo "Recreating LiveKit (loads redis from livekit.yaml)..."
docker compose up -d --force-recreate livekit

echo "Waiting for LiveKit..."
sleep 5

echo "Recreating egress worker..."
docker compose up -d --force-recreate livekit-egress

echo "Restarting nginx (refresh upstream IPs after app rebuilds)..."
docker compose restart nginx

echo "--- egress logs (last 30 lines) ---"
docker logs voiceapp_livekit_egress --tail 30

echo "Done. Look for 'registered' or 'ready' in egress logs."
