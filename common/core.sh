#!/system/bin/sh
# FAACC core.sh — Cache Cleanup Engine (AGRESIF)
# Prinsip:
#   - Never pm clear
#   - Never delete app data (hanya ISI direktori: cache + code_cache
#     internal, dan cache eksternal Android/data). Struktur dir dipertahankan.
#   - Validate target path (harus milik package yang dimaksud)
#   - Fail-safe (gagal validasi = ABORT, tanpa fallback rm -rf)
#
# Flow: Package -> Find cache -> Validate path -> Check ownership ->
#       Calculate size -> Delete contents -> Verify -> Write log

# Guard double-source
[ -n "$__FAACC_CORE_LOADED" ] && return 0 2>/dev/null
__FAACC_CORE_LOADED=1

# Lokasi script (agar bisa resolve logger saat standalone)
_FAACC_SCRIPT_DIR="$(dirname "$0" 2>/dev/null)"
case "$_FAACC_SCRIPT_DIR" in
  "") _FAACC_SCRIPT_DIR="." ;;
esac
# Cari logger.sh di beberapa lokasi umum
for _d in "$_FAACC_SCRIPT_DIR" "$_FAACC_SCRIPT_DIR/../common" "/data/adb/modules/faacc/common" "/data/adb/modules_update/faacc/common"; do
  if [ -f "$_d/logger.sh" ] && [ -z "$__FAACC_LOGGER_LOADED" ]; then
    # shellcheck source=/dev/null
    . "$_d/logger.sh" 2>/dev/null && __FAACC_LOGGER_LOADED=1 && break
  fi
done
unset _d
# Fallback no-op logger bila file tidak ketemu (misal saat unit test)
if [ -z "$__FAACC_LOGGER_LOADED" ]; then
  faacc_log() { echo "[$1] $2" >&2; }
  faacc_log_info() { :; }; faacc_log_scan() { :; }
  faacc_log_clean() { :; }; faacc_log_warn() { echo "WARN: $*" >&2; }
  faacc_log_error() { echo "ERROR: $*" >&2; }
fi

FAACC_VERSION="${FAACC_VERSION:-1.0.0}"

# Direktori data yang dipindai per user. Owner 0 ada di /data/data.
# Multi-user lain di /data/user/<id>/.
FAACC_DATA_ROOTS_DEFAULT="/data/data /data/user/0"

# ---------------------------------------------------------------
# Environment detection
# ---------------------------------------------------------------
faacc_detect_android() {
  FAACC_SDK="$(getprop ro.build.version.sdk 2>/dev/null)"
  FAACC_RELEASE="$(getprop ro.build.version.release 2>/dev/null)"
  [ -z "$FAACC_SDK" ] && FAACC_SDK="unknown"
  [ -z "$FAACC_RELEASE" ] && FAACC_RELEASE="unknown"
  echo "$FAACC_SDK"
}

faacc_is_root() {
  [ "$(id -u 2>/dev/null)" = "0" ]
}

faacc_require_root() {
  if ! faacc_is_root; then
    echo "FAACC butuh root. Jalankan: su -c faacc" >&2
    faacc_log_error "Root check gagal (uid=$(id -u 2>/dev/null))"
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------
# validate_package(pkg) -> 0 valid, 1 invalid
# Aturan: format java-package + (opsional, jika pm tersedia) package terinstal.
# ---------------------------------------------------------------
validate_package() {
  _pkg="$1"
  [ -z "$_pkg" ] && return 1
  # Tolak karakter berbahaya / path traversal
  case "$_pkg" in
    *"/"*|*" "*|*";"*|*"&"*|*"|"*|*"\$"*|*"\`"*|*"*"*|*"!"*|*"#"*) return 1 ;;
  esac
  # Format: huruf/angka/underscore dipisah titik, min 1 titik, tiap segmen tidak diawali angka
  echo "$_pkg" | grep -Eq '^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$' || return 1
  # Blokir prefix sistem berbahaya yang tidak boleh dibersihkan sembarangan
  case "$_pkg" in
    android|com.android.systemui|com.android.phone) return 1 ;;
  esac
  return 0
}

# Cek apakah package terinstal (best-effort, tidak fatal bila pm tak ada)
faacc_package_installed() {
  _pkg="$1"
  # 1) direktori data ada?
  [ -d "/data/data/$_pkg" ] && return 0
  for _u in /data/user/*; do
    [ -d "$_u/$_pkg" ] && return 0
  done
  # 2) pm path (butuh root/shell)
  if command -v pm >/dev/null 2>&1; then
    pm path "$_pkg" 2>/dev/null | grep -q "^package:" && return 0
  fi
  return 1
  unset _u
}

# ---------------------------------------------------------------
# is_safe_path(pkg, path) -> 0 aman, 1 tidak aman
# Syarat aman (mode AGRESIF FAACC):
#  - path absolut milik package yang dimaksud
#  - path akhir tepat ".../<pkg>/{cache,code_cache}" (internal) atau
#    ".../Android/data/<pkg>/cache" (eksternal). Selain itu = ABORT.
#  - tidak mengandung .. atau link keluar (cek readlink bila ada)
#  - tidak masuk daftar kritis
# ---------------------------------------------------------------
# Samakan prefix storage eksternal ke bentuk kanonis /data/media/0.
# Hasil di variabel global $_NORM (tanpa fork, tanpa echo).
faacc_norm_ext() {
  _NORM="$1"
  case "$_NORM" in
    /sdcard/*) _NORM="/data/media/0/${_NORM#/sdcard/}" ;;
    /storage/emulated/0/*) _NORM="/data/media/0/${_NORM#/storage/emulated/0/}" ;;
    /storage/self/primary/*) _NORM="/data/media/0/${_NORM#/storage/self/primary/}" ;;
  esac
  case "$_NORM" in
    /mnt/user/[0-9]*/primary/*)
      _NORM=$(echo "$_NORM" | sed 's#^/mnt/user/[0-9][0-9]*/primary/#/data/media/0/#')
      ;;
  esac
}

is_safe_path() {
  [ -z "$1" ] && return 1
  validate_package "$1" || return 1
  _faacc_path_ok "$1" "$2"
}

# Inti cek path TANPA validasi ulang pkg (hemat 1 fork grep per kandidat).
# Dipakai loop panas faacc_find_cache_dirs (pkg sudah tervalidasi).
# Input luar (CLI/clean manual) WAJIB lewat is_safe_path.
_faacc_path_ok() {
  _sp_pkg="$1"
  _sp_path="$2"
  [ -z "$_sp_pkg" ] || [ -z "$_sp_path" ] && return 1

  # Harus absolut
  case "$_sp_path" in /*) ;; *) return 1 ;; esac
  # Tolak traversal & karakter aneh
  case "$_sp_path" in *"../"*|*"/.."*|*"*"*|*" "*|*";"*|*"&"*|*"|"*) return 1 ;; esac

  # Normalisasi prefix eksternal -> kanonis (tanpa fork, hasil di $_NORM)
  faacc_norm_ext "$_sp_path"; _sp_path="$_NORM"

  # Daftar path yang TIDAK BOLEH disentuh
  case "$_sp_path" in
    "/"|"/data"|"/data/"|"/data/data"|"/data/data/"|"/data/user"|"/data/user/"| \
    "/sdcard"|"/sdcard/"|"/storage"|"/data/media"|"/data/media/"| \
    "/data/media/0"|"/data/media/0/"|"/data/media/0/Android"| \
    "/data/media/0/Android/data"|"/system"|"/vendor"|"/apex") return 1 ;;
  esac

  # Pola yang diizinkan (exact match, KIND = cache atau code_cache):
  #   /data/data/<pkg>/{cache,code_cache}
  #   /data/user/<N>/<pkg>/{cache,code_cache}
  #   /data/user_de/<N>/<pkg>/{cache,code_cache}
  #   /data/media/0/Android/data/<pkg>/cache   (eksternal, cache saja)
  _ok=1
  for _kind in cache code_cache; do
    [ "$_sp_path" = "/data/data/$_sp_pkg/$_kind" ] && _ok=0
    # shellcheck disable=SC2254
    case "$_sp_path" in
      /data/user/[0-9]*/"$_sp_pkg"/"$_kind"|/data/user_de/[0-9]*/"$_sp_pkg"/"$_kind") _ok=0 ;;
    esac
  done
  unset _kind
  [ "$_sp_path" = "/data/media/0/Android/data/$_sp_pkg/cache" ] && _ok=0
  [ "$_ok" = "0" ] && return 0
  return 1
}

# validate_cache_path(pkg, path): wrapper + pastikan direktori ada & memang direktori
validate_cache_path() {
  _pkg="$1"
  _path="$2"
  is_safe_path "$_pkg" "$_path" || {
    echo "CLEANUP ABORTED - Reason: unsafe target ($_path)" >&2
    return 1
  }
  [ -e "$_path" ] || return 2
  [ -d "$_path" ] || return 1
  return 0
}

# ---------------------------------------------------------------
# faacc_find_cache_dirs(pkg) : cetak SEMUA direktori milik pkg yang boleh
# dibersihkan mode AGRESIF (satu per baris):
#   internal: cache + code_cache (/data/data, /data/user/<N>, /data/user_de/<N>)
#   eksternal: Android/data/<pkg>/cache (/sdcard, /data/media/0)
# ---------------------------------------------------------------
# Emit 1 kandidat (dipakai finder; _found/_seen milik pemanggil).
# Dedup LOGIS tanpa readlink: /data/user/0 == /data/data,
# semua varian /sdcard == /data/media/0.
_faacc_emit_dir() {
  _e_pkg="$1"; _e_c="$2"
  if _faacc_path_ok "$_e_pkg" "$_e_c" && [ -d "$_e_c" ]; then
    faacc_norm_ext "$_e_c"; _e_nk="$_NORM"
    case "$_e_nk" in
      /data/user/0/*) _e_nk="/data/data/${_e_nk#/data/user/0/}" ;;
    esac
    case "$_seen" in
      *"$_e_nk"*) unset _e_pkg _e_c _e_nk; return 0 ;;
    esac
    _seen="$_seen
$_e_nk"
    echo "$_e_c"
    _found=$((_found + 1))
  fi
  unset _e_pkg _e_c _e_nk
}

faacc_find_cache_dirs() {
  _pkg="$1"
  validate_package "$_pkg" || return 1
  _found=0; _seen=""
  for _root in /data/data "/data/user"/* /data/user_de/*; do
    case "$_root" in
      "/data/user/*"|"/data/user_de/*") continue ;;
    esac
    if [ "$_root" = "/data/data" ]; then
      _faacc_emit_dir "$_pkg" "/data/data/$_pkg/cache"
      _faacc_emit_dir "$_pkg" "/data/data/$_pkg/code_cache"
    else
      _faacc_emit_dir "$_pkg" "$_root/$_pkg/cache"
      _faacc_emit_dir "$_pkg" "$_root/$_pkg/code_cache"
    fi
  done
  # Eksternal (shared storage): hanya .../Android/data/<pkg>/cache
  for _eroot in /sdcard/Android/data /data/media/0/Android/data; do
    _faacc_emit_dir "$_pkg" "$_eroot/$_pkg/cache"
  done
  unset _root _eroot
  [ "$_found" -gt 0 ]
}

# ---------------------------------------------------------------
# get_cache_size(path) : cetak ukuran bytes (angka). Return 1 bila gagal.
# ---------------------------------------------------------------
get_cache_size() {
  _p="$1"
  [ -d "$_p" ] || { echo 0; return 1; }
  # Direktori kosong = 0. Tanpa ini, du menghitung overhead metadata
  # dir (~12 KB) sehingga scan melaporkan "cache" padahal sudah bersih.
  # Cek via glob builtin (nol fork) termasuk dotfiles, kecuali . dan ..
  _gempty=1
  for _e in "$_p"/* "$_p"/.[!.]* "$_p"/..?*; do
    [ -e "$_e" ] || [ -L "$_e" ] || continue
    _gempty=0; break
  done
  unset _e
  if [ "$_gempty" = "1" ]; then echo 0; unset _gempty; return 0; fi
  unset _gempty
  # du = satu-satunya fork per direktori. Parse tanpa awk via read.
  _du=$(du -sk "$_p" 2>/dev/null)
  read -r _bytes _rest <<EOF_DU
$_du
EOF_DU
  unset _du _rest
  case "$_bytes" in ''|*[!0-9]*) echo 0; return 1 ;; esac
  echo $((_bytes * 1024))
  unset _bytes
}

# Human readable: 182 MB dst. Murni shell (nol fork) — dipanggil ratusan
# kali tiap scan, jadi awk dihindari. Pecahan via pembagian bertahap agar
# aman dari overflow aritmetika 32-bit mksh (tak pernah kali angka besar).
faacc_human_size() {
  _b="$1"
  case "$_b" in ''|*[!0-9]*) _b=0 ;; esac
  if [ "$_b" -ge 1073741824 ] 2>/dev/null; then
    _w=$((_b / 1073741824)); _f=$(((_b % 1073741824) / 10737418))
    [ "$_f" -lt 10 ] && _f="0$_f"
    echo "$_w.$_f GB"
  elif [ "$_b" -ge 1048576 ] 2>/dev/null; then
    _w=$((_b / 1048576)); _f=$(((_b % 1048576) / 104857))
    [ "$_f" -gt 9 ] && _f=9
    echo "$_w.$_f MB"
  elif [ "$_b" -ge 1024 ] 2>/dev/null; then
    echo "$((_b / 1024)) KB"
  else
    echo "$_b B"
  fi
  unset _b _w _f
}

# ---------------------------------------------------------------
# faacc_validate_interval(menit) : validasi durasi auto-clean.
# Cetak nilai ternormalisasi (tanpa nol depan), return 1 bila invalid.
# Batas: 5 - 1440 menit (1440 = 24 jam). Murni string/digit, aman di mksh
# 32-bit (nilai kecil) dan tahan input oktal ("08" -> 8, bukan error).
# ---------------------------------------------------------------
faacc_validate_interval() {
  _in="$1"
  case "$_in" in ''|*[!0-9]*) return 1 ;; esac
  _in=$(echo "$_in" | sed 's/^0*//')
  [ -z "$_in" ] && _in="0"
  [ "$_in" -ge 5 ] 2>/dev/null || return 1
  [ "$_in" -le 1440 ] 2>/dev/null || return 1
  echo "$_in"
  unset _in
}

# ---------------------------------------------------------------
# clean_cache(pkg, [cache_dir]) : hapus ISI cache saja, pertahankan direktorinya.
# Return: 0 sukses, 1 abort (unsafe), 2 dir tidak ada, 3 gagal hapus.
# ---------------------------------------------------------------
clean_cache() {
  _pkg="$1"
  _dir="$2"

  validate_package "$_pkg" || {
    echo "CLEANUP ABORTED - Reason: invalid package ($_pkg)" >&2
    faacc_log_error "Invalid package: $_pkg"
    return 1
  }

  # Jika dir tidak disebut, cari semua cache milik pkg
  if [ -z "$_dir" ]; then
    _list=$(faacc_find_cache_dirs "$_pkg")
    if [ -z "$_list" ]; then
      return 2
    fi
    _rc=0; _total_freed=0
    while read -r _d; do
      [ -z "$_d" ] && continue
      _out=$(clean_cache "$_pkg" "$_d" 2>/dev/null)
      _st=$?
      if [ "$_st" -ne 0 ]; then
        _rc="$_st"
      else
        case "$_out" in ''|*[!0-9]*) ;; *) _total_freed=$((_total_freed + _out)) ;; esac
      fi
    done <<EOF_LIST
$_list
EOF_LIST
    echo "$_total_freed"
    return "$_rc"
  fi

  validate_cache_path "$_pkg" "$_dir" || {
    echo "❌ CLEANUP ABORTED" >&2
    echo "Reason: unsafe target" >&2
    faacc_log_error "ABORTED unsafe target pkg=$_pkg path=$_dir"
    return 1
  }

  _before=$(get_cache_size "$_dir")
  # Hapus ISI saja — pola aman: "$_dir"/.. tidak pernah dipakai.
  # Termasuk file tersembunyi di dalam cache.
  rm -rf "$_dir"/* 2>/dev/null
  # Hapus dotfiles (tapi lindungi . dan .. secara eksplisit)
  for _dot in "$_dir"/.[!.]* "$_dir"/..?*; do
    case "$_dot" in
      "$_dir/."|"$_dir/..") continue ;;
    esac
    [ -e "$_dot" ] || [ -L "$_dot" ] || continue
    # Safety: dotfile harus tetap di dalam cache dir
    case "$_dot" in "$_dir"/*) rm -rf "$_dot" 2>/dev/null ;; esac
  done
  unset _dot

  verify_cleanup "$_pkg" "$_dir" || {
    faacc_log_error "Verify gagal pkg=$_pkg path=$_dir"
    return 3
  }

  _after=$(get_cache_size "$_dir")
  _freed=$((_before - _after))
  [ "$_freed" -lt 0 ] && _freed=0
  faacc_log_clean "$_pkg - $(faacc_human_size "$_freed")"
  echo "$_freed"
  unset _pkg _dir _before _after _freed
  return 0
}

# ---------------------------------------------------------------
# verify_cleanup(pkg, dir): pastikan dir masih ada & isinya ~kosong.
# Toleransi: <= 64KB dianggap bersih (ada file yang langsung dibuat ulang OS).
# ---------------------------------------------------------------
verify_cleanup() {
  _pkg="$1"
  _dir="$2"
  is_safe_path "$_pkg" "$_dir" || return 1
  [ -d "$_dir" ] || return 1
  _left=$(get_cache_size "$_dir")
  case "$_left" in ''|*[!0-9]*) return 1 ;; esac
  [ "$_left" -le 65536 ]
}

# ---------------------------------------------------------------
# faacc_scan_all([user_id]) : scan semua package, output "pkg|bytes|dir"
# Dipakai CLI --scan dan WebUI. Tidak menghapus apa pun.
# ---------------------------------------------------------------
faacc_list_packages() {
  if command -v pm >/dev/null 2>&1; then
    pm list packages 2>/dev/null | sed 's/^package://' | sort -u
  else
    # Fallback: daftar direktori /data/data
    for _d in /data/data/*; do
      [ -d "$_d" ] || continue
      basename "$_d"
    done
  fi
  unset _d
}

faacc_scan_all() {
  for _pkg in $(faacc_list_packages); do
    validate_package "$_pkg" || continue
    _total=0; _t_int=0; _t_cc=0; _t_ext=0; _dirs=""
    for _c in $(faacc_find_cache_dirs "$_pkg" 2>/dev/null); do
      _s=$(get_cache_size "$_c" 2>/dev/null)
      case "$_s" in ''|*[!0-9]*) _s=0 ;; esac
      _total=$((_total + _s))
      # Klasifikasi jenis: eksternal / code_cache / internal
      case "$_c" in
        */Android/data/*) _t_ext=$((_t_ext + _s)) ;;
        */code_cache) _t_cc=$((_t_cc + _s)) ;;
        *) _t_int=$((_t_int + _s)) ;;
      esac
      _dirs="${_dirs:+$_dirs,}$_c"
    done
    # Cetak semua, termasuk yang 0 agar WebUI bisa tampilkan status lengkap.
    # Format pipe agar mudah diparse:
    # pkg|total|internal|code_cache|external|dir1,dir2
    echo "$_pkg|$_total|$_t_int|$_t_cc|$_t_ext|$_dirs"
  done
  unset _pkg _total _t_int _t_cc _t_ext _dirs _c _s
}
