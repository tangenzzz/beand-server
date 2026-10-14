#!/bin/bash
# Writes the status page data/status/index.html (runs every minute via cron,
# served by the "status" container on port 8080). Collects only values that
# are available without root; a missing value shows "—" instead of failing.
set -u
cd "$(dirname "$0")/.."
OUT=data/status
mkdir -p "$OUT"
TMP=$(mktemp "$OUT/.index.XXXXXX")

esc() { sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'; }
human() { numfmt --to=iec --suffix=B "${1:-0}" 2>/dev/null || echo "${1:-0} B"; }

# --- Services --------------------------------------------------------------
svc_rows=""
all_ok=1
for s in strfry blossom status; do
  st=$(docker compose ps --format '{{.State}}|{{.Status}}' "$s" 2>/dev/null | head -1)
  state=${st%%|*}; detail=${st#*|}
  [ -z "$st" ] && { state="missing"; detail="not created"; }
  if [ "$state" = "running" ]; then cls=ok; else cls=bad; all_ok=0; fi
  svc_rows+="<div class=row><span class='dot $cls'></span><b>$s</b><span class=muted>$(echo "$detail" | esc)</span></div>"
done

# --- Relay -------------------------------------------------------------------
sc() { docker compose exec -T strfry /app/strfry --config=/etc/strfry.conf scan --count "$1" 2>/dev/null | tail -1; }
ev_all=$(sc '{}'); ev_app=$(sc '{"kinds":[30078]}'); ev_del=$(sc '{"kinds":[5]}')
authors=$(docker compose exec -T strfry /app/strfry --config=/etc/strfry.conf scan '{}' 2>/dev/null \
  | grep -o '"pubkey":"[0-9a-f]*"' | sort -u | wc -l)
db_size=$(du -sb data/strfry-db 2>/dev/null | cut -f1)
allowed=$(sed 's/#.*//; s/[[:space:]]//g' policy/pubkeys.txt 2>/dev/null | grep -cE '^[0-9a-f]{64}$')
kinds=$(sed 's/#.*//; s/[[:space:]]//g' policy/kinds.txt 2>/dev/null | grep -E '^[0-9]+$' | paste -sd, -)

# --- Blossom -----------------------------------------------------------------
blobs=$(find data/blossom/blobs -type f 2>/dev/null | wc -l)
blob_size=$(du -sb data/blossom 2>/dev/null | cut -f1)

# --- System ------------------------------------------------------------------
read -r _ size used avail pct _ < <(df -B1 / | tail -1)
temp=$(awk '{printf "%.1f °C", $1/1000}' /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
load=$(cut -d' ' -f1-3 /proc/loadavg)
mem=$(free -b | awk '/^Mem:/ {printf "%s of %s", $3, $2}')
mem_h=$(echo "$mem" | awk '{print $1, $3}' | { read a b; echo "$(human $a) of $(human $b)"; })
up=$(uptime -p | sed 's/^up //')
throttled=$(vcgencmd get_throttled 2>/dev/null | cut -d= -f2)
[ "$throttled" = "0x0" ] && thr="none" || thr="${throttled:-—}"

# --- Backup ------------------------------------------------------------------
last=$(ls -1t backups/relay-*.jsonl.gz 2>/dev/null | head -1)
if [ -n "$last" ]; then
  b_age=$(( ($(date +%s) - $(stat -c %Y "$last")) / 3600 ))
  b_when=$(date -d @"$(stat -c %Y "$last")" '+%Y-%m-%d %H:%M')
  b_count=$(ls -1 backups/relay-*.jsonl.gz 2>/dev/null | wc -l)
  b_size=$(du -cb backups/ 2>/dev/null | tail -1 | cut -f1)
  [ "$b_age" -le 26 ] && b_cls=ok || { b_cls=bad; all_ok=0; }
else
  b_when="never"; b_age="—"; b_count=0; b_size=0; b_cls=bad; all_ok=0
fi

# --- Tailscale ---------------------------------------------------------------
ts_ip=$(tailscale ip -4 2>/dev/null | head -1)
ts_state=$(tailscale status --self --peers=false 2>/dev/null | head -1 | awk '{print $NF}')
[ -n "$ts_ip" ] && ts_cls=ok || ts_cls=bad

[ "$all_ok" = 1 ] && head_cls=ok && head_txt="All systems running" || { head_cls=bad; head_txt="Needs attention"; }
now=$(date '+%Y-%m-%d %H:%M:%S %Z')
lan=$(hostname -I | awk '{print $1}')

cat > "$TMP" <<HTML
<!doctype html>
<html lang="en"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="refresh" content="60">
<title>beand server</title>
<style>
:root{--bg:#17171a;--card:#232327;--line:#3f3f43;--text:#f2f2f2;--muted:#9a9aa1;--ok:#1d9e75;--bad:#e5484d;--accent:#3ddbc4}
@media (prefers-color-scheme: light){:root{--bg:#f4f1ea;--card:#fff;--line:#ddd8ce;--text:#1d1d1f;--muted:#6b6b70;--ok:#15795a;--bad:#c8343a;--accent:#14917f}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--text);font:15px/1.45 system-ui,-apple-system,Segoe UI,Roboto,sans-serif}
main{max-width:860px;margin:0 auto;padding:20px 16px 40px}
h1{font-size:22px;margin:0 0 4px}.sub{color:var(--muted);font-size:13px;margin-bottom:18px}
.banner{display:flex;align-items:center;gap:10px;background:var(--card);border-radius:16px;padding:14px 16px;margin-bottom:14px;font-weight:600}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(250px,1fr));gap:14px}
.card{background:var(--card);border-radius:16px;padding:14px 16px}
.card h2{font-size:11px;letter-spacing:.9px;text-transform:uppercase;color:var(--muted);margin:0 0 10px}
.row{display:flex;align-items:center;gap:8px;padding:5px 0;border-top:1px solid var(--line)}.row:first-of-type{border-top:0}
.row b{font-weight:600}.row .muted,.kv span{color:var(--muted);margin-left:auto;font-size:13px;text-align:right}
.kv{display:flex;gap:12px;padding:5px 0;border-top:1px solid var(--line)}.kv:first-of-type{border-top:0}
.kv b{font-weight:600;margin-left:auto;font-variant-numeric:tabular-nums}
.dot{width:9px;height:9px;border-radius:50%;flex:none}.dot.ok{background:var(--ok)}.dot.bad{background:var(--bad)}
.bar{height:6px;border-radius:3px;background:var(--line);overflow:hidden;margin:8px 0 2px}.bar i{display:block;height:100%;background:var(--accent)}
code{font-size:12px;color:var(--muted);word-break:break-all;text-align:right}
</style></head><body><main>
<h1>beand server</h1>
<div class=sub>Private Nostr relay + Blossom for bean'd · updated $now · refreshes every minute</div>
<div class=banner><span class='dot $head_cls'></span>$head_txt</div>
<div class=grid>
<section class=card><h2>Services</h2>$svc_rows</section>
<section class=card><h2>Relay (strfry)</h2>
<div class=kv>Events<b>${ev_all:-—}</b></div>
<div class=kv>App data (kind 30078)<b>${ev_app:-—}</b></div>
<div class=kv>Deletions (kind 5)<b>${ev_del:-—}</b></div>
<div class=kv>Keys with data<b>$authors</b></div>
<div class=kv>Allowed keys<b>$allowed</b></div>
<div class=kv>Allowed kinds<b>$kinds</b></div>
<div class=kv>Database<b>$(human "$db_size")</b></div>
</section>
<section class=card><h2>Blossom</h2>
<div class=kv>Files<b>$blobs</b></div>
<div class=kv>Storage used<b>$(human "$blob_size")</b></div>
<div class=kv>Max file size<b>25 MB</b></div>
</section>
<section class=card><h2>Backup</h2>
<div class=row><span class='dot $b_cls'></span><b>Last run</b><span class=muted>$b_when</span></div>
<div class=kv>Age<b>$b_age h</b></div>
<div class=kv>Kept copies<b>$b_count</b></div>
<div class=kv>Backup size<b>$(human "$b_size")</b></div>
<div class=kv>Off-site copy<b>not set up</b></div>
</section>
<section class=card><h2>SSD</h2>
<div class=bar><i style="width:$pct"></i></div>
<div class=kv>Used<b>$(human "$used") of $(human "$size") ($pct)</b></div>
<div class=kv>Free<b>$(human "$avail")</b></div>
</section>
<section class=card><h2>System</h2>
<div class=kv>Uptime<b>$up</b></div>
<div class=kv>CPU temperature<b>${temp:-—}</b></div>
<div class=kv>Load (1/5/15 min)<b>$load</b></div>
<div class=kv>Memory<b>$mem_h</b></div>
<div class=kv>Power/heat throttling<b>$thr</b></div>
</section>
<section class=card><h2>Network</h2>
<div class=row><span class='dot $ts_cls'></span><b>Tailscale</b><span class=muted>${ts_ip:-offline}</span></div>
<div class=kv>LAN<b>$lan</b></div>
<div class=kv>Relay<b><code>ws://$lan:7777</code></b></div>
<div class=kv>Blossom<b><code>http://$lan:3000</code></b></div>
</section>
</div></main></body></html>
HTML
chmod 644 "$TMP"
mv -f "$TMP" "$OUT/index.html"
