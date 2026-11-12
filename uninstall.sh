#!/system/bin/sh
# Restores the original state on module removal:
# stops the rclone daemon, unmounts the FUSE filesystem and removes the
# mountpoint directory. Nothing else was changed by this module.

MODDIR=${0%/*}

MP="/storage/emulated/0/NetShare"

# Stop the daemon by process name. The daemon process name is "rclone"
# (the module binary); other rclone builds on this TV run as "rclone-min".
killall rclone 2>/dev/null
sleep 1
killall -9 rclone 2>/dev/null

# Unmount, retry a few times, then detach as a last resort
i=0
while grep -q " $MP " /proc/mounts; do
    i=$((i + 1))
    if [ "$i" -gt 5 ]; then
        umount -l "$MP" 2>/dev/null
        break
    fi
    umount "$MP" 2>/dev/null
    sleep 1
done

# Remove the mountpoint only if we created it (empty directory)
rmdir "$MP" 2>/dev/null

exit 0
