#!/usr/bin/env bash
# TEK KOMUTLA GERİ ALMA
#
#   bash ~/ayar_yedek/geri-al.sh                    → her şeyi kurulum öncesine döndürür
#   bash ~/ayar_yedek/geri-al.sh --sadece-ayarlar   → yalnızca GNOME/dconf ayarlarını döndürür (sudo istemez)
#
# Kurulan programlar varsayılan olarak KALIR (istersen sorulduğunda kaldırabilirsin);
# kaldırdığın ön yüklü uygulamaları yeniden kurmayı teklif eder.
set -uo pipefail
# shellcheck source=lib/ortak.sh
source "$(dirname "$0")/lib/ortak.sh"

SADECE_AYARLAR=0
for arg in "$@"; do
  case $arg in
    --sadece-ayarlar) SADECE_AYARLAR=1 ;;
    -h|--yardim|--help) sed -n '2,9p' "$0"; exit 0 ;;
    *) hata "Bilinmeyen seçenek: $arg"; exit 1 ;;
  esac
done

ortam_kontrol
ILK_YEDEK="$YEDEK_KOK/dconf-ilk.ini"
[[ -s $ILK_YEDEK ]] || { hata "İlk yedek bulunamadı: $ILK_YEDEK"; exit 1; }

kayit_sayisi() { [[ -f $DEGISIKLIK_LOG ]] && awk -F'|' -v t="$1" '$2==t' "$DEGISIKLIK_LOG" | wc -l || echo 0; }

if ((SADECE_AYARLAR)); then
  asama_ozeti "GERİ ALMA (yalnızca ayarlar)" "" \
    "Tüm GNOME ayarlarını $(cat "$YEDEK_KOK/ilk-yedek-zamani.txt" 2>/dev/null) tarihli ilk yedeğe döndüreceğim" \
    "Tema, simge, imleç, yazı tipi, duvar kâğıdı, dock ve eklenti açık/kapalı durumu eski haline gelir"
else
  asama_ozeti "GERİ ALMA (tamamı)" "kapatılan servisleri açmak, değiştirilen sistem dosyalarını ve NVIDIA PRIME kipini eski haline getirmek için" \
    "Tüm GNOME ayarlarını ilk yedeğe döndüreceğim ($(kayit_sayisi ayar) ayar değişikliği kayıtlı)" \
    "Kurulan GNOME eklentilerini kaldıracağım ($(kayit_sayisi eklenti) adet)" \
    "Kapatılan servisleri yeniden açacağım ($(kayit_sayisi servis) adet)" \
    "Değiştirilen dosyaları ilk hallerine döndüreceğim ($(kayit_sayisi dosya) adet)" \
    "Kaldırılan ön yüklü uygulamaları yeniden kurmayı soracağım ($(( $(kayit_sayisi paket_kaldirildi) + $(kayit_sayisi snap_kaldirildi) )) adet)" \
    "Kurulan programları KALDIRMAYACAĞIM; istersen ayrıca soracağım ($(kayit_sayisi paket_kuruldu) apt + $(kayit_sayisi pipx_kuruldu) pipx)" \
    "~/Projeler klasörüne DOKUNMAYACAĞIM"
fi
onay "Geri alma başlasın mı?" h || { bilgi "İptal edildi, hiçbir şey değişmedi."; exit 0; }

# Geri almadan hemen önceki durumu da sakla (fikrini değiştirirsen diye).
ZAMAN=$(date +%Y-%m-%d_%H%M%S)
mkdir -p "$YEDEK_KOK/anlik/$ZAMAN-geri-alma-oncesi"
dconf dump / >"$YEDEK_KOK/anlik/$ZAMAN-geri-alma-oncesi/dconf.ini"

# --- 1) dconf ---------------------------------------------------------------
bilgi "GNOME ayarları ilk yedeğe döndürülüyor…"
if dconf reset -f / && dconf load / <"$ILK_YEDEK"; then
  basarili "GNOME ayarları geri yüklendi."
else
  hata "dconf geri yüklemesi başarısız. Elle: dconf reset -f / && dconf load / < $ILK_YEDEK"
fi

if ((SADECE_AYARLAR)); then
  basarili "Bitti. Tam görünüm için oturumu kapatıp yeniden açman önerilir."
  exit 0
fi

[[ -f $DEGISIKLIK_LOG ]] || { basarili "Başka kayıtlı değişiklik yok. Bitti."; exit 0; }

# --- 2) Kayıtları sondan başa işle ---------------------------------------------
GERI_KURULACAK_APT=(); GERI_KURULACAK_SNAP=(); KURULAN_APT=(); KURULAN_PIPX=(); DEPOLAR=(); GRUPLAR=()
SUDO_HAZIR=0
sudo_bir_kez() { ((SUDO_HAZIR)) || { sudo_hazirla "sistem tarafındaki değişiklikleri geri almak için" && SUDO_HAZIR=1; }; }

dosya_geri_yukle() {
  local yol=$1 kaynak="$YEDEK_KOK/dosyalar$1"
  if [[ -e $kaynak.yoktu ]]; then
    if [[ $yol == "$HOME"/* ]]; then rm -f -- "$yol"; else sudo_bir_kez && sudo rm -f -- "$yol"; fi
    basarili "Kaldırıldı (önceden yoktu): $yol"
  elif [[ -e $kaynak ]]; then
    if [[ $yol == "$HOME"/* ]]; then cp -p -- "$kaynak" "$yol"; else sudo_bir_kez && sudo cp -- "$kaynak" "$yol"; fi
    basarili "Eski haline döndü: $yol"
  else
    uyari "Yedeği bulunamadı, atlandı: $yol"
  fi
}

while IFS='|' read -r _zaman tur deger _aciklama; do
  case $tur in
    eklenti)
      if gnome-extensions uninstall "$deger" 2>/dev/null; then basarili "Eklenti kaldırıldı: $deger"
      else not_yaz "Eklenti zaten yok ya da sistem eklentisi: $deger"; fi ;;
    servis_eklendi)
      sudo_bir_kez && sudo systemctl disable --now "$deger" 2>/dev/null && basarili "Servis kapatıldı: $deger" ;;
    servis)
      sudo_bir_kez && sudo systemctl enable "$deger" 2>/dev/null && basarili "Servis yeniden açıldı: $deger" ;;
    prime)
      sudo_bir_kez && sudo prime-select "$deger" && basarili "NVIDIA PRIME kipi geri alındı: $deger" ;;
    dosya)            dosya_geri_yukle "$deger" ;;
    grup)             GRUPLAR+=("$deger") ;;
    paket_kaldirildi) GERI_KURULACAK_APT+=("$deger") ;;
    snap_kaldirildi)  GERI_KURULACAK_SNAP+=("$deger") ;;
    paket_kuruldu)    KURULAN_APT+=("$deger") ;;
    pipx_kuruldu)     KURULAN_PIPX+=("$deger") ;;
    depo)             DEPOLAR+=("$deger") ;;
  esac
done < <(tac "$DEGISIKLIK_LOG")

if ((${#GERI_KURULACAK_APT[@]} + ${#GERI_KURULACAK_SNAP[@]})); then
  printf '\nKaldırılmış ön yüklü uygulamalar: %s\n' "${GERI_KURULACAK_APT[*]} ${GERI_KURULACAK_SNAP[*]}"
  if onay "Bunlar yeniden kurulsun mu?" e; then
    sudo_bir_kez
    ((${#GERI_KURULACAK_APT[@]})) && sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y "${GERI_KURULACAK_APT[@]}"
    for s in "${GERI_KURULACAK_SNAP[@]}"; do sudo snap install "$s"; done
  fi
fi

for g in "${GRUPLAR[@]}"; do
  if onay "Kullanıcın '$g' grubundan çıkarılsın mı?" h; then
    sudo_bir_kez && sudo gpasswd -d "$USER" "$g"
  fi
done

if ((${#KURULAN_APT[@]} + ${#KURULAN_PIPX[@]})); then
  printf '\nBu kurulumla eklenen programlar:\n  apt : %s\n  pipx: %s\n' "${KURULAN_APT[*]:-—}" "${KURULAN_PIPX[*]:-—}"
  if onay "Bunlar da KALDIRILSIN mı? (önerilmez; programlar ayar değildir)" h; then
    sudo_bir_kez
    ((${#KURULAN_APT[@]})) && sudo env DEBIAN_FRONTEND=noninteractive apt-get remove -y "${KURULAN_APT[@]}"
    for p in "${KURULAN_PIPX[@]}"; do pipx uninstall "$p"; done
    for d in "${DEPOLAR[@]}"; do
      if [[ $d == ppa:* ]]; then sudo add-apt-repository --remove -y "$d"
      else sudo rm -f -- "$d"; fi && not_yaz "Depo kaldırıldı: $d"
    done
  fi
fi

mv "$DEGISIKLIK_LOG" "$YEDEK_KOK/degisiklikler-geri-alindi-$ZAMAN.log"
basarili "Geri alma tamamlandı. Kayıt: $YEDEK_KOK/degisiklikler-geri-alindi-$ZAMAN.log"
uyari "Değişikliklerin tamamen oturması için oturumu kapatıp aç (servis/sürücü değişikliği varsa yeniden başlat)."
