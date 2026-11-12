#!/system/bin/sh
# SMB Media Mount for Xiaomi Jaws
# Mounts the SMB share configured in conf/rclone.conf at
# /storage/emulated/0/NetShare via rclone mount2. Uses only the standard
# FUSE API; it does not modify boot, kernel, partitions or ADB settings.
# Uninstall restores the original state.

MODDIR=${0%/*}

BIN="$MODDIR/bin/rclone"
CONF="$MODDIR/conf/rclone.conf"
MP="/storage/emulated/0/NetShare"
LOGDIR="$MODDIR/logs"
LOG="$LOGDIR/mount.log"
MODULE_LOG="$LOGDIR/module.log"

mkdir -p "$LOGDIR" || exit 1

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$MODULE_LOG"
}

# Wait for Android to finish booting (up to 300 s)
i=0
while [ "$(getprop sys.boot_completed)" != "1" ]; do
    i=$((i + 1))
    if [ "$i" -gt 300 ]; then
        log "ERROR: sys.boot_completed not set, giving up"
        exit 1
    fi
    sleep 1
done

# Idempotent: do nothing if the mount is already in place
if grep -q " $MP " /proc/mounts; then
    log "already mounted, nothing to do"
    exit 0
fi

[ -x "$BIN" ] || { log "ERROR: $BIN not found or not executable"; exit 1; }
[ -f "$CONF" ] || { log "ERROR: $CONF not found, see conf/rclone.conf.example"; exit 1; }

# The NAS address comes from the rclone config, not from this script
HOST=$(sed -n 's/^host *= *//p' "$CONF" | head -n 1)
[ -n "$HOST" ] || { log "ERROR: no host in $CONF"; exit 1; }

# Wait until the NAS answers ping (up to 180 s).
# Do not mount with an unreachable server: mount2 would start a daemon
# without a working share and the mountpoint would stay empty.
i=0
until ping -c 1 -w 2 "$HOST" > /dev/null 2>&1; do
    i=$((i + 1))
    if [ "$i" -gt 90 ]; then
        log "ERROR: NAS $HOST unreachable, giving up"
        exit 1
    fi
    sleep 2
done

# The emulated storage FUSE is recreated by MediaProvider shortly after
# boot_completed; a mount made into the early instance is silently
# destroyed with it. Wait until the FUSE device id of /storage/emulated
# stops changing before mounting (grace + two identical samples 15 s
# apart, bounded at 180 s).
i=0
until grep -q " /storage/emulated " /proc/mounts; do
    i=$((i + 1))
    if [ "$i" -gt 60 ]; then
        log "ERROR: emulated storage FUSE not present, giving up"
        exit 1
    fi
    sleep 2
done
sleep 30
prev=$(grep " /storage/emulated " /proc/self/mountinfo | head -n 1 | cut -d ' ' -f 3)
i=0
until [ "$(grep " /storage/emulated " /proc/self/mountinfo | head -n 1 | cut -d ' ' -f 3)" = "$prev" ]; do
    i=$((i + 1))
    if [ "$i" -gt 12 ]; then
        log "ERROR: emulated storage FUSE keeps changing, giving up"
        exit 1
    fi
    prev=$(grep " /storage/emulated " /proc/self/mountinfo | head -n 1 | cut -d ' ' -f 3)
    sleep 15
done

# Mount, verify, re-check after 30 s, retry once if the mount was lost.
attempt=0
while [ "$attempt" -lt 3 ]; do
    attempt=$((attempt + 1))

    # Kill a stale daemon from a previous attempt, if any. The daemon
    # process name is "rclone" (the module binary); other rclone builds
    # on this TV run as "rclone-min" and are not affected.
    killall rclone 2>/dev/null
    sleep 1

    mkdir -p "$MP" || { log "ERROR: cannot create mountpoint $MP"; exit 1; }

    export RCLONE_CONFIG="$CONF"
    "$BIN" mount2 smb-tv:media "$MP" \
        --allow-other \
        --dir-perms 0777 \
        --file-perms 0666 \
        --daemon \
        --log-file "$LOG"

    # rclone mount2 does not support --pid-file, so identify the daemon
    # process by name where a pid is needed.

    # Verify the result instead of assuming success
    ok=0
    i=0
    while [ "$i" -lt 15 ]; do
        sleep 1
        if grep -q " $MP " /proc/mounts && ls "$MP" > /dev/null 2>&1; then
            ok=1
            break
        fi
        i=$((i + 1))
    done

    if [ "$ok" != "1" ]; then
        log "attempt $attempt: mount verification failed, see $LOG"
        continue
    fi

    # Re-check after 30 s: if the storage FUSE was replaced right after
    # our mount, the mount is gone again and needs one more attempt.
    sleep 30
    if grep -q " $MP " /proc/mounts && ls "$MP" > /dev/null 2>&1; then
        log "OK: smb-tv:media mounted at $MP, stable (pid $(pidof rclone 2>/dev/null))"
        exit 0
    fi
    log "attempt $attempt: mount lost after storage settle, retrying"
done

log "ERROR: mount did not stabilize after 3 attempts, see $LOG"
exit 1
