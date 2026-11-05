#!/system/bin/sh
# Magisk late_start service (/data/adb/service.d): cast housekeeping (docs/58).
# Limit the vendor Wi-Fi Display offer to this phone's encoder, keep the vendor's
# secondary-display launcher from covering the TV before the Linux desktop takes
# it (restore: pm enable --user 0 <component>), and start the reconnect watcher.
#
# Which component that launcher is depends on the vendor, so it is not written in here: the
# SECONDARY_HOME query below is the authority, and every component it offers is turned off.
# /data/adb/rungic-wfd/cast-launchers narrows that on a phone where the query also answers with
# something that has to stay on, one component per line (docs/123).
LAUNCHERS=
[ ! -f /data/adb/rungic-wfd/cast-launchers ] || LAUNCHERS=$(cat /data/adb/rungic-wfd/cast-launchers)
until [ "$(getprop sys.boot_completed)" = 1 ]; do sleep 5; done
# Recovery is shared; codec/SELinux/launcher workarounds require a verified adapter.
nohup /data/adb/rungic-wfd/rungic-cast watch </dev/null >>/data/adb/rungic-wfd/recovery.log 2>&1 &
# One capability-checked implementation owns both the boot clamp and user mode offers.
/data/adb/rungic-wfd/rungic-cast configure auto > /data/adb/rungic-wfd/wfd-config.log 2>&1
case "$(/data/adb/rungic-wfd/rungic-cast adapter)" in
    *'"legacy_qualcomm":true'*) ;;
    *) exit 0 ;;
esac
offered=$(cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.SECONDARY_HOME)
# No list given: take what the query itself answers. The vendor only changes the package prefix
# (Motorola's com.motorola.launcher3, ColorOS' com.android.launcher, both ...SecondaryDisplayLauncher).
[ -n "$LAUNCHERS" ] || LAUNCHERS=$(printf '%s\n' "$offered" |
    sed -n 's/^ *\([A-Za-z0-9_.]*\/[A-Za-z0-9_.$]*\)$/\1/p')
for launcher in $LAUNCHERS; do
    # Our own cast screen answers that query on some builds; disabling it leaves nothing to show.
    case "$launcher" in com.rungic.*) continue;; esac
    printf '%s\n' "$offered" | grep -q "$launcher" || continue
    pm disable --user 0 "$launcher" > /dev/null
done
nohup /data/adb/rungic-wfd/rungic-cast-watch < /dev/null > /dev/null 2>&1 &
