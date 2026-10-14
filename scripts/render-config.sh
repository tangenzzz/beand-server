#!/bin/sh
# Writes blossom/config.yml from the template and the pubkeys in
# policy/pubkeys.txt (one hex key per line, # = comment).
# strfry reads policy/pubkeys.txt directly; saving the file is enough there.
set -eu
cd "$(dirname "$0")/.."
[ -f policy/pubkeys.txt ] || { echo "policy/pubkeys.txt is missing (template: policy/pubkeys.example.txt)"; exit 1; }
keys=$(sed 's/#.*//; s/[[:space:]]//g' policy/pubkeys.txt | tr 'A-F' 'a-f' | grep -E '^[0-9a-f]{64}$' || true)
[ -n "$keys" ] || { echo "No valid pubkeys in policy/pubkeys.txt"; exit 1; }
list=$(printf '%s\n' "$keys" | sed 's/^/        - "/; s/$/"/')
awk -v list="$list" '{ if ($0 == "__PUBKEYS__") print list; else print }' blossom/config.template.yml > blossom/config.yml
echo "Wrote blossom/config.yml with $(printf '%s\n' "$keys" | wc -l) pubkey(s)"
