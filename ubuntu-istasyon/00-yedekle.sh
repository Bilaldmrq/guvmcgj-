#!/usr/bin/env bash
# 0. AŞAMA — Mevcut ayarların yedeği (hiçbir şeyi değiştirmez, sudo gerekmez).
#
#   ~/ayar_yedek/dconf-ilk.ini        → İLK yedek; bir daha asla üzerine yazılmaz
#   ~/ayar_yedek/anlik/<zaman>/       → her çalıştırmada o anki durumun anlık görüntüsü
#   ~/ayar_yedek/geri-al.sh           → tek komutla geri alma
set -uo pipefail
# shellcheck source=lib/ortak.sh
source "$(dirname "$0")/lib/ortak.sh"

SESSIZ=0
[[ ${1:-} == --sessiz ]] && SESSIZ=1

ortam_kontrol

if ((!SESSIZ)); then
  asama_ozeti "0/5 YEDEK" "" \
    "GNOME/dconf ayarlarının tamamını 'dconf dump /' ile ~/ayar_yedek klasörüne yazacağım" \
    "Kurulu paket, snap, eklenti, servis ve otomatik başlatma listelerini kaydedeceğim" \
    "Geri alma betiğini ~/ayar_yedek/geri-al.sh olarak koyacağım" \
    "Hiçbir ayarı DEĞİŞTİRMİYORUM"
fi

komut_var dconf || { hata "dconf komutu yok (dconf-cli paketi). Yedek alınamıyor."; exit 1; }

ZAMAN=$(date +%Y-%m-%d_%H%M%S)
ANLIK="$YEDEK_KOK/anlik/$ZAMAN"
mkdir -p "$ANLIK"

# 1) dconf — tüm kullanıcı ayarları
if ! dconf dump / >"$ANLIK/dconf.ini"; then
  hata "dconf dump başarısız."
  exit 1
fi
if [[ ! -s $YEDEK_KOK/dconf-ilk.ini ]]; then
  cp "$ANLIK/dconf.ini" "$YEDEK_KOK/dconf-ilk.ini"
  chmod 444 "$YEDEK_KOK/dconf-ilk.ini"
  printf '%s\n' "$ZAMAN" >"$YEDEK_KOK/ilk-yedek-zamani.txt"
  ILK=1
else
  ILK=0
fi

# 2) Okunabilir kopya (varsayılanlar dahil) — karşılaştırma için
komut_var gsettings && gsettings list-recursively >"$ANLIK/gsettings.txt" 2>/dev/null

# 3) Eklentiler
if komut_var gnome-extensions; then
  gnome-extensions list >"$ANLIK/eklentiler-tum.txt" 2>/dev/null
  gnome-extensions list --enabled >"$ANLIK/eklentiler-acik.txt" 2>/dev/null
fi
[[ -d $HOME/.local/share/gnome-shell/extensions ]] &&
  ls -1 "$HOME/.local/share/gnome-shell/extensions" >"$ANLIK/eklentiler-kullanici-dizini.txt"

# 4) Paketler
komut_var apt-mark && apt-mark showmanual >"$ANLIK/apt-elle-kurulan.txt" 2>/dev/null
dpkg-query -W -f='${Package}\t${Version}\n' >"$ANLIK/apt-tum-paketler.tsv" 2>/dev/null
komut_var snap && snap list >"$ANLIK/snap.txt" 2>/dev/null
komut_var flatpak && flatpak list --app >"$ANLIK/flatpak.txt" 2>/dev/null
komut_var pipx && pipx list --short >"$ANLIK/pipx.txt" 2>/dev/null
ls /etc/apt/sources.list.d/ >"$ANLIK/apt-depolari.txt" 2>/dev/null

# 5) Servisler ve açılış
systemctl list-unit-files --state=enabled --no-legend >"$ANLIK/servisler-sistem.txt" 2>/dev/null
systemctl --user list-unit-files --state=enabled --no-legend >"$ANLIK/servisler-kullanici.txt" 2>/dev/null
komut_var systemd-analyze && systemd-analyze >"$ANLIK/acilis-suresi.txt" 2>/dev/null
[[ -d $HOME/.config/autostart ]] && cp -a "$HOME/.config/autostart" "$ANLIK/autostart"

# 6) Donanım/güç durumu (bilgi amaçlı)
{
  komut_var prime-select && printf 'prime-select: %s\n' "$(prime-select query 2>/dev/null)"
  komut_var powerprofilesctl && printf 'güç profili: %s\n' "$(powerprofilesctl get 2>/dev/null)"
  komut_var nvidia-smi && nvidia-smi --query-gpu=name,driver_version --format=csv,noheader 2>/dev/null
  uname -r
} >"$ANLIK/donanim.txt" 2>/dev/null

# 7) Geri alma betiğini yedeğin yanına koy (kurulum klasörü silinse bile çalışsın)
mkdir -p "$YEDEK_KOK/lib"
cp "$ISTASYON_DIZIN/geri-al.sh" "$YEDEK_KOK/geri-al.sh"
cp "$ISTASYON_DIZIN/rapor.sh" "$YEDEK_KOK/rapor.sh"
cp "$ISTASYON_DIZIN/lib/ortak.sh" "$YEDEK_KOK/lib/ortak.sh"
chmod +x "$YEDEK_KOK/geri-al.sh" "$YEDEK_KOK/rapor.sh"

cat >"$YEDEK_KOK/BENIOKU.txt" <<'METIN'
AYAR YEDEĞİ
===========
dconf-ilk.ini        Kurulumdan ÖNCEKİ tüm GNOME ayarların (dconf dump /). Asla değiştirilmez.
anlik/<zaman>/       Her aşamadan önce alınan anlık görüntüler (paket, servis, eklenti listeleri).
dosyalar/            Değiştirilen sistem/kullanıcı dosyalarının ilk halleri.
degisiklikler.log    Yapılan her değişikliğin kaydı.
gunlukler/           Ekran çıktılarının günlükleri.

TEK KOMUTLA GERİ ALMA:
    bash ~/ayar_yedek/geri-al.sh

Yalnızca görünüm/GNOME ayarlarını geri almak için (sudo istemez):
    bash ~/ayar_yedek/geri-al.sh --sadece-ayarlar

Elle geri yüklemek istersen:
    dconf reset -f / && dconf load / < ~/ayar_yedek/dconf-ilk.ini
METIN

if ((ILK)); then
  kaydet bilgi "yedek" "İlk yedek alındı: $YEDEK_KOK/dconf-ilk.ini"
fi

if ((SESSIZ)); then
  not_yaz "Anlık yedek: $ANLIK"
else
  basarili "Yedek hazır: $YEDEK_KOK"
  if ((ILK)); then
    basarili "İlk (değişmeyecek) dconf yedeği: $YEDEK_KOK/dconf-ilk.ini"
  else
    not_yaz "İlk yedek zaten vardı ($(cat "$YEDEK_KOK/ilk-yedek-zamani.txt" 2>/dev/null)); o korunuyor."
  fi
  printf '\nGeri almak için tek komut:  %sbash ~/ayar_yedek/geri-al.sh%s\n' "$R_KALIN" "$R_SIFIR"
fi
