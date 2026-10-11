#!/usr/bin/env bash
# 2b. AŞAMA — GEREKSİZ ÖN YÜKLÜ UYGULAMALAR: yalnızca ÖNERİR, her biri için ayrı onay ister.
# Varsayılan cevap her zaman "hayır"dır; onay vermediğin hiçbir şey silinmez.
set -uo pipefail
# shellcheck source=lib/ortak.sh
source "$(dirname "$0")/lib/ortak.sh"

ortam_kontrol
gunluk_baslat gereksizler

# paket|tür|açıklama|öneri notu
ADAYLAR=(
  "gnome-mahjongg|apt|Mahjongg oyunu|"
  "gnome-mines|apt|Mayın Tarlası oyunu|"
  "gnome-sudoku|apt|Sudoku oyunu|"
  "aisleriot|apt|Kart oyunları (Solitaire)|"
  "rhythmbox|apt|Müzik çalar|VLC zaten her şeyi çalar"
  "totem|apt|GNOME Videolar oynatıcısı|VLC kurulu"
  "showtime|apt|GNOME video oynatıcısı|VLC kurulu"
  "shotwell|apt|Fotoğraf yöneticisi|"
  "transmission-gtk|apt|Torrent istemcisi|"
  "remmina|apt|Uzak masaüstü istemcisi|Uzak bağlantı kullanıyorsan tut"
  "cheese|apt|Kamera uygulaması|OBS kamerayı zaten açar"
  "libreoffice-common|apt|LibreOffice ofis paketi (tamamı)|Word/Excel dosyası açıyorsan TUT"
  "thunderbird|snap|Thunderbird e-posta istemcisi|Gmail'i tarayıcıdan kullanıyorsan gereksiz"
)

asama_ozeti "GEREKSİZ UYGULAMALAR (yalnızca öneri)" "onay verdiğin uygulamaları kaldırmak için (apt/snap)" \
  "Ön yüklü uygulamalar arasından kurulu olanları listeleyeceğim" \
  "Her biri için AYRI AYRI soracağım; varsayılan cevap HAYIR" \
  "'remove' kullanırım (purge değil): ayar dosyaların kalır, geri-al.sh yeniden kurabilir" \
  "Firefox, Dosyalar, Ayarlar, Uygulama Merkezi ve yedekleme aracı gibi temel parçalara DOKUNMAM"
onay "Önerileri görmek ister misin?" e || { bilgi "Atlandı."; exit 0; }

snap_kurulu() { komut_var snap && snap list "$1" >/dev/null 2>&1; }

KURULU=()
for satir in "${ADAYLAR[@]}"; do
  IFS='|' read -r ad tur _ _ <<<"$satir"
  if [[ $tur == apt ]] && paket_kurulu "$ad"; then KURULU+=("$satir")
  elif [[ $tur == snap ]] && snap_kurulu "$ad"; then KURULU+=("$satir"); fi
done

if ((${#KURULU[@]} == 0)); then
  basarili "Önerilecek gereksiz uygulama bulunamadı; sistem zaten sade."
  exit 0
fi

printf '\nKurulu olan aday uygulamalar:\n'
for satir in "${KURULU[@]}"; do
  IFS='|' read -r ad tur aciklama notu <<<"$satir"
  printf '  • %-20s %-5s %s%s\n' "$ad" "($tur)" "$aciklama" "${notu:+ — $notu}"
done
printf '\n'

SILINECEK_APT=(); SILINECEK_SNAP=()
for satir in "${KURULU[@]}"; do
  IFS='|' read -r ad tur aciklama _ <<<"$satir"
  if onay "Kaldırılsın mı: $aciklama ($ad)?" h; then
    [[ $tur == apt ]] && SILINECEK_APT+=("$ad") || SILINECEK_SNAP+=("$ad")
  fi
done

if ((${#SILINECEK_APT[@]} + ${#SILINECEK_SNAP[@]} == 0)); then
  basarili "Hiçbir şey kaldırılmadı."
  exit 0
fi

# apt, bağımlı paketleri de kaldırabilir: gerçek etkiyi önceden göster ve hepsini kaydet.
ETKILENEN_APT=""
if ((${#SILINECEK_APT[@]})); then
  ETKILENEN_APT=$(apt-get -s remove "${SILINECEK_APT[@]}" 2>/dev/null | awk '/^Remv /{print $2}')
fi
printf '\nKaldırılacak paketler (bağımlılarıyla birlikte):\n'
[[ -n $ETKILENEN_APT ]] && sed 's/^/  - /' <<<"$ETKILENEN_APT"
for s in "${SILINECEK_SNAP[@]}"; do printf '  - %s (snap)\n' "$s"; done
onay "Son onay: bunlar kaldırılsın mı?" h || { bilgi "Vazgeçildi, hiçbir şey kaldırılmadı."; exit 0; }

yedek_gerekli
sudo_hazirla "seçtiğin uygulamaları kaldırmak için" || exit 1

if [[ -n $ETKILENEN_APT ]]; then
  if sudo env DEBIAN_FRONTEND=noninteractive apt-get remove -y "${SILINECEK_APT[@]}"; then
    while read -r p; do kaydet paket_kaldirildi "$p" "kullanıcı onayıyla kaldırıldı"; done <<<"$ETKILENEN_APT"
  fi
fi
for s in "${SILINECEK_SNAP[@]}"; do
  sudo snap remove "$s" && kaydet snap_kaldirildi "$s" "kullanıcı onayıyla kaldırıldı"
done

# Artık kullanılmayan bağımlılıklar
OTO=$(apt-get -s autoremove 2>/dev/null | awk '/^Remv /{print $2}')
if [[ -n $OTO ]]; then
  printf '\nArtık hiçbir şeyin kullanmadığı bağımlılıklar:\n%s\n' "$(sed 's/^/  - /' <<<"$OTO")"
  if onay "Bunlar da temizlensin mi (apt autoremove)?" h; then
    sudo apt-get autoremove -y && while read -r p; do kaydet paket_kaldirildi "$p" "autoremove"; done <<<"$OTO"
  fi
fi

basarili "Kaldırma tamamlandı. Geri almak istersen: bash ~/ayar_yedek/geri-al.sh"
