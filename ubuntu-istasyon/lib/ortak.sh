#!/usr/bin/env bash
# Ortak yardımcılar: tüm aşama betikleri bu dosyayı "source" eder.
# Kendi başına çalıştırılmaz.

# ---------------------------------------------------------------------------
# Yollar
# ---------------------------------------------------------------------------
ISTASYON_DIZIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
YEDEK_KOK="${YEDEK_KOK:-$HOME/ayar_yedek}"
DEGISIKLIK_LOG="$YEDEK_KOK/degisiklikler.log"
GUNLUK_DIZIN="$YEDEK_KOK/gunlukler"

# ISTASYON_OTOMATIK=1 ise sorular varsayılan cevapla geçilir (test / tekrar çalıştırma için).
ISTASYON_OTOMATIK="${ISTASYON_OTOMATIK:-0}"

# ---------------------------------------------------------------------------
# Çıktı
# ---------------------------------------------------------------------------
if [[ -t 1 ]]; then
  R_MAVI=$'\033[1;34m'; R_YESIL=$'\033[1;32m'; R_SARI=$'\033[1;33m'
  R_KIRMIZI=$'\033[1;31m'; R_GRI=$'\033[0;90m'; R_KALIN=$'\033[1m'; R_SIFIR=$'\033[0m'
else
  R_MAVI=; R_YESIL=; R_SARI=; R_KIRMIZI=; R_GRI=; R_KALIN=; R_SIFIR=
fi

bilgi()    { printf '%s==>%s %s\n' "$R_MAVI" "$R_SIFIR" "$*"; }
basarili() { printf '%s ✔%s  %s\n' "$R_YESIL" "$R_SIFIR" "$*"; }
uyari()    { printf '%s ⚠%s  %s\n' "$R_SARI" "$R_SIFIR" "$*"; }
hata()     { printf '%s ✖%s  %s\n' "$R_KIRMIZI" "$R_SIFIR" "$*" >&2; }
not_yaz()  { printf '%s    %s%s\n' "$R_GRI" "$*" "$R_SIFIR"; }

# Aşama başında ne yapılacağını ve sudo gerekip gerekmediğini gösterir.
# Kullanım: asama_ozeti "BAŞLIK" "sudo açıklaması (boşsa gerekmez)" "madde 1" "madde 2" ...
asama_ozeti() {
  local baslik=$1 sudo_aciklama=$2; shift 2
  printf '\n%s━━━ %s ━━━%s\n' "$R_KALIN" "$baslik" "$R_SIFIR"
  printf 'Bu aşamada yapacaklarım:\n'
  local m
  for m in "$@"; do printf '  • %s\n' "$m"; done
  if [[ -n $sudo_aciklama ]]; then
    printf '%s🔑 sudo GEREKİYOR:%s %s\n' "$R_SARI" "$R_SIFIR" "$sudo_aciklama"
  else
    printf '%s🔓 sudo gerekmiyor.%s\n' "$R_YESIL" "$R_SIFIR"
  fi
  printf '\n'
}

# ---------------------------------------------------------------------------
# Etkileşim
# ---------------------------------------------------------------------------
# onay "Soru?" [e|h]  → evet ise 0 döner. Varsayılan cevap köşeli parantezde büyük harfle görünür.
onay() {
  local soru=$1 varsayilan=${2:-h} ipucu cevap
  [[ $varsayilan == e ]] && ipucu="E/h" || ipucu="e/H"
  if [[ $ISTASYON_OTOMATIK == 1 ]]; then
    printf '%s [%s] → %s (otomatik)\n' "$soru" "$ipucu" "$varsayilan"
    [[ $varsayilan == e ]]
    return
  fi
  while true; do
    read -r -p "$soru [$ipucu] " cevap </dev/tty || cevap=""
    cevap=${cevap,,}
    [[ -z $cevap ]] && cevap=$varsayilan
    case $cevap in
      e|evet|y|yes) return 0 ;;
      h|hayir|hayır|n|no) return 1 ;;
      *) printf 'Lütfen e (evet) ya da h (hayır) yaz.\n' ;;
    esac
  done
}

# sor "Soru" "varsayılan" → cevabı stdout'a yazar
sor() {
  local soru=$1 varsayilan=${2:-} cevap
  if [[ $ISTASYON_OTOMATIK == 1 ]]; then printf '%s' "$varsayilan"; return; fi
  read -r -p "$soru${varsayilan:+ [$varsayilan]}: " cevap </dev/tty || cevap=""
  printf '%s' "${cevap:-$varsayilan}"
}

# ---------------------------------------------------------------------------
# Ortam kontrolleri
# ---------------------------------------------------------------------------
komut_var() { command -v "$1" >/dev/null 2>&1; }

ortam_kontrol() {
  if [[ $EUID -eq 0 ]]; then
    hata "Bu betiği sudo ile ya da root olarak çalıştırma. Normal kullanıcınla çalıştır; gerektiğinde şifreni kendisi ister."
    exit 1
  fi
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    if [[ ${ID:-} != ubuntu ]]; then
      uyari "Bu sistem Ubuntu görünmüyor (ID=${ID:-?}). Betikler Ubuntu 26.04 için yazıldı."
      onay "Yine de devam edilsin mi?" h || exit 1
    elif [[ ${VERSION_ID:-} != 26.04 ]]; then
      uyari "Ubuntu ${VERSION_ID:-?} algılandı; betikler 26.04 için hazırlandı. Çoğu adım yine çalışır."
    fi
  fi
  mkdir -p "$YEDEK_KOK" "$GUNLUK_DIZIN"
}

gnome_kontrol() {
  if [[ ${XDG_CURRENT_DESKTOP:-} != *GNOME* ]] || [[ -z ${DBUS_SESSION_BUS_ADDRESS:-} ]]; then
    hata "Bu aşama GNOME oturumu içindeki bir terminalden çalıştırılmalı (ör. Terminal / Ptyxis)."
    return 1
  fi
  komut_var gsettings || { hata "gsettings bulunamadı."; return 1; }
}

# Ekran çıktısını aynı zamanda günlük dosyasına yazar.
gunluk_baslat() {
  local ad=$1
  mkdir -p "$GUNLUK_DIZIN"
  GUNLUK_DOSYA="$GUNLUK_DIZIN/$(date +%Y-%m-%d_%H%M%S)_$ad.log"
  exec > >(tee -a "$GUNLUK_DOSYA") 2>&1
  not_yaz "Günlük: $GUNLUK_DOSYA"
}

# ---------------------------------------------------------------------------
# sudo
# ---------------------------------------------------------------------------
SUDO_CANLI_PID=""
sudo_hazirla() {
  local neden=$1
  printf '%s🔑 sudo şifren istenecek:%s %s\n' "$R_SARI" "$R_SIFIR" "$neden"
  sudo -v || { hata "sudo yetkisi alınamadı."; return 1; }
  # Uzun kurulumlarda şifrenin tekrar sorulmaması için oturumu canlı tut.
  if [[ -z $SUDO_CANLI_PID ]]; then
    ( while kill -0 "$$" 2>/dev/null; do sudo -n true 2>/dev/null; sleep 50; done ) &
    SUDO_CANLI_PID=$!
    trap 'kill "$SUDO_CANLI_PID" 2>/dev/null' EXIT
  fi
}

# ---------------------------------------------------------------------------
# Değişiklik kaydı (geri alma ve rapor bunu okur)
# Biçim: ZAMAN|TÜR|DEĞER|AÇIKLAMA
#   ayar            gsettings/dconf değişikliği (dconf yedeğiyle geri alınır)
#   dosya           değiştirilen dosya (ilk hali $YEDEK_KOK/dosyalar altında)
#   servis          kapatılan servis (geri almada yeniden etkinleşir)
#   servis_eklendi  yeni eklenen servis (geri almada kapatılır)
#   paket_kuruldu / paket_kaldirildi / snap_kaldirildi / pipx_kuruldu
#   eklenti         kurulan GNOME eklentisi
#   prime           NVIDIA PRIME kipinin eski değeri
#   grup            kullanıcının eklendiği grup
#   depo            eklenen apt deposu
#   bilgi           yalnızca rapor için not
# ---------------------------------------------------------------------------
kaydet() {
  local tur=$1 deger=$2 aciklama=${3:-}
  mkdir -p "$YEDEK_KOK"
  printf '%s|%s|%s|%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$tur" "${deger//|//}" "${aciklama//|//}" >>"$DEGISIKLIK_LOG"
}

yedek_gerekli() {
  if [[ ! -f $YEDEK_KOK/dconf-ilk.ini ]]; then
    uyari "Henüz yedek alınmamış. Hiçbir şeyi değiştirmeden önce yedek alıyorum."
    bash "$ISTASYON_DIZIN/00-yedekle.sh" || { hata "Yedek alınamadı; güvenlik için duruyorum."; exit 1; }
  else
    # Her aşamadan önce o anki durumun da anlık görüntüsünü al (ilk yedek hiç değişmez).
    bash "$ISTASYON_DIZIN/00-yedekle.sh" --sessiz || uyari "Anlık yedek alınamadı (ilk yedek duruyor)."
  fi
}

# Bir dosyanın İLK halini saklar (sonraki çalıştırmalar üzerine yazmaz).
dosya_yedekle() {
  local yol=$1 hedef="$YEDEK_KOK/dosyalar$1"
  [[ -e $hedef || -e $hedef.yoktu ]] && return 0
  mkdir -p "$(dirname "$hedef")"
  if [[ -e $yol ]]; then
    if [[ -r $yol ]]; then
      cp -p "$yol" "$hedef"
    else
      # Yedek kullanıcıya ait olsun diye yönlendirme bilerek sudo dışında.
      # shellcheck disable=SC2024
      sudo cat "$yol" >"$hedef"
    fi
  else
    : >"$hedef.yoktu"
  fi
  kaydet dosya "$yol" "değiştirilmeden önceki hali yedeklendi"
}

# ---------------------------------------------------------------------------
# gsettings (anahtar bu GNOME sürümünde yoksa sessizce atlar)
# ---------------------------------------------------------------------------
gsetting_var() { gsettings list-keys "$1" 2>/dev/null | grep -qx "$2"; }

gset() {
  local sema=$1 anahtar=$2 deger=$3 eski yeni
  if ! gsetting_var "$sema" "$anahtar"; then
    not_yaz "atlandı: $sema $anahtar (bu sürümde yok)"
    return 1
  fi
  eski=$(gsettings get "$sema" "$anahtar")
  if ! gsettings set "$sema" "$anahtar" "$deger" 2>/dev/null; then
    uyari "ayarlanamadı: $sema $anahtar = $deger"
    return 1
  fi
  yeni=$(gsettings get "$sema" "$anahtar")
  if [[ $eski != "$yeni" ]]; then
    kaydet ayar "$sema $anahtar" "$eski → $yeni"
    not_yaz "$sema $anahtar: $eski → $yeni"
  fi
}

# ---------------------------------------------------------------------------
# apt
# ---------------------------------------------------------------------------
paket_kurulu() { dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"; }
paket_depoda() { apt-cache show "$1" >/dev/null 2>&1; }

APT_GUNCEL=0
apt_guncelle() {
  ((APT_GUNCEL)) && return 0
  bilgi "Paket listeleri güncelleniyor (apt update)…"
  sudo apt-get update -q && APT_GUNCEL=1
}

# apt_kur paket1 paket2 … ("paket-" sonekli olanlar kurulmaz, kurulumu engellenir)
apt_kur() {
  local eksik=() p
  for p in "$@"; do
    [[ $p == *- ]] && continue
    paket_kurulu "$p" || eksik+=("$p")
  done
  if ((${#eksik[@]} == 0)); then
    basarili "Zaten kurulu: $*"
    return 0
  fi
  apt_guncelle || return 1
  local kurulacak=()
  for p in "$@"; do
    if [[ $p == *- ]]; then
      paket_depoda "${p%-}" && kurulacak+=("$p")   # "paket-" = kurulmasını engelle (depoda varsa)
    elif paket_depoda "$p"; then
      kurulacak+=("$p")
    else
      uyari "Depoda yok, atlanıyor: $p"
    fi
  done
  bilgi "Kuruluyor: ${eksik[*]}"
  sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y "${kurulacak[@]}" || return 1
  for p in "${eksik[@]}"; do
    paket_kurulu "$p" && kaydet paket_kuruldu "$p" "apt ile kuruldu"
  done
  return 0
}

# Bir apt deposunun bu Ubuntu sürümünü destekleyip desteklemediğine bakar.
depo_surumu_destekliyor() { curl -fsIL --max-time 15 "$1/dists/$2/Release" >/dev/null 2>&1; }

ubuntu_kod_adi() {
  # shellcheck disable=SC1091
  (. /etc/os-release; printf '%s' "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
}

# ---------------------------------------------------------------------------
# Adım yürütücü: bir adım başarısız olursa betik durmaz, sonda listelenir.
# ---------------------------------------------------------------------------
BASARISIZ_ADIMLAR=()
adim() {
  local ad=$1; shift
  printf '\n%s▶ %s%s\n' "$R_KALIN" "$ad" "$R_SIFIR"
  if "$@"; then
    return 0
  else
    BASARISIZ_ADIMLAR+=("$ad")
    hata "Adım tamamlanamadı: $ad (diğer adımlara devam ediliyor)"
    return 1
  fi
}

asama_sonu() {
  local ad=$1
  printf '\n'
  if ((${#BASARISIZ_ADIMLAR[@]})); then
    uyari "$ad tamamlandı, ancak şu adımlar başarısız oldu:"
    local a
    for a in "${BASARISIZ_ADIMLAR[@]}"; do printf '    - %s\n' "$a"; done
    not_yaz "Ayrıntılar günlükte: ${GUNLUK_DOSYA:-$GUNLUK_DIZIN}"
  else
    basarili "$ad tamamlandı."
  fi
}
