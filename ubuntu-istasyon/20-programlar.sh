#!/usr/bin/env bash
# 2. AŞAMA — PROGRAMLAR: Chrome, VS Code, OBS, VLC, GIMP, Docker, Node.js, Python araçları, ffmpeg, git.
set -uo pipefail
# shellcheck source=lib/ortak.sh
source "$(dirname "$0")/lib/ortak.sh"

ortam_kontrol
gunluk_baslat programlar

asama_ozeti "2/5 PROGRAMLAR" "programları apt ile kurmak ve Docker deposunu eklemek için" \
  "Ubuntu deposundan: VLC, GIMP, ffmpeg, git + git-lfs, Node.js + npm, Python (venv, pip, pipx, geliştirme başlıkları), derleme araçları" \
  "Yardımcılar: curl, jq, unzip/7z, htop, btop, nvtop (GPU izleme), ripgrep, fd, tree, mediainfo, imagemagick" \
  "OBS Studio: resmî OBS PPA'sı bu sürümü destekliyorsa oradan, yoksa Ubuntu deposundan (v4l2loopback-dkms hariç: Secure Boot'ta MOK kaydı isteyip açılışa dokunmasın diye)" \
  "Google Chrome ve VS Code: üreticilerin resmî .deb paketleri (kendi güncelleme depolarını kendileri ekler)" \
  "Docker Engine + Compose: Docker'ın resmî deposu (bu Ubuntu sürümünü desteklemiyorsa Ubuntu'nun docker.io paketi)" \
  "pipx ile kullanıcıya: uv (hızlı Python ortam yöneticisi), yt-dlp, edge-tts" \
  "VS Code: JetBrains Mono yazı tipi + koyu tema ayarı; isteğe bağlı Python/Docker eklentileri" \
  "Dock'taki sık kullanılanlar: Dosyalar, Chrome, VS Code, Terminal, OBS, GIMP, VLC" \
  "Soracaklarım: docker grubuna ekleme, NVIDIA Container Toolkit, git kullanıcı adı/e-posta"
onay "Programlar aşaması başlasın mı?" e || { bilgi "Atlandı."; exit 0; }

yedek_gerekli
sudo_hazirla "programları kurmak için (apt)" || exit 1

KOD_ADI=$(ubuntu_kod_adi)
MIMARI=$(dpkg --print-architecture)
GECICI=$(mktemp -d)
chmod 755 "$GECICI"   # apt'nin _apt kullanıcısı .deb dosyasını okuyabilsin
trap 'rm -rf "$GECICI"; kill "${SUDO_CANLI_PID:-}" 2>/dev/null' EXIT

# ---------------------------------------------------------------------------
temel_paketler() {
  apt_kur ca-certificates curl wget gnupg software-properties-common \
          vlc gimp ffmpeg git git-lfs \
          nodejs npm \
          python3 python3-venv python3-pip python3-dev python3-tk pipx build-essential pkg-config \
          jq unzip p7zip-full htop btop nvtop tree ripgrep fd-find mediainfo imagemagick
}

obs_kur() {
  if paket_kurulu obs-studio; then basarili "OBS Studio zaten kurulu."; return 0; fi
  if depo_surumu_destekliyor "https://ppa.launchpadcontent.net/obsproject/obs-studio/ubuntu" "$KOD_ADI"; then
    bilgi "Resmî OBS PPA'sı $KOD_ADI sürümünü destekliyor; ekleniyor."
    sudo add-apt-repository -y ppa:obsproject/obs-studio && kaydet depo "ppa:obsproject/obs-studio" "OBS resmî PPA"
    APT_GUNCEL=0
  else
    not_yaz "OBS PPA'sı henüz $KOD_ADI için yok; Ubuntu deposundaki sürüm kurulacak."
  fi
  apt_kur obs-studio v4l2loopback-dkms-
}

deb_kur() { # ad url
  local ad=$1 url=$2 dosya="$GECICI/$1.deb"
  bilgi "$ad indiriliyor…"
  curl -fL --retry 3 -o "$dosya" "$url" || { hata "$ad indirilemedi."; return 1; }
  chmod 644 "$dosya"
  sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y "$dosya" || return 1
}

chrome_kur() {
  if paket_kurulu google-chrome-stable; then basarili "Chrome zaten kurulu."; return 0; fi
  deb_kur google-chrome-stable "https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb" &&
    kaydet paket_kuruldu google-chrome-stable "Google resmî .deb (güncellemeler Google deposundan)"
}

vscode_kur() {
  if paket_kurulu code; then basarili "VS Code zaten kurulu."; return 0; fi
  # Microsoft deposunun eklenmesine önceden izin ver (aksi halde kurulum soru sorar)
  echo "code code/add-microsoft-repo boolean true" | sudo debconf-set-selections
  deb_kur code "https://go.microsoft.com/fwlink/?LinkID=760868" &&
    kaydet paket_kuruldu code "Microsoft resmî .deb (güncellemeler Microsoft deposundan)"
}

docker_kur() {
  if paket_kurulu docker-ce || paket_kurulu docker.io; then
    basarili "Docker zaten kurulu."
  elif depo_surumu_destekliyor "https://download.docker.com/linux/ubuntu" "$KOD_ADI"; then
    bilgi "Docker resmî deposu ekleniyor ($KOD_ADI)."
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc || return 1
    sudo chmod a+r /etc/apt/keyrings/docker.asc
    sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $KOD_ADI
Components: stable
Architectures: $MIMARI
Signed-By: /etc/apt/keyrings/docker.asc
EOF
    kaydet depo /etc/apt/sources.list.d/docker.sources "Docker resmî deposu"
    kaydet depo /etc/apt/keyrings/docker.asc "Docker depo anahtarı"
    APT_GUNCEL=0
    apt_kur docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || return 1
  else
    not_yaz "Docker deposu henüz $KOD_ADI için yok; Ubuntu'nun paketleri kurulacak."
    apt_kur docker.io docker-compose-v2 docker-buildx || return 1
  fi

  if ! id -nG "$USER" | tr ' ' '\n' | grep -qx docker; then
    printf '\n'
    not_yaz "docker grubundaki kullanıcı 'sudo' yazmadan Docker kullanabilir. Bu grup fiilen root yetkisi"
    not_yaz "demektir; tek kullanıcılı kişisel bilgisayarda yaygın ve makul bir tercihtir."
    if onay "Kullanıcın ($USER) docker grubuna eklensin mi?" e; then
      sudo usermod -aG docker "$USER" && kaydet grup docker "sudo'suz docker kullanımı (oturumu yeniden açınca geçerli)"
    fi
  fi
}

nvidia_container_kur() {
  komut_var nvidia-smi && nvidia-smi >/dev/null 2>&1 || { not_yaz "NVIDIA sürücüsü çalışmıyor; NVIDIA Container Toolkit atlandı."; return 0; }
  paket_kurulu nvidia-container-toolkit && { basarili "NVIDIA Container Toolkit zaten kurulu."; return 0; }
  onay "NVIDIA Container Toolkit kurulsun mu? (Docker konteynerlerinde RTX 3050'yi kullanmak için; ör. Whisper/AI araçları)" h || return 0
  curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey |
    sudo gpg --dearmor --yes -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg || return 1
  curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list |
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' |
    sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list >/dev/null || return 1
  kaydet depo /etc/apt/sources.list.d/nvidia-container-toolkit.list "NVIDIA Container Toolkit deposu"
  APT_GUNCEL=0
  apt_kur nvidia-container-toolkit || return 1
  dosya_yedekle /etc/docker/daemon.json
  sudo nvidia-ctk runtime configure --runtime=docker && sudo systemctl restart docker
}

pipx_araclari() {
  komut_var pipx || { hata "pipx yok."; return 1; }
  pipx ensurepath >/dev/null 2>&1
  export PATH="$HOME/.local/bin:$PATH"
  local arac kurulu
  kurulu=$(pipx list --short 2>/dev/null | awk '{print $1}')
  for arac in uv yt-dlp edge-tts; do
    if grep -qx "$arac" <<<"$kurulu"; then
      basarili "$arac zaten kurulu (pipx)."
    else
      bilgi "pipx install $arac"
      pipx install "$arac" && kaydet pipx_kuruldu "$arac" "pipx ile kullanıcıya kuruldu"
    fi
  done
}

git_ayarlari() {
  git lfs install >/dev/null 2>&1
  [[ -z $(git config --global init.defaultBranch) ]] && git config --global init.defaultBranch main && kaydet bilgi git "init.defaultBranch=main"
  if [[ -z $(git config --global user.name) ]]; then
    local ad eposta
    ad=$(sor "git için adın (boş bırakırsan atlanır)")
    eposta=$(sor "git için e-posta adresin (boş bırakırsan atlanır)")
    [[ -n $ad ]] && git config --global user.name "$ad" && kaydet bilgi git "user.name ayarlandı"
    [[ -n $eposta ]] && git config --global user.email "$eposta" && kaydet bilgi git "user.email ayarlandı"
  fi
  return 0
}

node_kontrol() {
  komut_var node || { uyari "node bulunamadı."; return 1; }
  local surum ana
  surum=$(node --version 2>/dev/null); ana=${surum#v}; ana=${ana%%.*}
  if ((ana < 20)); then
    uyari "Node.js $surum eski. Güncel LTS için 'fnm' (kullanıcı düzeyi sürüm yöneticisi) önerilir:"
    not_yaz "curl -fsSL https://fnm.vercel.app/install | bash && fnm install --lts"
  else
    basarili "Node.js $surum, npm $(npm --version 2>/dev/null)"
  fi
}

vscode_ayarlari() {
  komut_var code || { not_yaz "VS Code yok; ayarları atlandı."; return 0; }
  local ayar="$HOME/.config/Code/User/settings.json"
  mkdir -p "$(dirname "$ayar")"
  dosya_yedekle "$ayar"
  python3 -I - "$ayar" <<'PY' || { uyari "settings.json yorum satırı içeriyor olabilir; dokunmadım."; }
import json, os, sys
yol = sys.argv[1]
mevcut = {}
if os.path.exists(yol) and os.path.getsize(yol) > 0:
    with open(yol, encoding="utf-8") as f:
        mevcut = json.load(f)   # JSONC (yorumlu) ise hata verir → dokunulmaz
istenen = {
    "editor.fontFamily": "'JetBrains Mono', monospace",
    "editor.fontLigatures": True,
    "editor.fontSize": 14,
    "terminal.integrated.fontFamily": "'JetBrains Mono'",
    "workbench.colorTheme": "Default Dark Modern",
    "window.titleBarStyle": "custom",
    "python.terminal.activateEnvironment": True,
    "files.eol": "\n",
}
for k, v in istenen.items():
    mevcut.setdefault(k, v)   # kullanıcının mevcut ayarlarını ezme
with open(yol, "w", encoding="utf-8") as f:
    json.dump(mevcut, f, indent=2, ensure_ascii=False)
    f.write("\n")
PY
  basarili "VS Code: JetBrains Mono + koyu tema (mevcut ayarların korunarak)."
  if onay "VS Code eklentileri kurulsun mu? (Python, Pylance, Ruff, Docker, Jupyter)" e; then
    local e
    for e in ms-python.python ms-python.vscode-pylance charliermarsh.ruff ms-azuretools.vscode-docker ms-toolsai.jupyter; do
      code --install-extension "$e" --force >/dev/null 2>&1 && not_yaz "eklenti: $e" || uyari "kurulamadı: $e"
    done
    kaydet bilgi vscode "Python, Pylance, Ruff, Docker, Jupyter eklentileri"
  fi
}

masaustu_dosyasi_bul() {
  local ad d
  for ad in "$@"; do
    for d in /usr/share/applications /var/lib/snapd/desktop/applications "$HOME/.local/share/applications" /var/lib/flatpak/exports/share/applications; do
      [[ -f $d/$ad ]] && { printf '%s' "$ad"; return 0; }
    done
  done
  return 1
}

dock_favorileri() {
  komut_var gsettings && [[ -n ${DBUS_SESSION_BUS_ADDRESS:-} ]] || { not_yaz "GNOME oturumu yok; dock favorileri atlandı."; return 0; }
  local liste=() d
  for d in "org.gnome.Nautilus.desktop" "google-chrome.desktop" "code.desktop" \
           "org.gnome.Ptyxis.desktop org.gnome.Terminal.desktop" \
           "com.obsproject.Studio.desktop obs.desktop" \
           "org.gimp.GIMP.desktop gimp.desktop" "vlc.desktop"; do
    # shellcheck disable=SC2086
    d=$(masaustu_dosyasi_bul $d) && liste+=("'$d'")
  done
  local IFS=,
  gset org.gnome.shell favorite-apps "[${liste[*]}]"
}

adim "Temel paketler (VLC, GIMP, ffmpeg, git, Node.js, Python araçları…)" temel_paketler
adim "OBS Studio" obs_kur
adim "Google Chrome" chrome_kur
adim "VS Code" vscode_kur
adim "Docker" docker_kur
adim "NVIDIA Container Toolkit (isteğe bağlı)" nvidia_container_kur
adim "pipx araçları (uv, yt-dlp, edge-tts)" pipx_araclari
adim "git ayarları" git_ayarlari
adim "Node.js sürüm kontrolü" node_kontrol
adim "VS Code ayarları" vscode_ayarlari
adim "Dock sık kullanılanlar" dock_favorileri

printf '\n'
bilgi "Sürümler:"
for k in google-chrome code obs vlc gimp docker node python3 ffmpeg git uv yt-dlp edge-tts; do
  if komut_var "$k" || [[ -x $HOME/.local/bin/$k ]]; then
    case $k in
      ffmpeg) s=$(ffmpeg -hide_banner -version 2>/dev/null | head -1) ;;
      gimp) s=$(gimp --version 2>/dev/null | head -1) ;;
      obs) s=$(dpkg-query -W -f='${Version}' obs-studio 2>/dev/null) ;;
      vlc) s=$(dpkg-query -W -f='${Version}' vlc 2>/dev/null) ;;
      *) s=$(PATH="$HOME/.local/bin:$PATH" "$k" --version 2>/dev/null | head -1) ;;
    esac
    printf '  %-14s %s\n' "$k" "${s:-kurulu}"
  else
    printf '  %-14s %s\n' "$k" "—"
  fi
done

asama_sonu "Programlar aşaması"
not_yaz "docker grubuna eklendiysen bunun geçerli olması için oturumu kapatıp açman gerekir."
