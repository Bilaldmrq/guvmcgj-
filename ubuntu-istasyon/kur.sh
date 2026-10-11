#!/usr/bin/env bash
# Ubuntu çalışma istasyonu kurulumu — ana menü.
#
#   bash kur.sh          → menü
#   bash kur.sh hepsi    → tüm aşamalar sırayla (her aşama yine önce ne yapacağını söyleyip onay ister)
#   bash kur.sh 2        → yalnızca 2. aşama (programlar) … vb.
set -uo pipefail
cd "$(dirname "$0")" || exit 1
# shellcheck source=lib/ortak.sh
source lib/ortak.sh

ortam_kontrol

asamalar=(
  "00-yedekle.sh|Yedek (dconf dump → ~/ayar_yedek)"
  "10-gorunum.sh|Görünüm (tema, simge, imleç, yazı tipi, duvar kâğıdı, dock, eklentiler)"
  "20-programlar.sh|Programlar (Chrome, VS Code, OBS, VLC, GIMP, Docker, Node.js, Python, ffmpeg, git)"
  "25-gereksizler.sh|Gereksiz ön yüklü uygulamalar (yalnızca öneri, tek tek onay)"
  "30-sistem.sh|Sistem (NVIDIA, güç profilleri, ASUS, güvenlik güncellemeleri, açılış)"
  "40-projeler.sh|Çalışma alanı (~/Projeler, sanal ortamlar, testler)"
)

calistir_asama() {
  local dosya=${asamalar[$1]%%|*}
  bash "./$dosya" || uyari "$dosya hata koduyla bitti; sonraki aşamaya geçilebilir."
}

hepsi() {
  local i
  for i in "${!asamalar[@]}"; do calistir_asama "$i"; done
  bash ./rapor.sh
  printf '\n'
  uyari "Tüm değişikliklerin oturması için bilgisayarı YENİDEN BAŞLAT."
}

case ${1:-} in
  hepsi) hepsi; exit ;;
  [0-5]) calistir_asama "$1"; exit ;;
  rapor) bash ./rapor.sh; exit ;;
  geri-al) bash ./geri-al.sh "${@:2}"; exit ;;
esac

while true; do
  printf '\n%sUbuntu çalışma istasyonu%s — ASUS TUF A15 · %s\n\n' "$R_KALIN" "$R_SIFIR" "$(. /etc/os-release; echo "$PRETTY_NAME")"
  for i in "${!asamalar[@]}"; do
    printf '  %d) %s\n' "$i" "${asamalar[$i]#*|}"
  done
  printf '  h) Hepsini sırayla çalıştır\n  r) Rapor: neler değişti?\n  g) Geri al (kurulum öncesine dön)\n  q) Çıkış\n\n'
  read -r -p "Seçimin: " secim </dev/tty || exit 0
  case $secim in
    [0-5]) calistir_asama "$secim" ;;
    h) hepsi ;;
    r) bash ./rapor.sh ;;
    g) bash ./geri-al.sh ;;
    q|"") exit 0 ;;
    *) uyari "Geçersiz seçim." ;;
  esac
done
