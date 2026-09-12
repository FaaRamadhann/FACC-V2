#!/system/bin/sh
# action.sh — tombol "Action" di Magisk Manager.
# Membuka menu FAACC. Dijalankan sebagai root oleh manager.
MODDIR=${0%/*}
"$MODDIR/system/bin/faacc" --status
echo ""
echo "Untuk menu penuh, jalankan di terminal: su -c faacc"
