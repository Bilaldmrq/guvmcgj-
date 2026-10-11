#!/usr/bin/env bash
# 3. AŞAMA — SİSTEM: NVIDIA sürücüsü, hibrit grafik, güç profilleri, ASUS, güvenlik güncellemeleri, açılış hızı.
# GRUB'a, /etc/default/grub'a, fstab'a ve Windows bölümüne DOKUNMAZ.
set -uo pipefail
# shellcheck source=lib/ortak.sh
source "$(dirname "$0")/lib/ortak.sh"

ortam_kontrol
gunluk_baslat sistem

asama_ozeti "3/5 SİSTEM" "sürücü kurulumu, servis ayarları ve otomatik güncelleme yapılandırması için" \
  "NVIDIA: sürücü çalışıyor mu bakacağım; çalışmıyorsa Ubuntu'nun önerdiği (imzalı) sürücüyü kurmayı soracağım" \
  "Hibrit grafik: 'on-demand' kipi (ekran AMD iGPU'da, RTX 3050 yalnızca gerektiğinde → pil dostu)" \
  "Güç profilleri: GNOME güç kipleri (TuneD ya da power-profiles-daemon) çalışıyor mu, TLP gibi çakışan araç var mı, ASUS fan kipleriyle eşleşiyor mu" \
  "Pil ömrü: %80 şarj sınırı (isteğe bağlı)" \
  "Otomatik güvenlik güncellemeleri (unattended-upgrades) — otomatik yeniden başlatma YOK" \
  "Açılışı yavaşlatan gereksiz servisleri tek tek sorarak kapatma (silme değil; geri alınabilir)" \
  "GRUB / açılış menüsü ve Windows bölümü: DOKUNULMAYACAK"
onay "Sistem aşaması başlasın mı?" e || { bilgi "Atlandı."; exit 0; }

yedek_gerekli
sudo_hazirla "sürücü, servis ve güncelleme ayarları için" || exit 1

# ---------------------------------------------------------------------------
nvidia() {
  if ! lspci 2>/dev/null | grep -qi 'nvidia'; then
    uyari "NVIDIA ekran kartı görülmedi (BIOS'ta kapalı olabilir)."
    return 0
  fi
  if komut_var nvidia-smi && nvidia-smi >/dev/null 2>&1; then
    basarili "NVIDIA sürücüsü çalışıyor: $(nvidia-smi --query-gpu=name,driver_version --format=csv,noheader 2>/dev/null)"
  else
    uyari "NVIDIA sürücüsü yüklü değil ya da çalışmıyor."
    komut_var ubuntu-drivers || apt_kur ubuntu-drivers-common
    bilgi "Ubuntu'nun önerdiği sürücüler:"
    ubuntu-drivers list 2>/dev/null | sed 's/^/    /'
    if komut_var mokutil && mokutil --sb-state 2>/dev/null | grep -qi enabled; then
      not_yaz "Secure Boot açık. Ubuntu'nun hazır imzalı sürücü modülleri kullanılacağı için ek işlem gerekmez;"
      not_yaz "kurulum bir 'MOK' şifresi isterse, yeniden başlatınca mavi ekranda 'Enroll MOK' seçip aynı şifreyi gir."
    fi
    if onay "Önerilen NVIDIA sürücüsü kurulsun mu? (ubuntu-drivers install; ardından yeniden başlatma gerekir)" e; then
      sudo ubuntu-drivers install && kaydet bilgi nvidia "Önerilen NVIDIA sürücüsü kuruldu (yeniden başlatma gerekli)"
      YENIDEN_BASLAT=1
    fi
  fi

  # Hibrit grafik kipi
  if komut_var prime-select; then
    local kip; kip=$(prime-select query 2>/dev/null)
    if [[ $kip != on-demand ]]; then
      bilgi "Şu anki PRIME kipi: ${kip:-bilinmiyor}"
      if onay "'on-demand' kipine geçilsin mi? (önerilen: pil ömrü + gerektiğinde tam GPU)" e; then
        sudo prime-select on-demand && kaydet prime "${kip:-on-demand}" "PRIME kipi: ${kip:-?} → on-demand"
        YENIDEN_BASLAT=1
      fi
    else
      basarili "PRIME kipi zaten on-demand."
    fi
  fi
  # GNOME'da sağ tık → "Harici Ekran Kartıyla Başlat" menüsü için
  apt_kur switcheroo-control
  systemctl is-active --quiet switcheroo-control || sudo systemctl enable --now switcheroo-control

  # Uyku/uyanma sırasında GPU belleğini koruyan servisler (sürücüyle gelir)
  local s
  for s in nvidia-suspend nvidia-resume nvidia-hibernate; do
    if systemctl list-unit-files "$s.service" --no-legend 2>/dev/null | grep -q .; then
      systemctl is-enabled --quiet "$s.service" || { sudo systemctl enable "$s.service" && kaydet bilgi nvidia "$s.service etkinleştirildi"; }
    fi
  done
  local guc
  guc=$(cat /proc/driver/nvidia/gpus/*/power 2>/dev/null | grep -i 'Runtime D3 status' | head -1)
  [[ -n $guc ]] && not_yaz "GPU güç yönetimi: ${guc#*:}"
  return 0
}

guc_profilleri() {
  local p
  for p in tlp auto-cpufreq laptop-mode-tools; do
    if paket_kurulu "$p"; then
      uyari "$p kurulu: GNOME'un güç profilleriyle (TuneD / power-profiles-daemon) çakışır."
      if onay "$p kaldırılsın mı? (önerilen)" e; then
        sudo apt-get remove -y "$p" && kaydet paket_kaldirildi "$p" "güç yönetimi çakışması"
      fi
    fi
  done
  # Ubuntu 25.10+ güç profillerini TuneD (tuned-ppd) ile, öncekiler power-profiles-daemon ile yönetir.
  # İkisi birbirinin yerine geçer; yanlış olanı kurmak diğerini kaldırır → yalnızca eksikse kur.
  if paket_kurulu tuned-ppd; then
    systemctl is-active --quiet tuned 2>/dev/null || sudo systemctl enable --now tuned
    basarili "Güç profilleri TuneD (tuned-ppd) ile yönetiliyor (Ubuntu'nun varsayılanı)."
    komut_var tuned-adm && not_yaz "Etkin TuneD profili: $(tuned-adm active 2>/dev/null | sed 's/^[^:]*: *//')"
  elif paket_kurulu power-profiles-daemon; then
    systemctl is-active --quiet power-profiles-daemon || sudo systemctl enable --now power-profiles-daemon
    basarili "Güç profilleri power-profiles-daemon ile yönetiliyor."
  else
    uyari "Güç profili servisi yok; Ubuntu'nun önerdiği kuruluyor."
    if paket_depoda tuned-ppd; then apt_kur tuned-ppd; else apt_kur power-profiles-daemon; fi || return 1
  fi
  if komut_var powerprofilesctl; then
    bilgi "Güç profilleri (Hızlı Ayarlar menüsünden değiştirilebilir):"
    powerprofilesctl list 2>/dev/null | sed 's/^/    /'
  else
    not_yaz "Güç kipini Hızlı Ayarlar menüsünden (sağ üst) seçebilirsin: Güç Tasarrufu / Dengeli / Performans."
  fi

  if [[ -r /sys/firmware/acpi/platform_profile_choices ]]; then
    basarili "ASUS fan/performans kipleri çekirdek tarafından destekleniyor: $(cat /sys/firmware/acpi/platform_profile_choices)"
    not_yaz "Şu anki fan kipi: $(cat /sys/firmware/acpi/platform_profile 2>/dev/null)"
    not_yaz "Hızlı Ayarlar'dan güç kipini değiştirince bu değer de değişmeli (quiet/low-power = Sessiz, balanced = Dengeli, performance = Turbo)."
    not_yaz "Fn+F5 tuşu da kipler arasında geçiş yapar."
  fi
}

sarj_siniri() {
  local esik
  esik=$(ls /sys/class/power_supply/BAT*/charge_control_end_threshold 2>/dev/null | head -1)
  [[ -z $esik ]] && { not_yaz "Pil şarj sınırı bu cihazda desteklenmiyor."; return 0; }
  basarili "Pil şarj sınırı destekleniyor (şu an: %$(cat "$esik"))."
  not_yaz "Laptop çoğunlukla prizdeyse %80 sınırı pilin ömrünü belirgin uzatır."
  not_yaz "GNOME'da Ayarlar > Güç > 'Pil Sağlığını Koru' seçeneği görünüyorsa onu kullanmak yeterli."
  if onay "%80 şarj sınırı her açılışta otomatik uygulansın mı?" h; then
    local servis=/etc/systemd/system/pil-sarj-siniri.service
    dosya_yedekle "$servis"
    sudo tee "$servis" >/dev/null <<'EOF'
[Unit]
Description=Pil şarj sınırını %%80'e ayarla (ASUS)
After=multi-user.target suspend.target hibernate.target
StartLimitBurst=0

[Service]
Type=oneshot
Restart=on-failure
ExecStart=/bin/sh -c 'for f in /sys/class/power_supply/BAT*/charge_control_end_threshold; do echo 80 > "$$f"; done'

[Install]
WantedBy=multi-user.target suspend.target hibernate.target
EOF
    sudo systemctl daemon-reload
    sudo systemctl enable --now pil-sarj-siniri.service && kaydet servis_eklendi pil-sarj-siniri.service "%80 pil şarj sınırı"
  fi
}

asus_onerisi() {
  printf '\n'
  bilgi "ASUS için araç önerisi"
  not_yaz "Temel ihtiyaçlar (fan kipleri, şarj sınırı) yukarıdaki gibi çekirdek + GNOME ile ek yazılımsız karşılanıyor."
  not_yaz "Özel fan eğrisi, klavye RGB ve 'Armoury Crate' benzeri ayarlar istersen: asusctl (asus-linux.org)."
  not_yaz "  • Ubuntu için resmî paketi yok; kaynak koddan derlenir. Ancak ihtiyaç duyarsan kurmanı öneririm."
  not_yaz "  • supergfxctl'yi KURMA: Ubuntu'nun prime-select/switcheroo düzeniyle çakışır."
}

guvenlik_guncellemeleri() {
  apt_kur unattended-upgrades || return 1
  local dosya=/etc/apt/apt.conf.d/20auto-upgrades
  dosya_yedekle "$dosya"
  sudo tee "$dosya" >/dev/null <<'EOF'
// ubuntu-istasyon: günlük paket listesi güncellemesi + otomatik güvenlik güncellemeleri
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF
  if grep -Eq '^\s*"\$\{distro_id\}:\$\{distro_codename\}-security"' /etc/apt/apt.conf.d/50unattended-upgrades 2>/dev/null; then
    basarili "Otomatik güvenlik güncellemeleri açık (yalnızca -security deposu; otomatik yeniden başlatma yok)."
  else
    uyari "50unattended-upgrades içinde güvenlik deposu satırı bulunamadı; dosyayı kontrol et."
  fi
  systemctl is-enabled --quiet apt-daily-upgrade.timer || sudo systemctl enable --now apt-daily-upgrade.timer
}

# servis|varsayılan cevap|açıklama
SERVIS_ADAYLARI=(
  "NetworkManager-wait-online.service|e|Açılışı ağ bağlanana kadar bekletir; masaüstünde gereksiz (en sık açılış yavaşlatıcısı)"
  "systemd-networkd-wait-online.service|e|Kullanılmayan networkd için ağ bekleme; açılışı 2 dakikaya kadar uzatabilir"
  "ModemManager.service|e|3G/4G modem yöneticisi; laptopta SIM/modem yoksa gereksiz"
  "cups-browsed.service|e|Ağdaki yazıcıları otomatik arar; geçmişte güvenlik açıkları çıktı (yazdırma yine çalışır)"
  "kerneloops.service|e|Çekirdek hata raporlarını gönderir"
  "whoopsie.service|e|Ubuntu çökme raporlarını gönderir"
  "apport.service|h|Çökme raporu toplayıcı (sorun giderirken işe yarar)"
  "docker.service|e|Docker'ı her açılışta başlatma; ilk 'docker' komutunda kendiliğinden başlar (docker.socket)"
  "containerd.service|e|Docker'ın alt servisi; Docker başlayınca o da başlar"
)

acilis_hizi() {
  bilgi "Şu anki açılış süresi:"
  systemd-analyze 2>/dev/null | sed 's/^/    /'
  bilgi "En çok zaman alan 10 birim:"
  systemd-analyze blame 2>/dev/null | head -10 | sed 's/^/    /'
  printf '\n'
  not_yaz "Servisler 'disable' ile yalnızca açılışta başlatılmaz; silinmez ve geri-al.sh ile yeniden açılır."
  local satir servis varsayilan aciklama
  for satir in "${SERVIS_ADAYLARI[@]}"; do
    IFS='|' read -r servis varsayilan aciklama <<<"$satir"
    systemctl is-enabled --quiet "$servis" 2>/dev/null || continue
    if [[ $servis == docker.service || $servis == containerd.service ]]; then
      systemctl list-unit-files docker.socket --no-legend 2>/dev/null | grep -q . || continue
    fi
    printf '\n  %s%s%s\n  %s\n' "$R_KALIN" "$servis" "$R_SIFIR" "$aciklama"
    if onay "  Açılışta başlatılmasın mı?" "$varsayilan"; then
      sudo systemctl disable "$servis" && kaydet servis "$servis" "açılışta başlatılmıyor"
      [[ $servis == docker.service ]] && sudo systemctl enable docker.socket
    fi
  done

  printf '\n'
  bilgi "Oturum açılışında başlayan uygulamalar (bilgi; değiştirmedim):"
  local f ad
  for f in /etc/xdg/autostart/*.desktop "$HOME"/.config/autostart/*.desktop; do
    [[ -f $f ]] || continue
    grep -qiE '^(Hidden|NoDisplay)=true' "$f" && continue
    ad=$(grep -m1 '^Name=' "$f" | cut -d= -f2-)
    printf '    %-40s %s\n' "${ad:-?}" "${f/#$HOME/\~}"
  done
  not_yaz "İstemediğini Ayarlar > Uygulamalar > (uygulama) > 'Oturum açınca başlat' ile kapatabilirsin."
  not_yaz "Not: GRUB bekleme süresine özellikle dokunmadım (Windows seçimi için menü kalmalı)."
}

YENIDEN_BASLAT=0
adim "NVIDIA sürücüsü ve hibrit grafik" nvidia
adim "Güç profilleri" guc_profilleri
adim "Pil şarj sınırı (isteğe bağlı)" sarj_siniri
asus_onerisi
adim "Otomatik güvenlik güncellemeleri" guvenlik_guncellemeleri
adim "Açılış hızı" acilis_hizi

asama_sonu "Sistem aşaması"
((YENIDEN_BASLAT)) && uyari "Sürücü/grafik değişikliği yapıldı: bilgisayarı YENİDEN BAŞLAT."
