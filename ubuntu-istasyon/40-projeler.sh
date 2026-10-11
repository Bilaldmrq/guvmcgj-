#!/usr/bin/env bash
# 4. AŞAMA — ÇALIŞMA ALANI: kod yedeğini ~/Projeler altına düzenli açar, sanal ortamları kurar ve test eder.
#
#   bash 40-projeler.sh                       → zip'i İndirilenler/Masaüstü/ev klasöründe kendisi bulur
#   bash 40-projeler.sh ~/yol/kod_yedek.zip   → belirli bir zip
set -uo pipefail
# shellcheck source=lib/ortak.sh
source "$(dirname "$0")/lib/ortak.sh"

ortam_kontrol
gunluk_baslat projeler

PROJELER="${PROJELER:-$HOME/Projeler}"

asama_ozeti "4/5 ÇALIŞMA ALANI" "" \
  "kod_yedek_*.zip dosyasını bulacağım (yoksa Google Drive'ı tarayıcıda açıp indirmeni bekleyeceğim)" \
  "Zip'i güvenli şekilde açacağım: Türkçe dosya adları ve Windows ters bölüleri düzeltilir; Windows sanal ortamları, __pycache__, node_modules açılmaz" \
  "Projeleri sınıflandırıp ~/Projeler altına yerleştireceğim: Kanallar/ · Otomasyon/ · Yazilim/ · Diger/ (önce planı gösterip onay alacağım, istersen düzenlersin)" \
  "Her proje için Linux sanal ortamı kuracağım (uv ile; Windows'taki .venv / .venv-asr adları ve Python sürümü korunur, eksik paketler Windows kaydından tamamlanır)" \
  "Test: sözdizimi + tüm bağımlılıkların içe aktarılması + GPU (torch / faster-whisper) + edge-tts → ffmpeg örnek video" \
  "Windows'a özgü kod satırlarını (C:\\ yolları, .exe, PowerShell…) bulup rapora yazacağım; kodunu DEĞİŞTİRMEYECEĞİM" \
  "Projelerin kendi betiklerini ÇALIŞTIRMAYACAĞIM (yanlışlıkla video yüklenmesin / API harcanmasın)" \
  "Mevcut ~/Projeler içeriğinin üzerine YAZMAYACAĞIM"
onay "Çalışma alanı aşaması başlasın mı?" e || { bilgi "Atlandı."; exit 0; }

# --- uv ----------------------------------------------------------------------
export PATH="$HOME/.local/bin:$PATH"
if ! komut_var uv; then
  if komut_var pipx; then
    bilgi "uv kuruluyor (pipx, kullanıcı düzeyinde; sudo gerekmez)…"
    pipx install uv && kaydet pipx_kuruldu uv "pipx ile kuruldu"
  else
    hata "uv ve pipx yok. Önce 2. aşamayı (programlar) çalıştır: bash $ISTASYON_DIZIN/20-programlar.sh"
    exit 1
  fi
fi

# --- zip'i bul ------------------------------------------------------------------
zip_bul() {
  local d indir
  indir=$(xdg-user-dir DOWNLOAD 2>/dev/null || true)
  for d in "$indir" "$HOME/İndirilenler" "$HOME/Downloads" "$HOME/Masaüstü" "$HOME/Desktop" "$HOME"; do
    [[ -n $d && -d $d ]] || continue
    find "$d" -maxdepth 1 -type f -iname 'kod_yedek_*.zip' -printf '%T@\t%p\n' 2>/dev/null
  done | sort -rn | head -1 | cut -f2-
}

ZIP="${1:-}"
[[ -z $ZIP ]] && ZIP=$(zip_bul)
if [[ -z $ZIP || ! -f $ZIP ]]; then
  uyari "kod_yedek_*.zip bulunamadı (İndirilenler, Masaüstü ve ev klasörüne baktım)."
  not_yaz "Google Drive'dan 'kod_yedek_2026-10-11.zip' dosyasını İndirilenler klasörüne indir."
  if onay "Google Drive'da aramayı tarayıcıda açayım mı?" e; then
    xdg-open "https://drive.google.com/drive/search?q=kod_yedek" >/dev/null 2>&1 &
  fi
  [[ $ISTASYON_OTOMATIK == 1 ]] && exit 1
  read -r -p "İndirme bitince Enter'a bas (vazgeçmek için Ctrl+C)… " _ </dev/tty
  ZIP=$(zip_bul)
  [[ -n $ZIP && -f $ZIP ]] || { hata "Zip hâlâ bulunamadı. Yolunu vererek çalıştır: bash $0 /yol/kod_yedek.zip"; exit 1; }
fi
basarili "Yedek: $ZIP ($(du -h "$ZIP" | cut -f1))"

# --- asıl iş (Python) ---------------------------------------------------------------
python3 -I "$ISTASYON_DIZIN/lib/projeler.py" --zip "$ZIP" --hedef "$PROJELER" --uv "$(command -v uv)"
DURUM=$?

if [[ -f $PROJELER/.son-kurulum.json ]] && ((DURUM == 0)); then
  OZET=$(python3 -I -c 'import json,sys; v=json.load(open(sys.argv[1])); print(", ".join(v["projeler"]))' "$PROJELER/.son-kurulum.json")
  kaydet bilgi projeler "$ZIP → $PROJELER: $OZET"
  kaydet bilgi projeler "Rapor: $PROJELER/PROJELER_RAPORU.md"
  printf '\n'
  basarili "Çalışma alanı hazır: $PROJELER"
  not_yaz "Ayrıntılı rapor (ortamlar, testler, Linux uyumluluk bulguları): $PROJELER/PROJELER_RAPORU.md"
  not_yaz "Bir projede çalışmak için: cd ~/Projeler/Kanallar/<proje> && source .venv/bin/activate"
fi
exit $DURUM
