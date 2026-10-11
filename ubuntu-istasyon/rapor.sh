#!/usr/bin/env bash
# Yapılan değişikliklerin kısa raporu (~/ayar_yedek/degisiklikler.log'dan üretilir).
set -uo pipefail
# shellcheck source=lib/ortak.sh
source "$(dirname "$0")/lib/ortak.sh"

[[ -f $DEGISIKLIK_LOG ]] || { uyari "Henüz kayıtlı değişiklik yok ($DEGISIKLIK_LOG)."; exit 0; }
RAPOR="$YEDEK_KOK/RAPOR.md"

# grup başlığı | tür(ler) | değer filtresi (regex, boş = hepsi)
bolum() {
  local baslik=$1 turler=$2 filtre=${3:-} satirlar
  satirlar=$(awk -F'|' -v t="$turler" -v f="$filtre" '
    BEGIN { n = split(t, T, ","); for (i = 1; i <= n; i++) ok[T[i]] = 1 }
    ok[$2] && (f == "" || $3 ~ f) {
      anahtar = $2 "|" $3
      if (!(anahtar in gorulen)) { gorulen[anahtar] = 1; sira[++k] = anahtar; metin[anahtar] = $4 }
      else metin[anahtar] = $4
    }
    END { for (i = 1; i <= k; i++) { split(sira[i], a, "|"); printf "- %s — %s\n", a[2], metin[sira[i]] } }
  ' "$DEGISIKLIK_LOG")
  [[ -z $satirlar ]] && return
  printf '\n## %s\n%s\n' "$baslik" "$satirlar"
}

{
  printf '# Ubuntu çalışma istasyonu — değişiklik raporu\n'
  printf '_Oluşturma: %s · İlk yedek: %s_\n' "$(date '+%Y-%m-%d %H:%M')" "$(cat "$YEDEK_KOK/ilk-yedek-zamani.txt" 2>/dev/null || echo '?')"
  bolum "Görünüm" ayar 'org\.gnome\.desktop\.(interface|background|screensaver|wm)|org\.gtk'
  bolum "Dock" ayar 'dash-to-dock|favorite-apps'
  bolum "GNOME eklentileri" "eklenti,ayar" '^[^ ]+@|org\.gnome\.shell (enabled|disabled)-extensions|disable-user-extensions'
  bolum "Güç / pencere davranışı" ayar 'org\.gnome\.(settings-daemon|mutter|desktop\.peripherals)'
  bolum "Kurulan programlar" "paket_kuruldu,pipx_kuruldu"
  bolum "Eklenen yazılım depoları" depo
  bolum "Kaldırılan uygulamalar" "paket_kaldirildi,snap_kaldirildi"
  bolum "Sistem" "servis,servis_eklendi,prime,grup"
  bolum "Değiştirilen dosyalar (ilk halleri yedekte)" dosya
  bolum "Projeler" bilgi '^projeler$'
  bolum "Notlar" bilgi '^(git|vscode|nvidia|imleç|yedek)$'
  printf '\n---\nGeri almak için: `bash ~/ayar_yedek/geri-al.sh` · Yalnızca görünüm: `bash ~/ayar_yedek/geri-al.sh --sadece-ayarlar`\n'
} >"$RAPOR"

cat "$RAPOR"
printf '\n'
basarili "Rapor kaydedildi: $RAPOR"
