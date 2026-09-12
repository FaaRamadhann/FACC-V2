#!/system/bin/sh

# ============================================================
# Android Root - Cache Cleaner
# Clear app cache without pm clear
# ============================================================

echo "========================================"
echo "      ANDROID ROOT CACHE CLEANER"
echo "========================================"

# Check root
if [ "$(id -u)" != "0" ]; then
    echo "[!] Script harus dijalankan sebagai root."
    echo "[!] Jalankan: su -c sh $0"
    exit 1
fi

TOTAL=0
FAILED=0

clean_dir() {
    DIR="$1"

    if [ -d "$DIR" ]; then
        find "$DIR" -mindepth 1 -delete 2>/dev/null

        if [ $? -eq 0 ]; then
            echo "[V] $DIR"
            TOTAL=$((TOTAL + 1))
        else
            echo "[!] Failed: $DIR"
            FAILED=$((FAILED + 1))
        fi
    fi
}

echo
echo "[*] Cleaning internal app cache..."
echo

# Android modern
for APP in /data/user/0/*; do
    [ -d "$APP" ] || continue

    PKG="${APP##*/}"

    clean_dir "$APP/cache"
    clean_dir "$APP/code_cache"
done

# Legacy /data/data symlink/path
echo
echo "[*] Cleaning /data/data cache..."
echo

for APP in /data/data/*; do
    [ -d "$APP" ] || continue

    clean_dir "$APP/cache"
    clean_dir "$APP/code_cache"
done

# External Android/data cache
echo
echo "[*] Cleaning external app cache..."
echo

if [ -d "/sdcard/Android/data" ]; then
    for APP in /sdcard/Android/data/*; do
        [ -d "$APP" ] || continue

        clean_dir "$APP/cache"
    done
fi

echo
echo "========================================"
echo "             CLEAN COMPLETE"
echo "========================================"
echo "[V] Cleaned : $TOTAL directories"
echo "[!] Failed  : $FAILED directories"
echo "========================================"
