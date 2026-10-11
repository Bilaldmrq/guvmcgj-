#!/usr/bin/env bash
# 1. AŞAMA — GÖRÜNÜM: koyu tema, simge/imleç seti, yazı tipleri, duvar kâğıdı, dock, eklentiler.
set -uo pipefail
# shellcheck source=lib/ortak.sh
source "$(dirname "$0")/lib/ortak.sh"

ortam_kontrol
gnome_kontrol || exit 1
gunluk_baslat gorunum

asama_ozeti "1/5 GÖRÜNÜM" "yazı tipi, simge, imleç ve GNOME eklenti paketlerini apt ile kurmak için" \
  "Koyu stil + mavi vurgu rengi (Ubuntu'nun kendi Yaru koyu teması; üçüncü parti tema yok, güncellemelerde bozulmaz)" \
  "Simgeler: Papirus-Dark · İmleç: Bibata Modern Classic" \
  "Yazı tipleri: arayüz Inter, kod/terminal JetBrains Mono" \
  "Duvar kâğıdı: koyu, sade (assets/istasyon-koyu.jpg) — kilit ekranı dahil" \
  "Dock: altta, ortalı, otomatik gizlenen; çöp kutusu ve disk simgeleri gizli" \
  "Eklentiler: pano geçmişi (Clipboard Indicator), sistem durumu (Vitals: CPU/GPU ısı, RAM, fan), Caffeine (isteğe bağlı)" \
  "Masaüstü simgelerini gizleme (isteğe bağlı), pil yüzdesi, gün adı, yeni pencereler ortada" \
  "Prize takılıyken otomatik uyku kapalı (uzun video çıktısı yarıda kesilmesin; pildeyken değişmez)"
onay "Görünüm aşaması başlasın mı?" e || { bilgi "Atlandı."; exit 0; }

yedek_gerekli

# ---------------------------------------------------------------------------
paketler() {
  sudo_hazirla "yazı tipi, simge, imleç ve eklenti paketleri (apt)" || return 1
  apt_kur fonts-inter fonts-jetbrains-mono papirus-icon-theme bibata-cursor-theme \
          gnome-shell-extensions gnome-shell-extension-manager gnome-tweaks
  fc-cache -f >/dev/null 2>&1
  return 0
}

bibata_yedek_indir() {
  # Depoda bibata yoksa resmi GitHub sürümünden kullanıcı klasörüne kurar (sudo gerekmez).
  local surum="v2.0.7" hedef="$HOME/.local/share/icons" gecici
  gecici=$(mktemp -d)
  curl -fL --retry 3 -o "$gecici/bibata.tar.xz" \
    "https://github.com/ful1e5/Bibata_Cursor/releases/download/$surum/Bibata-Modern-Classic.tar.xz" || { rm -rf "$gecici"; return 1; }
  mkdir -p "$hedef"
  tar -xJf "$gecici/bibata.tar.xz" -C "$hedef" && kaydet bilgi "imleç" "Bibata Modern Classic → $hedef"
  rm -rf "$gecici"
}

tema_dizini_var() { [[ -d /usr/share/themes/$1 || -d $HOME/.local/share/themes/$1 || -d $HOME/.themes/$1 ]]; }
simge_dizini_var() { [[ -d /usr/share/icons/$1 || -d $HOME/.local/share/icons/$1 || -d $HOME/.icons/$1 ]]; }

tema() {
  local I=org.gnome.desktop.interface aday
  gset $I color-scheme "'prefer-dark'"
  gset $I accent-color "'blue'" || true          # GNOME 47+
  for aday in Yaru-blue-dark Yaru-dark; do
    if tema_dizini_var "$aday"; then gset $I gtk-theme "'$aday'"; break; fi
  done
  if simge_dizini_var Papirus-Dark; then gset $I icon-theme "'Papirus-Dark'"
  else uyari "Papirus-Dark bulunamadı; simge teması değiştirilmedi."; fi

  simge_dizini_var Bibata-Modern-Classic || bibata_yedek_indir || uyari "Bibata imleci indirilemedi."
  if simge_dizini_var Bibata-Modern-Classic; then
    gset $I cursor-theme "'Bibata-Modern-Classic'"
    gset $I cursor-size 24
  fi
}

yazi_tipleri() {
  local I=org.gnome.desktop.interface arayuz="Inter" kod="JetBrains Mono"
  if ! fc-list : family | grep -qE '^Inter(,|$)'; then
    if fc-list : family | grep -qE '^Inter Variable(,|$)'; then arayuz="Inter Variable"
    else uyari "Inter yazı tipi bulunamadı."; return 1; fi
  fi
  fc-list : family | grep -qE "^$kod(,|$)" || { uyari "JetBrains Mono bulunamadı."; return 1; }
  gset $I font-name "'$arayuz 11'"
  gset $I document-font-name "'$arayuz 11'"
  gset $I monospace-font-name "'$kod 11'"
  gset org.gnome.desktop.wm.preferences titlebar-font "'$arayuz Bold 11'"
}

duvar_kagidi() {
  local kaynak="$ISTASYON_DIZIN/assets/istasyon-koyu.jpg" hedef="$HOME/.local/share/backgrounds/istasyon-koyu.jpg"
  [[ -f $kaynak ]] || { hata "Duvar kâğıdı dosyası yok: $kaynak"; return 1; }
  mkdir -p "$(dirname "$hedef")"
  cp "$kaynak" "$hedef"
  local B=org.gnome.desktop.background
  gset $B picture-uri "'file://$hedef'"
  gset $B picture-uri-dark "'file://$hedef'"
  gset $B picture-options "'zoom'"
  gset $B primary-color "'#0b0e15'"
  gset org.gnome.desktop.screensaver picture-uri "'file://$hedef'"
}

dock() {
  local D=org.gnome.shell.extensions.dash-to-dock
  if ! gsettings list-schemas | grep -qx "$D"; then
    uyari "Ubuntu Dock ayarları bulunamadı (dock devre dışı olabilir)."
    return 1
  fi
  gset $D dock-position "'BOTTOM'"
  gset $D extend-height false          # tüm kenarı kaplamasın → ortalı
  gset $D dock-fixed false             # otomatik gizle
  gset $D autohide true
  gset $D intellihide true             # pencere üstüne gelince gizlen
  gset $D autohide-in-fullscreen false
  gset $D dash-max-icon-size 42
  gset $D show-trash false
  gset $D show-mounts false            # Windows bölümü vb. disk simgeleri dock'ta görünmesin
  gset $D click-action "'minimize-or-previews'"
  gset $D scroll-action "'cycle-windows'"
  gset $D transparency-mode "'DYNAMIC'"
  gset $D running-indicator-style "'DOTS'"
  gset $D custom-theme-shrink true
  gset $D multi-monitor false
}

# GVariant dizisine öğe ekler/çıkarır (enabled-extensions gibi listeler için)
liste_duzenle() {
  local sema=$1 anahtar=$2 islem=$3 oge=$4 yeni
  gsetting_var "$sema" "$anahtar" || return 1
  yeni=$(python3 -I - "$(gsettings get "$sema" "$anahtar")" "$islem" "$oge" <<'PY'
import ast, sys
ham, islem, oge = sys.argv[1:4]
if ham.startswith("@as "):
    ham = ham[4:]
liste = ast.literal_eval(ham)
if islem == "ekle" and oge not in liste:
    liste.append(oge)
elif islem == "cikar":
    liste = [x for x in liste if x != oge]
print("[" + ", ".join("'%s'" % x for x in liste) + "]")
PY
) || return 1
  gset "$sema" "$anahtar" "$yeni"
}

eklenti_ac() {
  local uuid=$1
  liste_duzenle org.gnome.shell disabled-extensions cikar "$uuid"
  liste_duzenle org.gnome.shell enabled-extensions ekle "$uuid"
  gnome-extensions enable "$uuid" 2>/dev/null || not_yaz "$uuid oturum yeniden açılınca etkinleşecek."
}

eklenti_kapat() {
  local uuid=$1
  liste_duzenle org.gnome.shell enabled-extensions cikar "$uuid"
  liste_duzenle org.gnome.shell disabled-extensions ekle "$uuid"
  gnome-extensions disable "$uuid" 2>/dev/null || true
}

# extensions.gnome.org'dan, çalışan GNOME sürümüne uygun eklentiyi kurar.
# GNOME kendi onay penceresini gösterir; onay verilmezse kurulmaz.
ego_kur() {
  local uuid=$1 ad=$2 sonuc
  if gnome-extensions info "$uuid" >/dev/null 2>&1; then
    basarili "$ad zaten kurulu."
    eklenti_ac "$uuid"
    return 0
  fi
  bilgi "$ad kuruluyor — ekranda açılacak pencerede 'Yükle'ye bas."
  sonuc=$(timeout 180 gdbus call --session --dest org.gnome.Shell.Extensions \
            --object-path /org/gnome/Shell/Extensions \
            --method org.gnome.Shell.Extensions.InstallRemoteExtension "$uuid" 2>&1) || true
  if [[ $sonuc == *successful* ]]; then
    kaydet eklenti "$uuid" "$ad (extensions.gnome.org)"
    eklenti_ac "$uuid"
    basarili "$ad kuruldu."
    return 0
  fi
  uyari "$ad kurulamadı: ${sonuc:-yanıt yok}"
  return 1
}

eklentiler() {
  gset org.gnome.shell disable-user-extensions false

  # Pano geçmişi
  if ! ego_kur clipboard-indicator@tudmotu.com "Clipboard Indicator (pano geçmişi)"; then
    bilgi "Yedek seçenek: Ubuntu deposundaki GPaste."
    apt_kur gnome-shell-extension-gpaste && eklenti_ac GPaste@gnome-shell-extensions.gnome.org
  fi

  # Sistem durumu
  if ! ego_kur Vitals@CoreCoding.com "Vitals (CPU/GPU sıcaklık, RAM, fan, ağ)"; then
    bilgi "Yedek seçenek: GNOME'un resmî System Monitor eklentisi."
    eklenti_ac system-monitor@gnome-shell-extensions.gcampax.github.com
  fi

  if onay "Caffeine eklentisi kurulsun mu? (hızlı ayarlara tek düğme: render/yükleme sırasında ekran kararmasın)" e; then
    ego_kur caffeine@patapon.info "Caffeine"
  fi

  # Masaüstü simgeleri (Ubuntu'nun DING eklentisi)
  if gnome-extensions info ding@rastersoft.com >/dev/null 2>&1 &&
     onay "Masaüstündeki simgeler gizlensin mi? (sade görünüm; dosyalar yerinde kalır)" e; then
    eklenti_kapat ding@rastersoft.com
  fi
  return 0
}

kucuk_ayarlar() {
  local I=org.gnome.desktop.interface
  gset $I show-battery-percentage true
  gset $I clock-show-weekday true
  gset org.gnome.mutter center-new-windows true
  gset org.gnome.desktop.peripherals.touchpad tap-to-click true
  gset org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type "'nothing'"
  gset org.gtk.gtk4.Settings.FileChooser sort-directories-first true
  gset org.gtk.Settings.FileChooser sort-directories-first true
  return 0
}

adim "Paketler (yazı tipi, simge, imleç, eklenti araçları)" paketler
adim "Koyu tema, simge ve imleç" tema
adim "Yazı tipleri" yazi_tipleri
adim "Duvar kâğıdı" duvar_kagidi
adim "Dock" dock
adim "GNOME eklentileri" eklentiler
adim "Küçük ayarlar" kucuk_ayarlar

asama_sonu "Görünüm aşaması"
not_yaz "Bazı değişiklikler (yeni sistem eklentileri, imleç) oturumu kapatıp açınca tam görünür."
not_yaz "Eklentileri daha sonra 'Eklenti Yöneticisi' (Extension Manager) uygulamasından yönetebilirsin."
