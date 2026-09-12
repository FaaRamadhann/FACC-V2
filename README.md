# Faa Agresive App Cache Cleaner (FAACC)

[![Magisk](https://img.shields.io/badge/Magisk-Module-00af9c)](https://github.com/topjohnwu/Magisk) [![KernelSU](https://img.shields.io/badge/KernelSU-Module-323136)](https://github.com/tiann/KernelSU) [![APatch](https://img.shields.io/badge/APatch-Module-334d83)](https://github.com/apatch/apatch) [![License](https://img.shields.io/github/license/FaaRamadhann/FAACC)](LICENSE)

> **FAACC adalah versi AGRESIF dari [Magisk-FACC](https://github.com/FaaRamadhann/Magisk-FACC).**
> Kalau butuh yang aman/konservatif (cache internal saja), pakai Magisk-FACC.

---

## Apa itu FAACC?

Modul **Magisk / KernelSU / APatch** untuk membersihkan **cache aplikasi secara agresif** — tanpa `pm clear`, tanpa hapus app data. Punya CLI (`faacc`), auto-clean terjadwal, log lengkap, WebUI, dan **aplikasi manager bawaan** (`com.faa.faacc`) yang dipasang otomatis saat instalasi module.

### Yang dibersihkan (3 lokasi)

| Lokasi | Contoh | Keterangan |
|---|---|---|
| Cache internal | `/data/data/<pkg>/cache`, `/data/user/<N>/<pkg>/cache` | Cache aplikasi standar |
| Code cache | `/data/data/<pkg>/code_cache`, `/data/user/<N>/<pkg>/code_cache` | Hasil kompilasi Dalvik/ART — app akan recompile ulang setelah dibersihkan |
| Cache eksternal | `/sdcard/Android/data/<pkg>/cache` | Cache di shared storage (game, medsos, browser) |

## Fitur

- **Agresif tapi tervalidasi** — tiap target path divalidasi pola milik package-nya sendiri, gagal validasi = abort. Data aplikasi tidak pernah disentuh
- **CLI `faacc`** — menu interaktif + argumen (`--scan`, `--clean`, `--status`, `--logs`, `--version`) + output `--json` buat WebUI/scripting, dengan rincian `internal_bytes` / `code_cache_bytes` / `external_bytes`
- **FAACC Manager** — aplikasi Android (Light Blue Sea): dashboard cache, daftar aplikasi (search/sort/filter), detail per aplikasi, cleaning progress, settings
- **Auto-clean terjadwal** — service boot, config `AUTO_CLEAN` / `INTERVAL_MINUTES`
- **Logging** — `/sdcard/faacc-log/` format `[TIME] [LEVEL] MESSAGE` + rotasi arsip
- **WebUI** — dashboard + rincian Internal / Code cache / Eksternal, scan/clean per aplikasi, log viewer, config scheduler (via exec bridge `ksu`/`koush`/`kernelsu`/`mmrl`)
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
git clone https://github.com/FaaRamadhann/FAACC.git
cd FAACC

# 2. Pack jadi zip (manager.apk harus sudah ada di root, lihat bawah)
python zip.py
```

Perintah `python zip.py` menghasilkan file:

```
build/FAACC-v1.0.0.zip
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
adb push build/FAACC-v1.0.0.zip /sdcard/
```

**Langkah 3 — Install lewat manager root (dari HP):**

Buka aplikasi **Magisk / KernelSU / APatch / MMRL** → **Modul** → **Install dari penyimpanan** → pilih `FAACC-v1.0.0.zip`.

Atau via terminal/shell (root):

```
# masuk shell adb
adb shell
# lalu jalankan sebagai root
su -c 'magisk --install-module /sdcard/FAACC-v1.0.0.zip'
```

**Langkah 4 — Reboot**, lalu cek:

```
su -c 'faacc --status'
```

> Saat instalasi module, **FAACC Manager** (`com.faa.faacc`) ikut dipasang otomatis.

---

### B. Via Termux (di HP, tanpa PC)

Prasyarat: sudah ada **Termux** dan akses **root** (`su`).

**Langkah 1 — Install git & clone:**

```
pkg install -y git python
git clone https://github.com/FaaRamadhann/FAACC.git
cd FAACC
```

**Langkah 2 — Build zip:**

```
python zip.py
```

**Langkah 3 — Pindahkan zip ke penyimpanan (agar bisa dipilih manager):**

```
cp build/FAACC-v1.0.0.zip /sdcard/
```

**Langkah 4 — Install via manager root:**

Buka aplikasi **Magisk / KernelSU / APatch / MMRL** → **Modul** → **Install dari penyimpanan** → pilih zip.

Atau lewat Termux dengan root:

```
su -c 'magisk --install-module /sdcard/FAACC-v1.0.0.zip'
```

**Langkah 5 — Reboot**, lalu cek:

```
su -c 'faacc --status'
```

---

## Cara Pakai

```sh
su -c faacc                              # menu interaktif
su -c "faacc --scan"                     # pindai saja (dengan rincian jenis)
su -c "faacc --clean"                    # bersihkan semua (agresif)
su -c "faacc --clean com.android.chrome" # satu aplikasi
su -c "faacc --status --json"            # untuk WebUI / scripting
su -c "faacc --logs --lines 100"
```

Config scheduler — tanpa edit manual, via CLI:

```sh
su -c "faacc --autoclean 60"  # atau: faacc -ac 60 (1 jam)
su -c "faacc -ac 120"         # 2 jam (batas: 5-1440 menit = maks 24 jam)
su -c "faacc --acon"          # aktifkan auto-clean
su -c "faacc --acoff"         # matikan auto-clean
su -c "faacc --acstatus"      # status on/off + interval
su -c "faacc --lclean"        # waktu cleanup terakhir
su -c "faacc --clogs"         # reset/hapus log
```

(Masih bisa edit manual: `/data/adb/faacc/faacc.conf` — scheduler baca ulang tiap menit.)

## Aplikasi Manager

Source di `manager/` — project Android **tanpa Gradle / Android Studio**, build langsung pakai JDK + SDK build-tools:

```
cd manager
build.bat        # Windows, atau:
python build.py  # butuh Python 3.8+
```

Hasil: `manager/build/manager.apk` (paket `com.faa.faacc`, key alias `faacc`). Salin ke root sebagai `manager.apk` agar ikut ter-pack ke zip module:

```
copy manager\build\manager.apk manager.apk
```

> **Backup `manager/debug.keystore`!** Update APK wajib pakai key yang sama.

## Struktur Repo

```
FAACC/
├── module.prop            # Metadata modul (id faacc, Faa Ramadhan)
├── customize.sh           # Instalasi: permission + config + log dir + pasang manager.apk
├── uninstall.sh           # Cleanup saat module dihapus
├── action.sh              # Tombol Action di manager
├── service.sh             # Scheduler auto-clean (jalan saat boot)
├── manager.apk            # FAACC Manager siap install (com.faa.faacc)
├── cc.sh                  # Script referensi user (tidak ikut di-pack)
├── zip.py                 # Packing repo jadi .zip
├── LICENSE
├── system/bin/faacc       # CLI utama (CLI First)
├── common/                # Engine: core.sh (validate/safe/size/clean/verify)
│                          # + logger.sh — independen dari UI
├── config/faacc.conf      # Default config
├── manager/               # Source aplikasi manager (tanpa Gradle)
│                          # AndroidManifest.xml, src/com/faa/faacc/*.java,
│                          # res/drawable/icon.png, build.bat, build.py
└── webroot/               # WebUI (HTML/CSS/JS via exec bridge)
```

## Troubleshooting

Masalah | Solusi
`core.sh tidak ditemukan` | Reboot setelah install/update agar overlay aktif
WebUI mock | Buka dari MMRL/WebUI Next, bukan browser
`faacc` command not found | Jalankan sebagai root: `su -c faacc`
Scheduler tidak jalan | Cek `/data/adb/faacc/faacc.conf` (`AUTO_CLEAN=1`) dan log `/sdcard/faacc-log/`
Manager gagal update (`signatures do not match`) | Keystore beda — backup `debug.keystore`, update wajib key yang sama
App lemot setelah clean | Wajar untuk code_cache (recompile) — baca warning di bawah

## Lisensi

[MIT License](LICENSE) — © 2026 Faa Ramadhan

---

## ⚠️ WARNING / CATATAN — BACA DULU SEBELUM PAKAI

> **FAACC itu AGRESIF. Bukan Magisk-FACC.** Pahami risikonya sebelum install.

1. **Code cache ikut dihapus.** Setelah clean, aplikasi akan recompile ulang saat pertama dibuka — buka app pertama kali bisa lebih lambat & hangat. Ini normal, bukan bootloop.
2. **Cache eksternal (`/sdcard/Android/data`) ikut dihapus.** Game/medsos/browser bisa download ulang data cache (map offline, artwork Spotify, dsb). Jangan clean sebelum traveling tanpa kuota.
3. **Auto-clean default AKTIF tiap 30 menit.** Kalau tidak mau, matikan (`faacc --acoff`) atau naikkan interval setelah install.
4. **Jangan pakai bareng cleaner agresif lain** (cc.sh, cleaner MIUI, dsb) dalam waktu bersamaan — hasil dobel dan log susah dibaca.
5. **Package & data penting dikecualikan** (`android`, `com.android.systemui`, `com.android.phone`), dan `pm clear` / hapus data TIDAK PERNAH dilakukan. Tapi kalau ada app yang aneh setelah clean, lapor via GitHub issue.
6. **Backup keystore & config** sebelum update module/APK: `/data/adb/faacc/faacc.conf`, `manager/debug.keystore`.
