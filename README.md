# SMB Media Mount for Xiaomi Jaws

Magisk module for the Xiaomi "Jaws" Android TV (MiTV-AFKR0, Android 14).
Mounts a Synology SMB share at `/storage/emulated/0/NetShare` via
`rclone mount2`, so TV apps can browse and play files from the NAS.

## How it works

- `service.sh` waits for `sys.boot_completed`, waits until the NAS answers
  ping, waits until the emulated storage FUSE is stable (MediaProvider
  recreates it shortly after boot; a mount made too early is destroyed
  with it), then starts `rclone mount2 ... --daemon` and verifies the
  result: mount present, listing works, and still present after 30 s.
- The NAS address is read from `conf/rclone.conf`, not hardcoded.
- Uses only the standard FUSE API. It does not modify boot, kernel,
  partitions or ADB settings. No dangerous commands.

The bundled `bin/rclone` is a minimal rclone build (v1.76.0) with only the
`local` and `smb` backends plus the `mount`/`mount2` commands, ~20 MB
instead of ~80 MB. The key patch is in `cmd/mount2`: `DirectMount: true`,
which makes go-fuse call `syscall.Mount` itself - Android ships no
`fusermount` helper, so stock rclone mount2 cannot mount there.
See `rclone-min-profile.patch`.

## Install

```sh
adb root
adb push magisk-smb-media-mount-jaws-vX.Y.Z.zip /data/local/tmp/
adb shell magisk --install-module /data/local/tmp/magisk-smb-media-mount-jaws-vX.Y.Z.zip
```

After installing (new install or update), fix permissions - Magisk's
unzip does not preserve them:

```sh
adb shell "M=/data/adb/modules_update/smb-media-mount-jaws; \
  chmod 755 \$M/service.sh \$M/uninstall.sh \$M/bin/rclone"
```

Create the config (never commit the real file):

```sh
adb shell "M=/data/adb/modules_update/smb-media-mount-jaws; \
  cp \$M/conf/rclone.conf.example \$M/conf/rclone.conf"
# edit \$M/conf/rclone.conf: host, user and an obscured password
# (generate with: rclone obscure '<PASSWORD>')
adb shell "chmod 600 /data/adb/modules_update/smb-media-mount-jaws/conf/rclone.conf"
```

Then reboot. The mount appears at `/storage/emulated/0/NetShare` and is
visible to TV apps. Log: `/data/adb/modules/smb-media-mount-jaws/logs/`.

## Uninstall

Remove the module in the Magisk app (or `magisk --remove-module`).
`uninstall.sh` stops the daemon, unmounts and removes the mountpoint.
No other state is modified.

## Building the rclone binary

Go 1.26+, any host:

```sh
git clone --depth 1 --branch v1.76.0 https://github.com/rclone/rclone.git
cd rclone
git apply /path/to/rclone-min-profile.patch
CGO_ENABLED=0 GOOS=linux GOARCH=arm GOARM=7 \
  go build -trimpath -buildvcs=false \
  -ldflags "-s -w -X github.com/rclone/rclone/fs.Version=v1.76.0-min-local-smb-mount2" \
  -o ../bin/rclone .
```

## License

MIT
