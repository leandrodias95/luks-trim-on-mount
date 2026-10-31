# luks-trim-on-mount

Run `fstrim` on a **LUKS-encrypted data disk** when it is mounted, **at most once
every 24 hours**, with a daily timer as a fallback.

## Why

When a filesystem lives on top of a LUKS-encrypted device, the device-mapper
layer **blocks TRIM (discard) by default**. The SSD never learns which blocks
are free, so its internal garbage collection degrades and write performance
drops over time (and wear increases). A plain `fstrim.timer` also misses a
removable disk that is not mounted at the scheduled time.

This project fixes both problems:

- **On mount:** a drop-in on the disk's `.mount` unit starts the service as soon
  as the disk is mounted, **at any time of the day**.
- **Rate limit:** a stamp file makes it run **at most once per 24 hours**.
- **Fallback:** a daily timer still runs it if the disk stays mounted for days.
- **Retry:** the stamp is written **only on success**, so an interrupted
  `fstrim` (for example, the disk unmounted mid-run) is retried on the next
  mount.

`fstrim` only reports free blocks to the SSD; it never touches file contents,
so it is safe to run at any moment.

## How it works

```
 disk mounted
      │
      ▼
 <mount-unit>.mount  ──Wants──►  trim-luks-mount.service
                                      │
                                      ▼
                         trim-luks-mount.sh <mount-point>
                           ├─ not mounted? exit
                           ├─ last run < 24h? exit
                           └─ fstrim -v <mount-point>
                                └─ on success: write stamp

 trim-luks-mount.timer (daily, fallback) ──► same service
```

Components:

| File | Purpose |
|------|---------|
| `trim-luks-mount.sh` | Idempotent wrapper: checks mount, enforces the 24 h rate limit, runs `fstrim`, writes the stamp on success. |
| `trim-luks-mount.service` | `oneshot` service that calls the script. |
| `trim-luks-mount.timer` | Daily fallback (03:00, `Persistent=true`). |
| `mount-drop-in.conf` | Drop-in for the disk's `.mount` unit (`Wants=trim-luks-mount.service`) so it fires on mount. |

The script keeps its stamp in `/var/lib/trim-luks-mount/last-run`.

## Requirements

- Linux with **systemd**
- `fstrim` (from `util-linux`)
- A LUKS device opened with **`allow-discards`** (otherwise `fstrim` fails and no
  stamp is written; fix the LUKS flag first, see below)

## Enabling TRIM through LUKS (once)

TRIM must be allowed through the encryption layer. Either store the flag in the
LUKS2 header (persistent, works with any unlock path):

```bash
sudo cryptsetup open --allow-discards --persistent /dev/sdXN <mapper-name>
```

or add `discard` to the `/etc/crypttab` entry. Verify:

```bash
cat /sys/block/dm-*/queue/discard_max_bytes   # must be > 0
lsblk --discard
```

## Install

1. Copy the script and units:

   ```bash
   sudo install -m 0755 trim-luks-mount.sh /usr/local/bin/trim-luks-mount.sh
   sudo install -m 0644 trim-luks-mount.service /etc/systemd/system/
   sudo install -m 0644 trim-luks-mount.timer   /etc/systemd/system/
   ```

2. Edit `trim-luks-mount.service` and set your real mount point in both
   `ConditionPathIsMountPoint=` and the script argument (`ExecStart=... <mount-point>`).

3. Create the drop-in on the disk's `.mount` unit. The unit name is derived from
   the mount path, for example:

   | Mount point | `.mount` unit |
   |-------------|---------------|
   | `/run/media/<user>/Data` | `run-media-<user>-Data.mount` |
   | `/mnt/data` | `mnt-data.mount` |

   ```bash
   sudo mkdir -p /etc/systemd/system/run-media-<user>-Data.mount.d
   sudo cp mount-drop-in.conf /etc/systemd/system/run-media-<user>-Data.mount.d/10-trim-luks-mount.conf
   ```

4. Enable:

   ```bash
   sudo systemctl daemon-reload
   sudo systemctl enable --now trim-luks-mount.timer
   ```

5. Test: unmount and mount the disk, then watch:

   ```bash
   journalctl -u trim-luks-mount.service -f
   ```

## Notes

- The trigger relies on the exact `.mount` unit name. If the mount point changes,
  update the drop-in path (the daily timer keeps working as a fallback).
- Do **not** use a `.path` unit with `PathExists=` for this: the condition stays
  true while the disk is mounted and the service is restarted in a loop. The
  `.mount` drop-in is the correct trigger.
- An interrupted `fstrim` is harmless; the next mount retries it.

## Tested on

Ubuntu (base system), on a generic test machine.

## Author

**Leandro** — Product Engineer and founder of **Spartanus Gestão Inteligente**.

## License

MIT. See [LICENSE](LICENSE).
