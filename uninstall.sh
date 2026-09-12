#!/system/bin/sh
# FAACC uninstall.sh : dipanggil Magisk/KernelSU saat module dihapus.
# Hanya bersihkan jejak FAACC. JANGAN sentuh data aplikasi lain.

# Hentikan service yang mungkin jalan
pkill -f "faacc.*daemon" 2>/dev/null
pkill -f "service.sh.*faacc" 2>/dev/null

# Hapus symlink / binary yang mungkin dibuat manual (bukan overlay)
rm -f /data/adb/service.d/faacc_service.sh 2>/dev/null

# NOTE: sengaja TIDAK menghapus /sdcard/faacc-log dan /data/adb/faacc
# agar log & config user tetap ada sebagai arsip.
# Hapus manual jika mau bersih total:
#   rm -rf /sdcard/faacc-log /data/adb/faacc

exit 0
