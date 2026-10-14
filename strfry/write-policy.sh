#!/bin/sh
# strfry writePolicy plugin: accepts only events from allowed pubkeys with
# allowed kinds. Protocol: strfry writes one JSON line per event to stdin, the
# plugin answers with one JSON line (docs/plugins.md in the strfry repo).
#
# Runs in the official strfry image (Alpine, BusyBox only), hence awk instead
# of jq. strfry passes the event minified; the keys "id", "pubkey" and "kind"
# appear only once unescaped (text in content/tags is escaped, \" instead
# of ").
#
# The lists are re-read for every event so changes to policy/pubkeys.txt and
# policy/kinds.txt apply without a restart.

PUBKEYS=${BEAND_PUBKEYS_FILE:-/app/policy/pubkeys.txt}
KINDS=${BEAND_KINDS_FILE:-/app/policy/kinds.txt}

exec awk -v pubfile="$PUBKEYS" -v kindfile="$KINDS" '
function load(file, set,    l, n) {
  for (k in set) delete set[k]
  n = 0
  while ((getline l < file) > 0) {
    sub(/#.*/, "", l); gsub(/[ \t\r]/, "", l)
    if (l != "") { set[tolower(l)] = 1; n++ }
  }
  close(file)
  return n
}
function reply(id, action, msg) {
  if (msg == "") printf "{\"id\":\"%s\",\"action\":\"%s\"}\n", id, action
  else printf "{\"id\":\"%s\",\"action\":\"%s\",\"msg\":\"%s\"}\n", id, action, msg
  fflush()
}
{
  id = ""; pk = ""; kind = ""
  if (match($0, /"id":"[0-9a-f]+"/)) id = substr($0, RSTART + 6, RLENGTH - 7)
  if (match($0, /"pubkey":"[0-9a-f]+"/)) pk = substr($0, RSTART + 10, RLENGTH - 11)
  if (match($0, /"kind":[0-9]+/)) kind = substr($0, RSTART + 7, RLENGTH - 7)

  load(pubfile, allowedPk)
  load(kindfile, allowedKind)

  if (length(id) != 64 || length(pk) != 64 || kind == "") {
    reply(id, "reject", "invalid: could not read event"); next
  }
  if (!(pk in allowedPk)) { reply(id, "reject", "blocked: pubkey not allowed on this relay"); next }
  if (!(kind in allowedKind)) { reply(id, "reject", "blocked: kind " kind " not allowed on this relay"); next }
  reply(id, "accept", "")
}
'
