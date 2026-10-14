#!/bin/sh
# Backs up relay and Blossom into backups/ (on the Pi) and keeps the last
# KEEP copies. Runs daily via cron (see README). For an OFF-SITE copy, another
# machine pulls backups/ regularly (rsync, see README).
#
#   relay-<date>.jsonl.gz    all events (strfry export); restore: strfry import
#   blossom-<date>.tar.gz    Blossom SQLite DB + blobs
set -eu
cd "$(dirname "$0")/.."
KEEP=${KEEP:-14}
TS=$(date +%Y-%m-%d_%H%M)
mkdir -p backups

docker compose exec -T strfry /app/strfry --config=/etc/strfry.conf export 2>/dev/null \
  | gzip -9 > "backups/relay-$TS.jsonl.gz"

# Stop Blossom briefly so the SQLite DB and the blobs match.
docker compose stop -t 20 blossom >/dev/null
tar -C data -czf "backups/blossom-$TS.tar.gz" blossom
docker compose start blossom >/dev/null

for kind in relay blossom; do
  ls -1t backups/$kind-* 2>/dev/null | tail -n +$((KEEP + 1)) | xargs -r rm -f
done
echo "Backup $TS: $(zcat backups/relay-$TS.jsonl.gz | wc -l) Events, Blossom $(du -h backups/blossom-$TS.tar.gz | cut -f1)"
