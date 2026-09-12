# Faa App Cache Cleaner (FACC) V2

[![Magisk](https://img.shields.io/badge/Magisk-Module-00af9c)](https://github.com/topjohnwu/Magisk) [![KernelSU](https://img.shields.io/badge/KernelSU-Module-323136)](https://github.com/tiann/KernelSU) [![APatch](https://img.shields.io/badge/APatch-Module-334d83)](https://github.com/apatch/apatch) [![License](https://img.shields.io/github/license/FaaRamadhann/FACC-V2)](LICENSE)

---

## Apa itu FACC V2?

Modul **Magisk / KernelSU / APatch** untuk membersihkan **cache aplikasi dengan aman** — tanpa `pm clear`, tanpa hapus app data, hanya isi direktori `cache/`. Punya CLI (`facc`), auto-clean terjadwal, log lengkap, WebUI, dan **aplikasi manager bawaan** (`com.faa.facc`) yang dipasang otomatis saat instalasi module.

## Fitur

- **Aman** — tiap target path divalidasi, gagal validasi = abort. `code_cache`/`files`/data lain tidak pernah disentuh
- **CLI `facc`** — menu interaktif + argumen (`--scan`, `--clean`, `--status`, `--logs`, `--version`) + output `--json` buat WebUI/scripting
- **FACC Manager** — aplikasi Android (Light Blue Sea): dashboard cache, daftar aplikasi (search/sort/filter), detail per aplikasi, cleaning progress, settings (tema, scanner, cleaner)
- **Auto-clean terjadwal** — service boot, config `AUTO_CLEAN` / `INTERVAL_MINUTES`
- **Logging** — `/sdcard/facc-log/` format `[TIME] [LEVEL] MESSAGE` + rotasi arsip
- **WebUI** — dashboard, scan/clean per aplikasi, log viewer, config scheduler (via exec bridge `ksu`/`koush`/`kernelsu`/`mmrl`)
- **`zip.py`** untuk mem-packing modul jadi `.zip` (anti-bug backslash `\`)

## Persyaratan

- **Android:** 7.0+ (API 24+)
- **Root:** Magisk / KernelSU / APatch

> Butuh WebUI? Buka module dari aplikasi **MMRL** atau **WebUI Next** — Magisk official manager tidak mendukung WebUI.

---

## Cara Install

Ada dua cara: **via PC (Windows/Linux)** atau **via Termux di HP**.

### A. Via PC (Windows / Linux) — pakai `adb push`

**Langkah 0 — Siapkan (clone + build zip):**

Prasyarat: sudah ada `git` dan `python 3` (versi apa pun) di PC.

```
# 1. Clone repo ini
git clone https://github.com/FaaRamadhann/FACC-V2.git
cd FACC-V2

# 2. Pack jadi zip (manager.apk harus sudah ada di root, lihat bawah)
python zip.py
```

Perintah `python zip.py` menghasilkan file:

```
build/FACC2-v1.0.0.zip
```

**Langkah 1 — Hubungkan HP ke PC:**

Aktifkan **USB Debugging** di HP (Developer Options), lalu colok USB.

```
# Cek HP terdeteksi
adb devices
# Harus muncul status "device"
```

**Langkah 2 — Push zip ke HP:**

```
adb push build/FACC2-v1.0.0.zip /sdcard/
```

**Langkah 3 — Install lewat manager root (dari HP):**

Buka aplikasi **Magisk / KernelSU / APatch / MMRL** → **Modul** → **Install dari penyimpanan** → pilih `FACC2-v1.0.0.zip`.

Atau via terminal/shell (root):

```
# masuk shell adb
adb shell
# lalu jalankan sebagai root
su -c 'magisk --install-module /sdcard/FACC2-v1.0.0.zip'
```

**Langkah 4 — Reboot**, lalu cek:

```
su -c 'facc --status'
```

> Saat instalasi module, **FACC Manager** (`com.faa.facc`) ikut dipasang otomatis.

---

### B. Via Termux (di HP, tanpa PC)

Prasyarat: sudah ada **Termux** dan akses **root** (`su`).

**Langkah 1 — Install git & clone:**

```
pkg install -y git python
git clone https://github.com/FaaRamadhann/FACC-V2.git
cd FACC-V2
```

**Langkah 2 — Build zip:**

```
python zip.py
```

**Langkah 3 — Pindahkan zip ke penyimpanan (agar bisa dipilih manager):**

```
cp build/FACC2-v1.0.0.zip /sdcard/
```

**Langkah 4 — Install via manager root:**

Buka aplikasi **Magisk / KernelSU / APatch / MMRL** → **Modul** → **Install dari penyimpanan** → pilih zip.

Atau lewat Termux dengan root:

```
su -c 'magisk --install-module /sdcard/FACC2-v1.0.0.zip'
```

**Langkah 5 — Reboot**, lalu cek:

```
su -c 'facc --status'
```

---

## Cara Pakai

```sh
su -c facc                              # menu interaktif
su -c "facc --scan"                     # pindai saja
su -c "facc --clean"                    # bersihkan semua
su -c "facc --clean com.android.chrome" # satu aplikasi
su -c "facc --status --json"            # untuk WebUI / scripting
su -c "facc --logs --lines 100"
```

Config scheduler — tanpa edit manual, via CLI:

```sh
su -c "facc --autoclean 60"  # atau: facc -ac 60 (1 jam)
su -c "facc -ac 120"         # 2 jam (batas: 5-1440 menit = maks 24 jam)
su -c "facc --acon"          # aktifkan auto-clean
su -c "facc --acoof"         # matikan auto-clean
su -c "facc --acstatus"      # status on/off + interval
su -c "facc --lclean"        # waktu cleanup terakhir
su -c "facc --clogs"         # reset/hapus log
```

(Masih bisa edit manual: `/data/adb/facc2/facc.conf` — scheduler baca ulang tiap menit.)

## Aplikasi Manager

Source di `manager/` — project Android **tanpa Gradle / Android Studio**, build langsung pakai JDK + SDK build-tools:

```
cd manager
build.bat        # Windows, atau:
python build.py  # butuh Python 3.8+
```

Hasil: `manager/build/manager.apk` (paket `com.faa.facc`). Salin ke root sebagai `manager.apk` agar ikut ter-pack ke zip module:

```
copy manager\build\manager.apk manager.apk
```

> **Backup `manager/debug.keystore`!** Update APK wajib pakai key yang sama.

## Struktur Repo

```
FACC-V2/
├── module.prop            # Metadata modul (id facc2, Faa Ramadhan)
├── customize.sh           # Instalasi: permission + config + log dir + pasang manager.apk
├── uninstall.sh           # Cleanup saat module dihapus
├── action.sh              # Tombol Action di manager
├── service.sh             # Scheduler auto-clean (jalan saat boot)
├── manager.apk            # FACC Manager siap install (com.faa.facc)
├── zip.py                 # Packing repo jadi .zip
├── LICENSE
├── system/bin/facc        # CLI utama (CLI First)
├── common/                # Engine: core.sh (validate/safe/size/clean/verify)
│                          # + logger.sh — independen dari UI
├── config/facc.conf       # Default config
├── manager/               # Source aplikasi manager (tanpa Gradle)
│                          # AndroidManifest.xml, src/com/faa/facc/*.java,
│                          # res/drawable/icon.png, build.bat, build.py
└── webroot/               # WebUI (HTML/CSS/JS via exec bridge)
```

## Troubleshooting

Masalah | Solusi
`core.sh tidak ditemukan` | Reboot setelah install/update agar overlay aktif
WebUI mock | Buka dari MMRL/WebUI Next, bukan browser
`facc` command not found | Jalankan sebagai root: `su -c facc`
Scheduler tidak jalan | Cek `/data/adb/facc2/facc.conf` (`AUTO_CLEAN=1`) dan log `/sdcard/facc-log/`
Manager gagal update (`signatures do not match`) | Keystore beda — backup `debug.keystore`, update wajib key yang sama

## Lisensi

[MIT License](LICENSE) — © 2026 Faa Ramadhan
