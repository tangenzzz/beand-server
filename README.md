# beand-server

A private **Nostr relay** (strfry) and a private **Blossom server** for the
multi-device sync of [bean'd](https://github.com/tangenzzz/beand). Built for a
Raspberry Pi 4 running Raspberry Pi OS Lite (64-bit) from a USB SSD; all
services run with Docker Compose.

**Role:** this is a server you run *for yourself*, not a relay built into
bean'd for everyone. The app uses public relays by default and lets you add
your own relay and Blossom server as an option. This repo is the recipe for
that box.

| Service | Port | Image (pinned by digest)               | Data              |
|---------|------|----------------------------------------|-------------------|
| strfry  | 7777 | `ghcr.io/hoytech/strfry` (1.1.3)       | `data/strfry-db/` |
| Blossom | 3000 | `ghcr.io/hzrd149/blossom-server:6.4.1` | `data/blossom/`   |
| Status  | 8080 | `busybox:1.37` (httpd)                 | `data/status/`    |

**Access:** LAN (`ws://<pi-ip>:7777`, `http://<pi-ip>:3000`) and your
Tailscale tailnet (`ws://beand:7777`). Nothing is forwarded on the router.

**Who may do what:**
- *Write (relay):* only pubkeys listed in `policy/pubkeys.txt` and only the
  kinds in `policy/kinds.txt` (30078, 5), enforced by
  `strfry/write-policy.sh`. Changes to both lists apply immediately, no
  restart needed.
- *Upload/delete (Blossom):* only pubkeys from `policy/pubkeys.txt`
  (`upload.requirePubkeyInRule`), max. 25 MB per file; users can only delete
  their own blobs.
- *Read:* currently restricted only by the network (LAN/tailnet). strfry can
  restrict reads to the owner via NIP-42 (`relay.auth.restrictedReadKinds` +
  `serviceUrl`); enable that once the app speaks NIP-42.
- strfry handles by itself: NIP-09 (kind 5 deletes your own events), NIP-40
  (expired events are rejected/removed), NIP-77 (Negentropy).

Pi specific: `dbParams.mapsize` is 64 GB instead of 10 TB (otherwise
`mdb_env_open: Out of memory`, the Pi 4 has only 512 GB of address space).

## Setup

1. Raspberry Pi OS Lite (64-bit) on an SSD (or SD card + `rpi-clone` to the
   SSD). First-boot configuration: `provision/user-data` (cloud-init: user
   `beand`, SSH keys only). Put your own public key in it first. Fallback if
   cloud-init does not apply: `ssh` file and `userconf.txt` on `bootfs`.
2. Harden SSH: `/etc/ssh/sshd_config.d/10-beand.conf` with
   `PasswordAuthentication no`, `KbdInteractiveAuthentication no`,
   `PermitRootLogin no`.
3. Docker Engine + Compose plugin from the official Docker repo
   (`download.docker.com/linux/debian`, suite `trixie`); add the user to the
   `docker` group.
4. Tailscale from `pkgs.tailscale.com` (trixie),
   `sudo tailscale up --hostname=beand`.
5. Clone this repo to `~/beand-server`, then:
   ```sh
   cp policy/pubkeys.example.txt policy/pubkeys.txt   # add your hex pubkeys
   ./scripts/render-config.sh                         # writes blossom/config.yml
   mkdir -p data/strfry-db data/blossom
   docker compose up -d
   ```
6. Backup cron (daily at 03:30):
   `30 3 * * * $HOME/beand-server/scripts/backup.sh >> $HOME/beand-server/backups/backup.log 2>&1`

## Operation

**Status page:** `http://<pi-ip>:8080` (or `http://beand:8080` via
Tailscale). `scripts/status.sh` regenerates it every minute via cron
(`* * * * * $HOME/beand-server/scripts/status.sh >/dev/null 2>&1`): services,
events per kind, Blossom files, SSD, temperature, load, memory, throttling,
last backup (red after 26 h), Tailscale. Follows the system light/dark theme.

```sh
docker compose ps                     # status
docker compose logs -f --tail 50      # logs
./scripts/render-config.sh && docker compose up -d   # after changing pubkeys (Blossom)
```

**Updates:** put the new digest/tag into `docker-compose.yml` (official repos
only), `docker compose pull && docker compose up -d`, check the logs.

## Backup and restore

`scripts/backup.sh` writes to `backups/`: `relay-*.jsonl.gz` (all events,
`strfry export`) and `blossom-*.tar.gz` (SQLite + blobs); keeps 14 copies.
Pull an off-site copy from another machine, e.g.:
`rsync -a beand@beand:beand-server/backups/ ~/beand-backups/`

Restore:
```sh
zcat backups/relay-<date>.jsonl.gz | docker compose exec -T strfry /app/strfry --config=/etc/strfry.conf import
docker compose stop blossom && rm -rf data/blossom && tar -C data -xzf backups/blossom-<date>.tar.gz && docker compose start blossom
```

## Acceptance tests

Relay (`nak`, test key a = whitelisted, b = unknown):
kind 30078 with a → OK · with b → `blocked: pubkey not allowed` ·
kind 1 with a → `blocked: kind 1 not allowed` · same `d` twice → only the
newest version · kind 5 deletes your own event · past `expiration` →
`invalid: event expired` · an event expiring in 6 s is deleted after expiry
in the 9 s sweep (strfry keeps the NEWEST event of the DB until another one
arrives, intentional in strfry) · after a Pi reboot both services and
Tailscale are back, data intact · NIP-11 reports NIPs 1, 2, 4, 9, 11, 28, 40,
45, 59, 70, 77.

Blossom: upload with a → OK, download by hash identical · upload with b → 401
`Pubkey not authorized` · no auth → 401 · 30 MB → 413 · delete by b → 403,
by a → OK.

Note: clocks must be right. Auth and `expiration` checks depend on time (the
Pi syncs via NTP).

## License

See [LICENSE](LICENSE).
