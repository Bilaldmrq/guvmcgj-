#!/usr/bin/env python3
"""Kod yedeğini (Windows'ta hazırlanmış zip) ~/Projeler altına düzenli açar,
Python sanal ortamlarını Linux için yeniden kurar ve projeleri test eder.

Yalnızca standart kütüphane kullanır. 40-projeler.sh tarafından çağrılır:
    python3 -I projeler.py --zip ZIP --hedef ~/Projeler [--python 3.12]

Güvenlik:
  * Zip içeriği güvenilmeyen veri sayılır: '..' / mutlak yol / sembolik bağ içeren girdiler atlanır.
  * Projelerin kendi kodu ÇALIŞTIRILMAZ (yükleme/API çağrısı tetiklenmesin diye).
    Test = sözdizimi denetimi + bağımlılıkların içe aktarılması + araç zinciri testi.
  * .env dosyaları açılır ama içerikleri ekrana/rapora yazılmaz; izinleri 600 yapılır.
"""
from __future__ import annotations

import argparse
import ast
import datetime as dt
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path, PurePosixPath

try:
    import tomllib  # Python 3.11+
except ModuleNotFoundError:  # pragma: no cover
    tomllib = None

OTOMATIK = os.environ.get("ISTASYON_OTOMATIK") == "1"
DENETIM_BETIGI = Path(__file__).with_name("proje_denetim.py")

# ---------------------------------------------------------------------------
# Çıktı ve etkileşim
# ---------------------------------------------------------------------------
TTY = sys.stdout.isatty()


def _renk(kod: str, metin: str) -> str:
    return f"\033[{kod}m{metin}\033[0m" if TTY else metin


def bilgi(m: str) -> None:
    print(f"{_renk('1;34', '==>')} {m}", flush=True)


def basarili(m: str) -> None:
    print(f"{_renk('1;32', ' ✔')}  {m}", flush=True)


def uyari(m: str) -> None:
    print(f"{_renk('1;33', ' ⚠')}  {m}", flush=True)


def hata(m: str) -> None:
    print(f"{_renk('1;31', ' ✖')}  {m}", flush=True)


def not_yaz(m: str) -> None:
    print(_renk("0;90", f"    {m}"), flush=True)


def baslik(m: str) -> None:
    print(f"\n{_renk('1', '▶ ' + m)}", flush=True)


def onay(soru: str, varsayilan: str = "h") -> bool:
    ipucu = "E/h" if varsayilan == "e" else "e/H"
    if OTOMATIK:
        print(f"{soru} [{ipucu}] → {varsayilan} (otomatik)")
        return varsayilan == "e"
    while True:
        try:
            with open("/dev/tty") as tty:
                print(f"{soru} [{ipucu}] ", end="", flush=True)
                cevap = tty.readline().strip().lower()
        except OSError:
            cevap = ""
        cevap = cevap or varsayilan
        if cevap in ("e", "evet", "y", "yes"):
            return True
        if cevap in ("h", "hayır", "hayir", "n", "no"):
            return False
        print("Lütfen e (evet) ya da h (hayır) yaz.")


def secim(soru: str, secenekler: str, varsayilan: str) -> str:
    if OTOMATIK:
        print(f"{soru} → {varsayilan} (otomatik)")
        return varsayilan
    while True:
        try:
            with open("/dev/tty") as tty:
                print(f"{soru} ", end="", flush=True)
                cevap = tty.readline().strip().lower() or varsayilan
        except OSError:
            cevap = varsayilan
        if cevap in secenekler:
            return cevap


def calistir(komut, cwd=None, zaman_asimi=1800, sessiz=False, env=None):
    """Komutu çalıştırır; (dönüş kodu, birleşik çıktı) döndürür."""
    if not sessiz:
        not_yaz("$ " + " ".join(str(k) for k in komut))
    try:
        p = subprocess.run(
            [str(k) for k in komut], cwd=cwd, env=env, capture_output=True, text=True,
            timeout=zaman_asimi, errors="replace",
        )
        return p.returncode, (p.stdout or "") + (p.stderr or "")
    except FileNotFoundError:
        return 127, f"komut bulunamadı: {komut[0]}"
    except OSError as e:  # ör. çalıştırma izni yok
        return 126, f"çalıştırılamadı: {komut[0]} ({e})"
    except subprocess.TimeoutExpired:
        return 124, f"zaman aşımı ({zaman_asimi} sn)"


def kuyruk(metin: str, n: int = 12) -> None:
    for satir in metin.strip().splitlines()[-n:]:
        not_yaz(satir)


# ---------------------------------------------------------------------------
# Sabitler
# ---------------------------------------------------------------------------
ATLANAN_DIZINLER = {"__pycache__", "node_modules", ".pytest_cache", ".mypy_cache", ".ruff_cache", ".ipynb_checkpoints"}
ATLANAN_DOSYALAR = {"thumbs.db", "desktop.ini", ".ds_store"}
KOD_UZANTILARI = {".py", ".js", ".mjs", ".cjs", ".ts", ".ipynb", ".sh", ".bat", ".ps1", ".cmd"}
PROJE_ISARETLERI = {
    "requirements.txt", "pyproject.toml", "setup.py", "pipfile", "package.json", "agent_playbook.md",
    "dockerfile", "docker-compose.yml", "compose.yml", ".env", "main.py", "app.py",
}
KAPSAYICI_ADLAR = {
    "videos", "videolar", "desktop", "masaüstü", "masaustu", "documents", "belgeler", "downloads",
    "indirilenler", "i̇ndirilenler", "projects", "projeler", "code", "kod", "kodlar", "src", "repos",
    "github", "python", "users", "kullanıcılar", "onedrive", "workspace", "dev",
}
KANAL_ANAHTAR = [
    "quietwealth", "quiet_wealth", "quiet-wealth", "quiet wealth", "unsolved", "anadolu", "sirlar",
    "kanal", "channel", "shorts", "reels", "tiktok", "youtube", "video", "podcast",
]
OTOMASYON_ANAHTAR = [
    "n8n", "workflow", "otomasyon", "automation", "bot", "jarvis", "zapier", "scrap", "cron",
    "telegram", "discord", "agent", "asistan", "assistant",
]
KANAL_DOSYALARI = {"agent_playbook.md", "uploads_log.txt", "analytics_log.csv", "strategy_notes.md"}

WINDOWS_PAKETLERI = {
    "pywin32", "pywin32-ctypes", "pypiwin32", "pywinpty", "comtypes", "pywinauto", "wmi", "winshell",
    "pyreadline", "pyreadline3", "windows-curses", "win32-setctime", "winotify", "win10toast", "win11toast",
    "windows-toasts", "pywinstyles", "winrt", "winsdk",
}
WINDOWS_MODULLERI = {
    "winreg", "_winreg", "msvcrt", "winsound", "_winapi", "win32api", "win32con", "win32gui", "win32com",
    "win32clipboard", "win32process", "win32file", "win32event", "win32service", "pywintypes", "pythoncom",
    "wmi", "comtypes", "pywinauto", "winshell", "win10toast", "winotify",
}
IMPORT_PIP = {
    "cv2": "opencv-python", "PIL": "pillow", "yaml": "pyyaml", "dotenv": "python-dotenv",
    "sklearn": "scikit-learn", "skimage": "scikit-image", "bs4": "beautifulsoup4", "edge_tts": "edge-tts",
    "whisper": "openai-whisper", "faster_whisper": "faster-whisper", "stable_whisper": "stable-ts",
    "googleapiclient": "google-api-python-client", "google_auth_oauthlib": "google-auth-oauthlib",
    "google_auth_httplib2": "google-auth-httplib2", "telegram": "python-telegram-bot", "fitz": "pymupdf",
    "docx": "python-docx", "pptx": "python-pptx", "Crypto": "pycryptodome", "serial": "pyserial",
    "dateutil": "python-dateutil", "magic": "python-magic", "yt_dlp": "yt-dlp", "jwt": "PyJWT",
    "attr": "attrs", "imageio_ffmpeg": "imageio-ffmpeg", "ffmpeg": "ffmpeg-python",
    "speech_recognition": "SpeechRecognition", "gtts": "gTTS", "slugify": "python-slugify",
    "unidecode": "Unidecode", "apscheduler": "APScheduler", "dotmap": "dotmap", "pydub": "pydub",
    "moviepy": "moviepy", "sounddevice": "sounddevice", "soundfile": "soundfile", "OpenSSL": "pyOpenSSL",
    "websocket": "websocket-client", "socketio": "python-socketio", "discord": "discord.py",
    "github": "PyGithub", "Levenshtein": "python-Levenshtein", "pkg_resources": "setuptools",
}
GOOGLE_ALT = {
    "google.generativeai": "google-generativeai", "google.genai": "google-genai", "google.oauth2": "google-auth",
    "google.auth": "google-auth", "google.protobuf": "protobuf", "google.api_core": "google-api-core",
}
# Derleme hatası veren paketler için gereken sistem kütüphaneleri
SISTEM_KUTUPHANESI = {
    "pyaudio": "portaudio19-dev", "mysqlclient": "libmysqlclient-dev", "psycopg2": "libpq-dev",
    "pycairo": "libcairo2-dev", "pygobject": "libgirepository-2.0-dev libcairo2-dev", "dbus-python": "libdbus-1-dev",
    "python-ldap": "libldap2-dev libsasl2-dev", "lxml": "libxml2-dev libxslt1-dev",
}
PAYLASIMLI_KUTUPHANE = {
    "libGL.so": "libgl1", "libgthread": "libglib2.0-0t64", "libsndfile": "libsndfile1",
    "libportaudio": "libportaudio2", "libespeak": "espeak-ng", "libmagic": "libmagic1",
    "libEGL": "libegl1", "libxcb": "libxcb1", "libtk": "python3-tk", "libasound": "libasound2t64",
}


def normal_ad(ad: str) -> str:
    return re.sub(r"[-_.]+", "-", ad).lower()


def tr_kucuk(s: str) -> str:
    tablo = str.maketrans({"ı": "i", "İ": "i", "ş": "s", "Ş": "s", "ğ": "g", "Ğ": "g",
                           "ü": "u", "Ü": "u", "ö": "o", "Ö": "o", "ç": "c", "Ç": "c"})
    return s.translate(tablo).lower()


# ---------------------------------------------------------------------------
# 1) Zip'i güvenli aç
# ---------------------------------------------------------------------------
def duzgun_ad(info: zipfile.ZipInfo) -> str:
    """Windows zip'lerindeki kodlama ve ters bölü sorunlarını düzeltir."""
    ad = info.filename
    if not info.flag_bits & 0x800:  # UTF-8 bayrağı yok → zipfile cp437 ile çözdü
        try:
            ham = ad.encode("cp437")
        except UnicodeEncodeError:
            ham = None
        if ham is not None:
            try:
                ad = ham.decode("utf-8")
            except UnicodeDecodeError:
                ad = ham.decode("cp857", errors="replace")  # Türkçe Windows OEM kod sayfası
    return ad.replace("\\", "/")


def guvenli_parcalar(ad: str):
    parcalar = [p for p in ad.split("/") if p not in ("", ".")]
    if parcalar and re.fullmatch(r"[A-Za-z]:", parcalar[0]):
        parcalar = parcalar[1:]
    if any(p == ".." for p in parcalar):
        return None
    return parcalar


def zip_ac(zip_yolu: Path, gelen: Path) -> dict:
    baslik(f"Zip açılıyor: {zip_yolu.name}")
    with zipfile.ZipFile(zip_yolu) as zf:
        bozuk = zf.testzip()
        if bozuk:
            raise SystemExit(f"Zip dosyası bozuk (ilk bozuk girdi: {bozuk}). Drive'dan yeniden indir.")
        girdiler = []
        for info in zf.infolist():
            ad = duzgun_ad(info)
            dizin_mi = ad.endswith("/")
            parcalar = guvenli_parcalar(ad)
            if parcalar is None:
                uyari(f"Güvensiz yol atlandı: {ad}")
                continue
            if not parcalar:
                continue
            if (info.external_attr >> 16) & 0o170000 == 0o120000:
                uyari(f"Sembolik bağ atlandı: {ad}")
                continue
            girdiler.append((info, parcalar, dizin_mi))

        toplam = sum(i.file_size for i, _, d in girdiler if not d)
        bos = shutil.disk_usage(gelen.parent if gelen.parent.exists() else Path.home()).free
        if toplam > bos * 0.9:
            raise SystemExit(f"Diskte yer yok: açılınca {toplam/1e9:.1f} GB gerekiyor.")

        # Sanal ortamları bul (Windows venv'leri Linux'ta çalışmaz; yalnızca paket listesi alınır)
        venvler = {tuple(p[:-1]) for _, p, d in girdiler if not d and p[-1].lower() == "pyvenv.cfg"}
        kurtarilan = {}
        for venv in venvler:
            kurtarilan[venv] = venv_paketlerini_oku(zf, girdiler, venv)

        atlanan = {"sanal ortam": 0, "önbellek/node_modules": 0, "sistem dosyası": 0}
        acilan = 0
        env_dosyalari = []
        for info, parcalar, dizin_mi in girdiler:
            if any(tuple(parcalar[: len(v)]) == v for v in venvler):
                atlanan["sanal ortam"] += 1
                continue
            if any(p in ATLANAN_DIZINLER for p in parcalar) or parcalar[-1].endswith((".pyc", ".pyo")):
                atlanan["önbellek/node_modules"] += 1
                continue
            if parcalar[-1].lower() in ATLANAN_DOSYALAR:
                atlanan["sistem dosyası"] += 1
                continue
            hedef = gelen.joinpath(*parcalar)
            if not str(hedef.resolve()).startswith(str(gelen.resolve())):
                uyari(f"Klasör dışına çıkan yol atlandı: {'/'.join(parcalar)}")
                continue
            if dizin_mi:
                hedef.mkdir(parents=True, exist_ok=True)
                continue
            hedef.parent.mkdir(parents=True, exist_ok=True)
            with zf.open(info) as kaynak, open(hedef, "wb") as cikti:
                shutil.copyfileobj(kaynak, cikti)
            zaman = dt.datetime(*info.date_time).timestamp()
            os.utime(hedef, (zaman, zaman))
            ad_k = parcalar[-1].lower()
            if ad_k == ".env" or ad_k.startswith(".env.") or ad_k.endswith((".pem", ".key")) or \
               ad_k in ("client_secret.json", "credentials.json", "token.json", "token.pickle"):
                os.chmod(hedef, 0o600)
                env_dosyalari.append(hedef)
            elif ad_k.endswith(".sh"):
                os.chmod(hedef, 0o755)
            else:
                os.chmod(hedef, 0o644)
            acilan += 1

    # Kurtarılan paket listelerini projelerin içine yaz (proje taşınınca onunla gider)
    for venv, bilgi_ in kurtarilan.items():
        if not bilgi_["paketler"]:
            continue
        ust = gelen.joinpath(*venv[:-1])
        klasor = ust / ".linux-kurulum"
        klasor.mkdir(parents=True, exist_ok=True)
        (klasor / f"{venv[-1]}.json").write_text(json.dumps(bilgi_, ensure_ascii=False, indent=2), encoding="utf-8")

    basarili(f"{acilan} dosya açıldı.")
    for neden, sayi in atlanan.items():
        if sayi:
            not_yaz(f"Atlandı ({neden}): {sayi} dosya")
    for venv, b in kurtarilan.items():
        not_yaz(f"Windows sanal ortamı bulundu: {'/'.join(venv)} (Python {b['python'] or '?'}, "
                f"{len(b['paketler'])} paket kaydı) → Linux'ta yeniden kurulacak")
    if env_dosyalari:
        not_yaz(f"Gizli bilgi içerebilecek {len(env_dosyalari)} dosyanın (.env, token, anahtar) izni 600 yapıldı.")
    return {"acilan": acilan, "kurtarilan": len(kurtarilan), "gizli": len(env_dosyalari)}


def venv_paketlerini_oku(zf, girdiler, venv) -> dict:
    sonuc = {"ad": venv[-1], "python": None, "paketler": []}
    n = len(venv)
    for info, p, d in girdiler:
        if d or tuple(p[:n]) != venv:
            continue
        if len(p) == n + 1 and p[-1].lower() == "pyvenv.cfg":
            metin = zf.read(info).decode("utf-8", "replace")
            m = re.search(r"^\s*(?:version|version_info)\s*=\s*(\d+\.\d+)", metin, re.M)
            if m:
                sonuc["python"] = m.group(1)
    istenen = set()
    meta = {}
    for info, p, d in girdiler:
        if d or tuple(p[:n]) != venv or len(p) < 2 or not p[-2].endswith(".dist-info"):
            continue
        if "site-packages" not in p:
            continue
        if p[-1] == "REQUESTED":
            istenen.add(p[-2])
        elif p[-1] == "METADATA":
            metin = zf.read(info).decode("utf-8", "replace")
            ad = re.search(r"^Name:\s*(.+)$", metin, re.M)
            sur = re.search(r"^Version:\s*(.+)$", metin, re.M)
            if ad and sur:
                meta[p[-2]] = (ad.group(1).strip(), sur.group(1).strip())
    for dist, (ad, surum) in sorted(meta.items(), key=lambda x: x[1][0].lower()):
        sonuc["paketler"].append({"ad": ad, "surum": surum, "istenen": dist in istenen})
    return sonuc


# ---------------------------------------------------------------------------
# 2) Yerleşim planı
# ---------------------------------------------------------------------------
def proje_isareti_var(d: Path) -> bool:
    try:
        for c in d.iterdir():
            ad = c.name.lower()
            if ad in PROJE_ISARETLERI or ad.startswith("requirements") or c.suffix.lower() in KOD_UZANTILARI:
                return True
            if c.is_dir() and ad in (".git", ".linux-kurulum"):
                return True
    except OSError:
        pass
    return False


def kok_bul(gelen: Path) -> Path:
    """Zip'in tek bir sarmalayıcı klasörü varsa (ör. kod_yedek/) içine iner."""
    kok = gelen
    while True:
        cocuklar = [c for c in kok.iterdir()]
        if len(cocuklar) == 1 and cocuklar[0].is_dir() and not proje_isareti_var(cocuklar[0]):
            kok = cocuklar[0]
        else:
            return kok


def adaylari_topla(dizin: Path, derinlik=0):
    for c in sorted(dizin.iterdir(), key=lambda x: x.name.lower()):
        if c.is_dir():
            alt_dizinler = [x for x in c.iterdir() if x.is_dir()]
            dosya_var = any(x.is_file() for x in c.iterdir())
            kapsayici = tr_kucuk(c.name) in {tr_kucuk(k) for k in KAPSAYICI_ADLAR}
            saf_kapsayici = (not dosya_var and len(alt_dizinler) >= 2
                             and all(proje_isareti_var(x) for x in alt_dizinler))
            if derinlik < 3 and not proje_isareti_var(c) and (kapsayici or saf_kapsayici):
                yield from adaylari_topla(c, derinlik + 1)
            else:
                yield c
        else:
            yield c


def siniflandir(yol: Path) -> tuple[str, str]:
    if yol.is_file():
        return "Diger/_tekil-dosyalar", "tek başına dosya"
    ad = tr_kucuk(yol.name)
    for k in KANAL_ANAHTAR:
        if k.replace(" ", "") in ad.replace(" ", ""):
            return "Kanallar", f"adı '{k}' içeriyor"
    dosyalar = []
    for kok, dizinler, adlar in os.walk(yol):
        dizinler[:] = [d for d in dizinler if d not in ATLANAN_DIZINLER and not d.startswith(".")]
        dosyalar.extend(Path(kok) / a for a in adlar)
        if len(dosyalar) > 3000:
            break
    adlar_k = {f.name.lower() for f in dosyalar}
    if adlar_k & KANAL_DOSYALARI:
        return "Kanallar", "kanal dosyaları var (playbook / yükleme kaydı)"
    if any(re.fullmatch(r"ep\d+", p.name.lower()) for p in yol.iterdir() if p.is_dir()):
        return "Kanallar", "bölüm klasörleri (epXXX) var"
    for k in OTOMASYON_ANAHTAR:
        if re.search(rf"(^|[^a-z]){re.escape(k)}", ad):
            return "Otomasyon", f"adı '{k}' içeriyor"
    for f in dosyalar:
        if f.suffix.lower() == ".json" and f.stat().st_size < 5_000_000:
            try:
                veri = json.loads(f.read_text(encoding="utf-8", errors="replace"))
            except (ValueError, OSError):
                continue
            if isinstance(veri, dict) and "nodes" in veri and "connections" in veri:
                return "Otomasyon", "n8n iş akışı (workflow) içeriyor"
    kod = [f for f in dosyalar if f.suffix.lower() in KOD_UZANTILARI]
    if kod:
        metin = ""
        for f in kod[:200]:
            if f.suffix == ".py":
                try:
                    metin += f.read_text(encoding="utf-8", errors="replace")[:20000]
                except OSError:
                    pass
        if re.search(r"\b(edge_tts|moviepy|ffmpeg|pollinations|yt_dlp)\b", metin):
            return "Kanallar", "video üretim kodu (ffmpeg / edge-tts / moviepy)"
        return "Yazilim", "kod içeriyor"
    return "Diger", "kod içermiyor"


def plan_olustur(gelen: Path, hedef: Path) -> list[list[str]]:
    kok = kok_bul(gelen)
    plan = []
    for aday in adaylari_topla(kok):
        kategori, neden = siniflandir(aday)
        plan.append([str(aday.relative_to(gelen)), f"{kategori}/{aday.name}", neden])
    return plan


def plan_goster(plan, hedef: Path) -> None:
    print()
    genislik = max((len(p[0]) for p in plan), default=10)
    for kaynak, hedef_rel, neden in plan:
        print(f"  {kaynak:<{min(genislik, 45)}}  →  ~/{hedef.name}/{hedef_rel}   {_renk('0;90', '(' + neden + ')')}")
    print()


def plan_uygula(plan, gelen: Path, hedef: Path) -> list[Path]:
    tasinan = []
    for kaynak_rel, hedef_rel, _ in plan:
        kaynak = gelen / kaynak_rel
        parcalar = guvenli_parcalar(hedef_rel.strip())
        if not parcalar:
            uyari(f"Geçersiz hedef, atlandı: {hedef_rel}")
            continue
        yer = hedef.joinpath(*parcalar)
        if yer.exists():
            uyari(f"Zaten var, üzerine yazılmadı: {yer}  (kaynak {kaynak} içinde duruyor)")
            continue
        yer.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(kaynak), str(yer))
        tasinan.append(yer)
    # Boşalan geçici klasörleri temizle (alt klasörler silindikçe üsttekiler de boşalır)
    for kok, _, _ in os.walk(gelen, topdown=False):
        try:
            if not os.listdir(kok):
                os.rmdir(kok)
        except OSError:
            pass
    return tasinan


# ---------------------------------------------------------------------------
# 3) Sanal ortamlar
# ---------------------------------------------------------------------------
def gezin(kok: Path, derinlik=4):
    """Sanal ortam/node_modules/.git dışındaki dosyaları gezer."""
    kok_derinlik = len(kok.parts)
    for d, dizinler, dosyalar in os.walk(kok):
        p = Path(d)
        dizinler[:] = [x for x in dizinler
                       if x not in ATLANAN_DIZINLER and x != ".git" and not (p / x / "pyvenv.cfg").exists()
                       and len(p.parts) - kok_derinlik < derinlik]
        yield p, dizinler, dosyalar


def ortam_koklerini_bul(proje: Path) -> list[Path]:
    kokler = []
    for d, _, dosyalar in gezin(proje, 3):
        adlar = {f.lower() for f in dosyalar}
        if (d / ".linux-kurulum").is_dir() or adlar & {"pyproject.toml", "setup.py", "pipfile"} or \
           any(a.startswith("requirements") and a.endswith(".txt") for a in adlar):
            kokler.append(d)
    if not kokler:
        if any(f.endswith(".py") for _, _, dosyalar in gezin(proje, 3) for f in dosyalar):
            kokler.append(proje)
    # İç içe kökleri ele: bir kökün altındaki kök yalnızca kendi işaretine sahipse ayrı tutulur
    return sorted(set(kokler))


def python_surumu_sec(kok: Path, oneri: str | None, varsayilan: str) -> str:
    if oneri:
        return oneri
    pv = kok / ".python-version"
    if pv.is_file():
        m = re.match(r"\s*(\d+\.\d+)", pv.read_text(errors="replace"))
        if m:
            return m.group(1)
    pp = kok / "pyproject.toml"
    if pp.is_file() and tomllib:
        try:
            veri = tomllib.loads(pp.read_text(encoding="utf-8", errors="replace"))
            istek = veri.get("project", {}).get("requires-python", "")
            m = re.search(r">=\s*3\.(\d+)", istek)
            if m and int(m.group(1)) > int(varsayilan.split(".")[1]):
                return f"3.{m.group(1)}"
        except Exception:  # noqa: BLE001
            pass
    return varsayilan


def gereksinim_temizle(satirlar: list[str]) -> tuple[list[str], list[str]]:
    """Windows'a özgü paketleri çıkarır, '+cu121' gibi yerel sürüm eklerini temizler."""
    temiz, cikarilan = [], []
    pytorch_dizini = any("download.pytorch.org" in s for s in satirlar)
    for s in satirlar:
        cizgi = s.strip()
        if not cizgi or cizgi.startswith("#"):
            continue
        if cizgi.startswith("-r ") or cizgi.startswith("--requirement"):
            continue  # iç içe dosyalar ayrıca işlenir
        if cizgi.startswith("-"):
            temiz.append(cizgi)
            continue
        ad = re.split(r"[\s;<>=!~\[@]", cizgi, maxsplit=1)[0]
        if normal_ad(ad) in WINDOWS_PAKETLERI and ";" not in cizgi:
            cikarilan.append(ad)
            continue
        if not pytorch_dizini:
            cizgi = re.sub(r"(==\s*[^\s;+]+)\+[A-Za-z0-9.]+", r"\1", cizgi)
        temiz.append(cizgi)
    return temiz, cikarilan


def esnek_yap(satirlar: list[str]) -> list[str]:
    """Sürüm sabitlerini kaldırır (pinli kurulum başarısız olursa ikinci deneme)."""
    sonuc = []
    for s in satirlar:
        if s.startswith("-"):
            sonuc.append(s)
            continue
        ad, _, isaret = s.partition(";")
        ad = re.split(r"[\s<>=!~]", ad.strip(), maxsplit=1)[0]
        sonuc.append(ad + (";" + isaret if isaret else ""))
    return sonuc


class Ortam:
    def __init__(self, kok: Path, ad: str, python: str):
        self.kok, self.ad, self.python_surumu = kok, ad, python
        self.yol = kok / ad
        self.py = self.yol / "bin" / "python"
        self.kaynaklar: list[str] = []
        self.kurulum = "—"
        self.notlar: list[str] = []

    def __repr__(self):
        return f"{self.kok.name}/{self.ad}"


class Kurucu:
    def __init__(self, uv: str, varsayilan_python: str, gpu: bool):
        self.uv, self.varsayilan_python, self.gpu = uv, varsayilan_python, gpu

    def olustur(self, o: Ortam) -> bool:
        if o.py.exists():
            kod, _ = calistir([o.py, "-c", "import sys"], sessiz=True)
            if kod == 0:
                not_yaz(f"{o} zaten var; yeniden oluşturulmadı.")
                return True
            shutil.rmtree(o.yol)
        kod, cikti = calistir([self.uv, "venv", "--seed", "--python", o.python_surumu, o.yol], cwd=o.kok)
        if kod != 0 and re.search(r"No (interpreter|download) found|not found", cikti, re.I):
            # İstenen Python sürümü indirilemedi → sistemin Python'u ile dene
            uyari(f"{o}: Python {o.python_surumu} bulunamadı/indirilemedi; sistemin python3'ü kullanılacak.")
            o.notlar.append(f"Python {o.python_surumu} yerine sistem python3 kullanıldı.")
            o.python_surumu = "python3"
            kod, cikti = calistir([self.uv, "venv", "--seed", "--python", "python3", o.yol], cwd=o.kok)
        if kod != 0 and "seed" in cikti:
            # pip tohumlanamadı (ağ sorunu olabilir); uv pip pip'e ihtiyaç duymaz
            kod, cikti = calistir([self.uv, "venv", "--python", o.python_surumu, o.yol], cwd=o.kok)
            if kod == 0:
                o.notlar.append("Ortama pip eklenemedi (ağ?); paketler 'uv pip install' ile kurulabilir.")
        if kod != 0:
            hata(f"{o} oluşturulamadı.")
            kuyruk(cikti)
            return False
        basarili(f"{o} oluşturuldu (Python {o.python_surumu}).")
        return True

    def pip(self, o: Ortam, argumanlar: list, zaman=3600):
        return calistir([self.uv, "pip", "install", "--python", o.py, *argumanlar], cwd=o.kok, zaman_asimi=zaman)

    def gereksinim_kur(self, o: Ortam, satirlar: list[str], etiket: str) -> bool:
        temiz, cikarilan = gereksinim_temizle(satirlar)
        not_metni = f"Windows'a özgü paketler atlandı: {', '.join(cikarilan)}"
        if cikarilan and not_metni not in o.notlar:
            o.notlar.append(not_metni)
            not_yaz(f"Windows'a özgü, atlandı: {', '.join(cikarilan)}")
        if not [s for s in temiz if not s.startswith("-")]:
            return True
        with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False, encoding="utf-8") as f:
            f.write("\n".join(temiz) + "\n")
            gecici = f.name
        try:
            kod, cikti = self.pip(o, ["-r", gecici])
            if kod == 0:
                o.kurulum = f"{etiket} (sürümler aynen)"
                basarili(f"{o}: {etiket} kuruldu.")
                return True
            uyari(f"{o}: sabit sürümlerle kurulamadı; sürüm serbest bırakılarak yeniden deneniyor.")
            kuyruk(cikti, 6)
            self.derleme_ipucu(cikti, o)
            Path(gecici).write_text("\n".join(esnek_yap(temiz)) + "\n", encoding="utf-8")
            kod, cikti = self.pip(o, ["-r", gecici])
            if kod == 0:
                o.kurulum = f"{etiket} (esnek sürümler)"
                o.notlar.append("Bazı sabit sürümler Linux'ta bulunamadı; güncel uyumlu sürümler kuruldu.")
                basarili(f"{o}: {etiket} esnek sürümlerle kuruldu.")
                return True
            hata(f"{o}: {etiket} kurulamadı.")
            kuyruk(cikti)
            self.derleme_ipucu(cikti, o)
            o.kurulum = f"{etiket} — HATA"
            return False
        finally:
            os.unlink(gecici)

    def derleme_ipucu(self, cikti: str, o: Ortam) -> None:
        for paket, apt in SISTEM_KUTUPHANESI.items():
            if re.search(rf"\b{re.escape(paket)}\b", cikti, re.I) and re.search(r"(build|derle|error: command|failed)", cikti, re.I):
                o.notlar.append(f"{paket} için sistem paketi gerekebilir: sudo apt install {apt}")
                uyari(f"{paket} derlenemedi olabilir → sudo apt install {apt}")

    def kurulu_paketler(self, o: Ortam) -> set[str]:
        kod, cikti = calistir([self.uv, "pip", "list", "--python", o.py, "--format", "json"], sessiz=True)
        if kod != 0:
            return set()
        try:
            return {normal_ad(p["name"]) for p in json.loads(cikti[cikti.index("["):])}
        except (ValueError, KeyError):
            return set()

    def cuda_kutuphaneleri(self, o: Ortam) -> None:
        """faster-whisper/ctranslate2 Linux'ta cuBLAS + cuDNN'i pip paketinden bulsun diye."""
        if not self.gpu:
            return
        paketler = self.kurulu_paketler(o)
        if "ctranslate2" not in paketler:
            return
        eksik = [p for p in ("nvidia-cublas-cu12", "nvidia-cudnn-cu12") if p not in paketler]
        if eksik:
            bilgi(f"{o}: ctranslate2 (faster-whisper) GPU'da çalışsın diye CUDA kütüphaneleri ekleniyor.")
            kod, cikti = self.pip(o, ["nvidia-cublas-cu12", "nvidia-cudnn-cu12==9.*"])
            if kod != 0:
                kuyruk(cikti, 6)
                return
        kod, yollar = calistir([o.py, "-I", "-c",
                                "import os,nvidia.cublas.lib as a,nvidia.cudnn.lib as b;"
                                "print(os.path.dirname(a.__file__)+':'+os.path.dirname(b.__file__))"], sessiz=True)
        if kod != 0:
            return
        etkinlestir = o.yol / "bin" / "activate"
        isaret = "# ubuntu-istasyon: CUDA kütüphaneleri"
        metin = etkinlestir.read_text(encoding="utf-8")
        if isaret not in metin:
            with open(etkinlestir, "a", encoding="utf-8") as f:
                f.write(f"\n{isaret} (faster-whisper / ctranslate2)\n"
                        f'export LD_LIBRARY_PATH="{yollar.strip()}${{LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}}"\n')
        o.notlar.append("GPU için cuBLAS/cuDNN eklendi; ortamı 'source .../bin/activate' ile açınca etkin olur.")
        basarili(f"{o}: CUDA kütüphane yolu activate betiğine eklendi.")


def ortamlari_planla(kok: Path, varsayilan_python: str) -> list[tuple[Ortam, list[tuple[str, list[str]]]]]:
    """Her kök için hangi sanal ortamların, hangi kaynaklarla kurulacağını belirler."""
    ortamlar: dict[str, tuple[Ortam, list]] = {}
    kurtarilan = {}
    lk = kok / ".linux-kurulum"
    if lk.is_dir():
        for f in sorted(lk.glob("*.json")):
            try:
                kurtarilan[f.stem] = json.loads(f.read_text(encoding="utf-8"))
            except ValueError:
                pass

    def ortam(ad: str, python: str | None = None):
        if ad not in ortamlar:
            ortamlar[ad] = (Ortam(kok, ad, python_surumu_sec(kok, python, varsayilan_python)), [])
        return ortamlar[ad]

    for ad, b in kurtarilan.items():
        ortam(ad, b.get("python"))

    def gereksinim_oku(dosya: Path, gorulen=None) -> list[str]:
        gorulen = gorulen or set()
        if dosya in gorulen or not dosya.is_file():
            return []
        gorulen.add(dosya)
        satirlar = []
        for s in dosya.read_text(encoding="utf-8-sig", errors="replace").splitlines():
            m = re.match(r"\s*(?:-r|--requirement)\s*(\S+)", s)
            if m:
                satirlar += gereksinim_oku(dosya.parent / m.group(1), gorulen)
            else:
                satirlar.append(s)
        return satirlar

    for dosya in sorted(kok.glob("requirements*.txt")):
        ek = re.sub(r"^requirements[-_]?", "", dosya.stem.lower())
        if ek in ("", "linux", "prod", "base", "main", "lock"):
            hedef_ad = ".venv" if ".venv" in ortamlar or "venv" not in ortamlar else "venv"
        elif ek in ("dev", "test", "tests"):
            hedef_ad = ".venv" if ".venv" in ortamlar or "venv" not in ortamlar else "venv"
        else:
            hedef_ad = next((a for a in ortamlar if a.lower().endswith(ek)), f".venv-{ek}")
        ortam(hedef_ad)[1].append((dosya.name, gereksinim_oku(dosya)))

    pp = kok / "pyproject.toml"
    if pp.is_file() and tomllib:
        try:
            veri = tomllib.loads(pp.read_text(encoding="utf-8", errors="replace"))
        except Exception:  # noqa: BLE001
            veri = {}
        bagimlilik = veri.get("project", {}).get("dependencies", [])
        if "build-system" in veri:
            ortam(".venv")[1].append(("pyproject.toml (-e .)", ["-e ."]))
        elif bagimlilik:
            ortam(".venv")[1].append(("pyproject.toml", list(bagimlilik)))
    pf = kok / "Pipfile"
    if pf.is_file() and tomllib:
        try:
            veri = tomllib.loads(pf.read_text(encoding="utf-8", errors="replace"))
            satirlar = [ad if surum in ("*", "") or not isinstance(surum, str) else f"{ad}{surum}"
                        for ad, surum in veri.get("packages", {}).items()]
            ortam(".venv")[1].append(("Pipfile", satirlar))
        except Exception:  # noqa: BLE001
            pass

    # Windows'taki ortamdan kurtarılan paketler: requirements dosyasında olmayanları tamamla
    for ad, b in kurtarilan.items():
        paketler = b.get("paketler", [])
        istenen = [p for p in paketler if p.get("istenen")] or paketler
        satirlar = [f"{p['ad']}=={p['surum']}" for p in istenen]
        if satirlar:
            ortamlar[ad][1].append((f"Windows'taki {ad} kaydı", satirlar))

    return [ortamlar[a] for a in sorted(ortamlar)]


# ---------------------------------------------------------------------------
# 4) Test ve uyumluluk
# ---------------------------------------------------------------------------
UYUMLULUK_DESENLERI = [
    (re.compile(r"(?<![A-Za-z0-9])[A-Za-z]:(?:\\\\|\\|/)(?=[A-Za-z0-9_ .$%{-])"), "Windows mutlak yolu",
     "Linux yolu ya da göreli yol kullan (ör. Path.home() / 'Projeler' / ...)"),
    (re.compile(r"\.exe\b", re.I), ".exe çağrısı", "Linux'ta uzantısız komut adı (ör. 'ffmpeg')"),
    (re.compile(r"\bos\.startfile\b"), "os.startfile (yalnız Windows)", "subprocess.run(['xdg-open', yol])"),
    (re.compile(r"\b(?:import|from)\s+(winreg|_winreg|msvcrt|winsound|_winapi)\b"), "Windows'a özgü modül",
     "platform kontrolüyle sar ya da Linux karşılığını kullan"),
    (re.compile(r"\b(?:import|from)\s+(win32\w*|pywintypes|pythoncom|comtypes|pywinauto|wmi|winshell)\b"),
     "pywin32/COM kullanımı", "Linux karşılığı gerekir (pano: pyperclip, pencere: xdotool/wmctrl)"),
    (re.compile(r"\bctypes\.windll\b|\bWinDLL\b"), "ctypes.windll", "Linux'ta yok; platform kontrolü gerekir"),
    (re.compile(r"\bpowershell(?:\.exe)?\b", re.I), "PowerShell çağrısı", "bash ya da Python karşılığı gerekir"),
    (re.compile(r"\bcmd(?:\.exe)?\s+/c\b", re.I), "cmd /c çağrısı", "doğrudan komutu çalıştır"),
    (re.compile(r"\\Scripts\\(?:python|activate|pip)", re.I), "Windows sanal ortam yolu",
     "Linux: .venv/bin/python · source .venv/bin/activate"),
    (re.compile(r"\bCREATE_NO_WINDOW\b|\bSTARTUPINFO\b|\bcreationflags\b"), "Windows süreç bayrağı",
     "Linux'ta gereksiz; `if os.name == 'nt'` ile sar"),
    (re.compile(r"os\.system\(\s*['\"](?:cls|pause)\b"), "cls/pause", "Linux: 'clear' / input()"),
]
TARANAN_UZANTILAR = {".py", ".js", ".mjs", ".cjs", ".ts", ".json", ".yaml", ".yml", ".toml", ".ini", ".cfg", ".md", ".sh"}


def uyumluluk_tara(proje: Path) -> dict:
    bulgular, betikler, crlf_duzeltilen = [], [], []
    for d, _, dosyalar in gezin(proje, 6):
        for ad in dosyalar:
            f = d / ad
            uz = f.suffix.lower()
            rel = str(f.relative_to(proje))
            if uz in (".bat", ".cmd", ".ps1"):
                betikler.append(rel)
                continue
            gizli = ad.lower() == ".env" or ad.lower().startswith(".env.")
            if not gizli and uz not in TARANAN_UZANTILAR:
                continue
            try:
                if f.stat().st_size > 2_000_000:
                    continue
                ham = f.read_bytes()
            except OSError:
                continue
            if uz == ".sh" and b"\r\n" in ham:
                f.write_bytes(ham.replace(b"\r\n", b"\n"))
                crlf_duzeltilen.append(rel)
            metin = ham.decode("utf-8", "replace")
            sayac = 0
            for no, satir in enumerate(metin.splitlines(), 1):
                for desen, tur, oneri in UYUMLULUK_DESENLERI:
                    if desen.search(satir):
                        if gizli:  # .env değerini asla yazma
                            anahtar = satir.split("=", 1)[0].strip()
                            ornek = f"{anahtar}=… (değer gizlendi)"
                        else:
                            ornek = satir.strip()[:140]
                        bulgular.append({"dosya": rel, "satir": no, "tur": tur, "oneri": oneri, "ornek": ornek})
                        sayac += 1
                        break
                if sayac >= 15:
                    break
    return {"bulgular": bulgular, "windows_betikleri": betikler, "crlf_duzeltilen": crlf_duzeltilen}


def json_al(cikti: str):
    """proje_denetim.py çıktısındaki son '@@JSON@@' satırını çözer."""
    satirlar = [s for s in cikti.splitlines() if s.startswith("@@JSON@@")]
    if not satirlar:
        raise ValueError("JSON yok")
    return json.loads(satirlar[-1][len("@@JSON@@"):])


def denetim(py: Path, kok: Path) -> dict:
    kod, cikti = calistir([py, "-I", DENETIM_BETIGI, "tara", kok], zaman_asimi=600, sessiz=True)
    try:
        return json_al(cikti)
    except ValueError:
        return {"hata": cikti[-500:]}


def modul_testi(py: Path, moduller: list[str]) -> dict:
    if not moduller:
        return {}
    kod, cikti = calistir([py, "-I", DENETIM_BETIGI, "ice-aktar", *moduller], zaman_asimi=3600, sessiz=True)
    try:
        return json_al(cikti)
    except ValueError:
        return {m: {"durum": "hata", "mesaj": "test çalıştırılamadı: " + cikti[-200:]} for m in moduller}


def pip_adi(modul: str, tam_adlar: set[str]) -> str | None:
    if modul in WINDOWS_MODULLERI:
        return None
    if modul == "google":
        for tam, paket in GOOGLE_ALT.items():
            if any(a == tam or a.startswith(tam + ".") for a in tam_adlar):
                return paket
        m = next((a for a in tam_adlar if a.startswith("google.cloud.")), None)
        return f"google-cloud-{m.split('.')[2]}" if m else None
    return IMPORT_PIP.get(modul, modul.replace("_", "-"))


def apt_onerisi(mesaj: str) -> str | None:
    for anahtar, paket in PAYLASIMLI_KUTUPHANE.items():
        if anahtar in mesaj:
            return paket
    return None


def kok_test_et(kurucu: Kurucu, kok: Path, ortamlar: list[Ortam]) -> dict:
    sonuc = {"sozdizimi": [], "eksik": [], "hatali": [], "windows_modulleri": [], "gpu": [], "pytest": None,
             "toplam_modul": 0}
    calisan = [o for o in ortamlar if o.py.exists()]
    if not calisan:
        return sonuc
    ana = calisan[0]
    tarama = denetim(ana.py, kok)
    if "hata" in tarama:
        uyari(f"{kok.name}: kaynak taraması yapılamadı.")
        return sonuc
    sonuc["sozdizimi"] = tarama["sozdizimi_hatalari"]
    disari = sorted(set(tarama["ucuncu_parti"]))
    sonuc["windows_modulleri"] = sorted(set(tarama["windows_modulleri"]))
    sonuc["toplam_modul"] = len(disari)
    durumlar = {o.ad: modul_testi(o.py, disari) for o in calisan}
    for m in disari:
        tum = [durumlar[o.ad].get(m, {}) for o in calisan]
        if any(t.get("durum") == "tamam" for t in tum):
            continue
        if all(t.get("durum") == "yok" for t in tum):
            sonuc["eksik"].append(m)
        else:
            mesaj = next((t.get("mesaj", "") for t in tum if t.get("durum") == "hata"), "")
            sonuc["hatali"].append({"modul": m, "mesaj": mesaj, "apt": apt_onerisi(mesaj)})

    if sonuc["eksik"]:
        paketler = sorted({p for m in sonuc["eksik"] if (p := pip_adi(m, set(tarama["tam_adlar"])))})
        uyari(f"{kok.name}: kodun kullandığı ama ortamda olmayan modüller: {', '.join(sonuc['eksik'])}")
        if paketler and onay(f"  Bunlar {ana.ad} ortamına kurulsun mu? ({' '.join(paketler)})", "e"):
            kod, cikti = kurucu.pip(ana, paketler)
            if kod != 0:
                kuyruk(cikti, 6)
                kod = 0
                for p in paketler:  # tek tek dene: biri bulunamasa da diğerleri kurulsun
                    k, _ = kurucu.pip(ana, [p])
                    kod |= k
            yeni = modul_testi(ana.py, sonuc["eksik"])
            kalan = [m for m in sonuc["eksik"] if yeni.get(m, {}).get("durum") != "tamam"]
            ana.notlar.append(f"Eksik modüller tamamlandı: {', '.join(sorted(set(sonuc['eksik']) - set(kalan))) or '—'}")
            sonuc["eksik"] = kalan

    # GPU kontrolü
    for o in calisan:
        pk = kurucu.kurulu_paketler(o)
        if "torch" in pk:
            _, c = calistir([o.py, "-I", "-c", "import torch;print(torch.cuda.is_available(), "
                             "torch.cuda.get_device_name(0) if torch.cuda.is_available() else '')"],
                            sessiz=True, zaman_asimi=300)
            sonuc["gpu"].append(f"{o.ad}: torch CUDA = {c.strip().splitlines()[-1] if c.strip() else '?'}")
        if "ctranslate2" in pk:
            env = dict(os.environ)
            etk = o.yol / "bin" / "activate"
            m = re.search(r'export LD_LIBRARY_PATH="([^"$]+)', etk.read_text(encoding="utf-8")) if etk.exists() else None
            if m:
                env["LD_LIBRARY_PATH"] = m.group(1) + ":" + env.get("LD_LIBRARY_PATH", "")
            _, c = calistir([o.py, "-I", "-c", "import ctranslate2;print(ctranslate2.get_cuda_device_count())"],
                            sessiz=True, env=env, zaman_asimi=300)
            sonuc["gpu"].append(f"{o.ad}: ctranslate2 GPU sayısı = {c.strip().splitlines()[-1] if c.strip() else '?'}")

    # İsteğe bağlı pytest (projenin kendi testleri; ağ/API çağırabilir → varsayılan hayır)
    if tarama.get("test_var") and "pytest" in kurucu.kurulu_paketler(ana):
        if onay(f"  {kok.name} içinde testler var. pytest çalıştırılsın mı? (testler API çağırıyorsa dikkat)", "h"):
            kod, cikti = calistir([ana.py, "-m", "pytest", "-q", "-x"], cwd=kok, zaman_asimi=900)
            sonuc["pytest"] = "geçti" if kod == 0 else "başarısız"
            kuyruk(cikti, 5)
    return sonuc


# ---------------------------------------------------------------------------
# 5) Video üretim hattı testi (edge-tts + ffmpeg + NVENC)
# ---------------------------------------------------------------------------
def arac_bul(ad: str) -> str | None:
    yol = shutil.which(ad)
    if yol:
        return yol
    aday = Path.home() / ".local" / "bin" / ad
    return str(aday) if aday.exists() else None


def hat_testi(hedef: Path) -> dict:
    baslik("Video üretim hattı testi (Linux): edge-tts → ffmpeg Ken Burns → altyazı → ffprobe")
    sonuc = {}
    klasor = hedef / ".istasyon-test"
    klasor.mkdir(exist_ok=True)
    ffmpeg, ffprobe = arac_bul("ffmpeg"), arac_bul("ffprobe")
    if not ffmpeg or not ffprobe:
        hata("ffmpeg/ffprobe yok (2. aşamada kurulur).")
        return {"ffmpeg": "YOK"}
    ses, srt = klasor / "ses.mp3", klasor / "altyazi.srt"
    edge = arac_bul("edge-tts")
    if edge:
        kod, cikti = calistir([edge, "--voice", "tr-TR-AhmetNeural", "--rate=+8%", "--text",
                               "Merhaba! Bu, Linux üzerinde video üretim hattının testidir.",
                               "--write-media", ses, "--write-subtitles", srt], zaman_asimi=90)
        sonuc["edge-tts"] = "tamam" if kod == 0 and ses.exists() and ses.stat().st_size > 0 else "HATA (ağ?)"
        if sonuc["edge-tts"] != "tamam":
            kuyruk(cikti, 4)
    else:
        sonuc["edge-tts"] = "YOK (2. aşamada pipx ile kurulur)"
    if sonuc["edge-tts"] != "tamam":
        calistir([ffmpeg, "-y", "-f", "lavfi", "-i", "sine=frequency=440:duration=3", ses], sessiz=True)
        srt.write_text("1\n00:00:00,000 --> 00:00:03,000\nLinux test altyazısı\n", encoding="utf-8")
    _, sure = calistir([ffprobe, "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", ses], sessiz=True)
    try:
        saniye = float(sure.strip().splitlines()[-1])
    except (ValueError, IndexError):
        saniye = 3.0
    kare = int(saniye * 30) + 15
    calistir([ffmpeg, "-y", "-f", "lavfi", "-i", "gradients=s=1080x1920:c0=0x14213d:c1=0x2f55d4:d=1",
              "-frames:v", "1", klasor / "sahne.png"], sessiz=True)
    if not (klasor / "sahne.png").exists():
        calistir([ffmpeg, "-y", "-f", "lavfi", "-i", "color=c=0x1d2a4a:s=1080x1920:d=1", "-frames:v", "1",
                  klasor / "sahne.png"], sessiz=True)
    kod, cikti = calistir([ffmpeg, "-y", "-i", klasor / "sahne.png", "-vf",
                           "scale=2160:3840,zoompan=z='min(zoom+0.0008,1.15)':x='iw/2-(iw/zoom/2)':"
                           f"y='ih/2-(ih/zoom/2)':d={kare}:s=1080x1920:fps=30",
                           "-c:v", "libx264", "-pix_fmt", "yuv420p", klasor / "s1.mp4"], zaman_asimi=300)
    sonuc["ken-burns (zoompan + libx264)"] = "tamam" if kod == 0 else "HATA"
    if kod != 0:
        kuyruk(cikti, 4)
    kod, cikti = calistir([ffmpeg, "-y", "-i", klasor / "s1.mp4", "-i", ses, "-vf",
                           f"subtitles={srt.name}:force_style='Bold=1,FontSize=16,Outline=3,Alignment=2,MarginV=120'",
                           "-c:v", "libx264", "-c:a", "aac", "-shortest", "final.mp4"], cwd=klasor, zaman_asimi=300)
    sonuc["altyazı (libass) + ses"] = "tamam" if kod == 0 else "HATA"
    if kod != 0:
        kuyruk(cikti, 4)
    final = klasor / "final.mp4"
    if final.exists():
        _, bilgi_ = calistir([ffprobe, "-v", "error", "-show_entries", "stream=codec_type,width,height,r_frame_rate",
                              "-of", "json", final], sessiz=True)
        try:
            akislar = json.loads(bilgi_)["streams"]
            v = next(a for a in akislar if a["codec_type"] == "video")
            ses_var = any(a["codec_type"] == "audio" for a in akislar)
            ok = v["width"] == 1080 and v["height"] == 1920 and v["r_frame_rate"] == "30/1" and ses_var
            sonuc["ffprobe 1080x1920 · 30 fps · ses"] = "tamam" if ok else f"BEKLENMEDİK: {v['width']}x{v['height']}"
        except (ValueError, KeyError, StopIteration):
            sonuc["ffprobe 1080x1920 · 30 fps · ses"] = "HATA"
    _, enc = calistir([ffmpeg, "-hide_banner", "-encoders"], sessiz=True)
    if "h264_nvenc" in enc:
        kod, _ = calistir([ffmpeg, "-y", "-f", "lavfi", "-i", "testsrc2=s=1080x1920:d=1", "-c:v", "h264_nvenc",
                           klasor / "nvenc.mp4"], sessiz=True, zaman_asimi=120)
        sonuc["NVENC (RTX ile hızlı kodlama)"] = "tamam" if kod == 0 else "derlemede var ama çalışmadı (sürücü?)"
        (klasor / "nvenc.mp4").unlink(missing_ok=True)
    else:
        sonuc["NVENC (RTX ile hızlı kodlama)"] = "bu ffmpeg derlemesinde yok"
    sonuc["yt-dlp"] = "tamam" if arac_bul("yt-dlp") else "YOK"
    for ara in ("sahne.png", "s1.mp4"):
        (klasor / ara).unlink(missing_ok=True)
    for ad, durum in sonuc.items():
        (basarili if durum == "tamam" else uyari)(f"{ad}: {durum}")
    if final.exists():
        not_yaz(f"Örnek çıktı: {final} (VLC ile izleyebilirsin)")
    return sonuc


# ---------------------------------------------------------------------------
# 6) Raporlar
# ---------------------------------------------------------------------------
def vscode_dosyalari(hedef: Path, projeler: list[Path], kok_ortamlari: dict) -> None:
    dosya = hedef / "Projeler.code-workspace"
    calisma = {"folders": [], "settings": {"python.terminal.activateEnvironment": True}}
    if dosya.exists():  # önceki çalıştırmalardan kalan klasörleri koru
        try:
            calisma = json.loads(dosya.read_text(encoding="utf-8"))
        except ValueError:
            pass
    mevcut = {f.get("path") for f in calisma.get("folders", [])}
    for p in projeler:
        rel = str(p.relative_to(hedef))
        if rel not in mevcut:
            calisma.setdefault("folders", []).append({"path": rel})
    dosya.write_text(json.dumps(calisma, ensure_ascii=False, indent=2) + "\n",
                                                   encoding="utf-8")
    for proje in projeler:
        ayar = proje / ".vscode" / "settings.json"
        if ayar.exists():
            continue
        ortamlar = [o for k, oo in kok_ortamlari.items() if k == proje for o in oo if o.py.exists()]
        if not ortamlar:
            continue
        ayar.parent.mkdir(exist_ok=True)
        ayar.write_text(json.dumps({"python.defaultInterpreterPath": f"${{workspaceFolder}}/{ortamlar[0].ad}/bin/python"},
                                   indent=2) + "\n", encoding="utf-8")


def raporla(hedef: Path, kayitlar: list[dict], hat: dict) -> Path:
    zaman = dt.datetime.now().strftime("%Y-%m-%d %H:%M")
    s = [f"# Projeler — Linux kurulum raporu\n", f"_{zaman} · ubuntu-istasyon/40-projeler.sh_\n"]
    s.append("## Projeler\n")
    s.append("| Proje | Klasör | Sanal ortamlar | Sözdizimi | Bağımlılıklar | Uyumluluk |")
    s.append("|---|---|---|---|---|---|")
    for k in kayitlar:
        ortam = "<br>".join(f"`{o['ad']}` Py {o['python']} — {o['kurulum']}" for o in k["ortamlar"]) or "—"
        soz = "✔" if not k["sozdizimi"] else f"✖ {len(k['sozdizimi'])} dosya"
        if k["toplam_modul"] == 0 and not k["ortamlar"]:
            bag = "—"
        else:
            sorun = len(k["eksik"]) + len(k["hatali"])
            bag = f"✔ {k['toplam_modul']} modül" if not sorun else f"⚠ {sorun}/{k['toplam_modul']} sorunlu"
        uy = len(k["uyumluluk"]["bulgular"]) + len(k["uyumluluk"]["windows_betikleri"])
        s.append(f"| {k['ad']} | `{k['yol']}` | {ortam} | {soz} | {bag} | {'✔' if not uy else f'⚠ {uy} bulgu'} |")
    s.append("\n## Video üretim hattı testi\n")
    for ad, durum in hat.items():
        s.append(f"- {'✔' if durum == 'tamam' else '⚠'} **{ad}**: {durum}")
    s.append("\n## Ayrıntılar\n")
    for k in kayitlar:
        s.append(f"### {k['ad']}\n")
        s.append(f"- Klasör: `{k['yol']}`")
        for o in k["ortamlar"]:
            s.append(f"- Ortam `{o['ad']}`: `source {o['yol']}/bin/activate` · kaynak: {', '.join(o['kaynaklar']) or 'kod içe aktarmaları'}")
            for n in o["notlar"]:
                s.append(f"  - {n}")
        for d in k["sozdizimi"]:
            s.append(f"- ✖ Sözdizimi hatası: `{d['dosya']}` satır {d['satir']}: {d['mesaj']}")
        if k["eksik"]:
            s.append(f"- ⚠ Kurulamayan modüller: {', '.join(k['eksik'])}")
        for h in k["hatali"]:
            ek = f" → `sudo apt install {h['apt']}`" if h["apt"] else ""
            s.append(f"- ⚠ `{h['modul']}` içe aktarılırken hata: {h['mesaj'][:200]}{ek}")
        if k["windows_modulleri"]:
            s.append(f"- ⚠ Windows'a özgü modüller: {', '.join(k['windows_modulleri'])} (Linux karşılığı gerekir)")
        for g in k["gpu"]:
            s.append(f"- GPU: {g}")
        if k["pytest"]:
            s.append(f"- pytest: {k['pytest']}")
        s.append("")
    s.append("## Linux uyumluluk bulguları\n")
    s.append("Kod otomatik DEĞİŞTİRİLMEDİ (yalnızca .sh dosyalarındaki Windows satır sonları düzeltildi). "
             "Aşağıdaki satırlar Linux'ta düzenleme gerektirebilir:\n")
    for k in kayitlar:
        u = k["uyumluluk"]
        if not (u["bulgular"] or u["windows_betikleri"] or u["crlf_duzeltilen"]):
            continue
        s.append(f"### {k['ad']}\n")
        if u["windows_betikleri"]:
            s.append(f"- Windows betikleri (Linux'ta çalışmaz, karşılığı gerekir): "
                     + ", ".join(f"`{b}`" for b in u["windows_betikleri"][:30]))
        if u["crlf_duzeltilen"]:
            s.append(f"- Satır sonu düzeltilen .sh dosyaları: " + ", ".join(f"`{b}`" for b in u["crlf_duzeltilen"]))
        for b in u["bulgular"][:150]:
            s.append(f"- `{b['dosya']}:{b['satir']}` — **{b['tur']}** → {b['oneri']}<br>`{b['ornek']}`")
        s.append("")
    rapor = hedef / "PROJELER_RAPORU.md"
    if rapor.exists():  # önceki raporu sakla
        eski = dt.datetime.fromtimestamp(rapor.stat().st_mtime).strftime("%Y-%m-%d_%H%M%S")
        rapor.rename(hedef / f"PROJELER_RAPORU_{eski}.md")
    rapor.write_text("\n".join(s) + "\n", encoding="utf-8")
    return rapor


# ---------------------------------------------------------------------------
def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--zip", required=True)
    ap.add_argument("--hedef", required=True)
    ap.add_argument("--python", default="3.12")
    ap.add_argument("--uv", default=shutil.which("uv") or str(Path.home() / ".local/bin/uv"))
    ap.add_argument("--hat-testi", choices=("sor", "evet", "hayir"), default="sor")
    a = ap.parse_args()

    zip_yolu = Path(a.zip).expanduser().resolve()
    hedef = Path(a.hedef).expanduser().resolve()
    hedef.mkdir(parents=True, exist_ok=True)
    if not Path(a.uv).exists():
        hata(f"uv bulunamadı ({a.uv}). Önce 2. aşamayı (programlar) çalıştır.")
        return 1

    gelen = hedef / "_gelen" / zip_yolu.stem
    if gelen.exists():
        gelen = gelen.with_name(f"{zip_yolu.stem}_{dt.datetime.now():%H%M%S}")
    gelen.mkdir(parents=True)
    zip_ac(zip_yolu, gelen)

    baslik("Yerleşim planı")
    plan = plan_olustur(gelen, hedef)
    if not plan:
        uyari("Zip içinde proje bulunamadı.")
        return 1
    plan_dosyasi = hedef / ".yerlesim-plani.tsv"
    while True:
        plan_goster(plan, hedef)
        c = secim("Bu plan uygulansın mı? [E]vet / [d]üzenle / [h]ayır:", ("e", "d", "h"), "e")
        if c == "e":
            break
        if c == "h":
            uyari(f"İptal edildi. Açılan dosyalar şurada duruyor: {gelen}")
            return 1
        with open(plan_dosyasi, "w", encoding="utf-8") as f:
            f.write("# kaynak\thedef (~/Projeler'e göre)\tneden — yalnızca 2. sütunu değiştir\n")
            for p in plan:
                f.write("\t".join(p) + "\n")
        duzenleyici = os.environ.get("EDITOR") or shutil.which("nano") or "vi"
        subprocess.call([duzenleyici, str(plan_dosyasi)])
        yeni = []
        for satir in plan_dosyasi.read_text(encoding="utf-8").splitlines():
            if satir.startswith("#") or not satir.strip():
                continue
            parca = satir.split("\t")
            if len(parca) >= 2:
                yeni.append([parca[0], parca[1], parca[2] if len(parca) > 2 else "elle"])
        plan = yeni
    projeler = plan_uygula(plan, gelen, hedef)
    if not projeler:
        uyari(f"Yeni yerleştirilen öğe yok (hepsi zaten ~/{hedef.name} altında); mevcut ortamlar ve rapor korunuyor.")
        not_yaz(f"Açılan kopya şurada duruyor, işin bitince silebilirsin: {gelen}")
        return 0
    basarili(f"{len(projeler)} öğe ~/{hedef.name} altına yerleştirildi.")
    if gelen.exists() and any(gelen.iterdir()):
        uyari(f"Taşınamayan öğeler geçici klasörde kaldı: {gelen}")
    elif gelen.parent.exists() and not any(gelen.parent.iterdir()):
        gelen.parent.rmdir()

    gpu = calistir(["nvidia-smi"], sessiz=True)[0] == 0
    kurucu = Kurucu(a.uv, a.python, gpu)
    kayitlar, kok_ortamlari = [], {}
    proje_dizinleri = [p for p in projeler if p.is_dir()]
    for proje in proje_dizinleri:
        baslik(f"Proje: {proje.relative_to(hedef)}")
        kokler = ortam_koklerini_bul(proje)
        if not kokler:
            not_yaz("Python kodu yok; sanal ortam gerekmiyor.")
        for kok in kokler:
            plan_ortam = ortamlari_planla(kok, a.python)
            if not plan_ortam:
                plan_ortam = [(Ortam(kok, ".venv", python_surumu_sec(kok, None, a.python)), [])]
            ortamlar = []
            for o, kaynaklar in plan_ortam:
                ortamlar.append(o)
                if not kurucu.olustur(o):
                    o.kurulum = "oluşturulamadı"
                    continue
                if not kaynaklar:
                    o.kurulum = "kod içe aktarmalarından"
                for etiket, satirlar in kaynaklar:
                    o.kaynaklar.append(etiket)
                    if etiket.startswith("Windows'taki"):
                        mevcut = kurucu.kurulu_paketler(o)
                        satirlar = [s for s in satirlar if normal_ad(s.split("==")[0]) not in mevcut]
                        if not satirlar:
                            continue
                    kurucu.gereksinim_kur(o, satirlar, etiket)
                kurucu.cuda_kutuphaneleri(o)
            kok_ortamlari[kok] = ortamlar
            test = kok_test_et(kurucu, kok, ortamlar)
            uyum = uyumluluk_tara(kok)
            ad = str(kok.relative_to(hedef))
            sorun = len(test["eksik"]) + len(test["hatali"])
            (basarili if not sorun and not test["sozdizimi"] else uyari)(
                f"{ad}: {test['toplam_modul']} bağımlılık modülü içe aktarıldı ({sorun} sorunlu), "
                f"{len(test['sozdizimi'])} sözdizimi hatalı dosya, {len(uyum['bulgular'])} Linux uyumluluk bulgusu.")
            kayitlar.append({
                "ad": ad, "yol": str(kok).replace(str(Path.home()), "~"),
                "ortamlar": [{"ad": o.ad, "python": o.python_surumu, "kurulum": o.kurulum, "kaynaklar": o.kaynaklar,
                              "notlar": o.notlar, "yol": str(o.yol).replace(str(Path.home()), "~")} for o in ortamlar],
                **test, "uyumluluk": uyum,
            })
        if not kokler:
            uyum = uyumluluk_tara(proje)
            kayitlar.append({"ad": str(proje.relative_to(hedef)), "yol": str(proje).replace(str(Path.home()), "~"),
                             "ortamlar": [], "sozdizimi": [], "eksik": [], "hatali": [], "windows_modulleri": [],
                             "gpu": [], "pytest": None, "toplam_modul": 0, "uyumluluk": uyum})
        paket_json = [d / "package.json" for d, _, f in gezin(proje, 3) if "package.json" in f]
        for pj in paket_json:
            if onay(f"  Node.js projesi: {pj.parent.relative_to(hedef)} — npm bağımlılıkları kurulsun mu?", "e"):
                npm = shutil.which("npm")
                if not npm:
                    uyari("npm yok (2. aşamada kurulur).")
                    break
                komut = [npm, "ci"] if (pj.parent / "package-lock.json").exists() else [npm, "install"]
                kod, cikti = calistir(komut, cwd=pj.parent, zaman_asimi=1800)
                (basarili if kod == 0 else uyari)(f"{pj.parent.name}: npm {'tamam' if kod == 0 else 'HATA'}")
                if kod != 0:
                    kuyruk(cikti, 6)

    hat = {}
    if a.hat_testi == "evet" or (a.hat_testi == "sor" and onay(
            "Video üretim hattı testi yapılsın mı? (edge-tts ile kısa ses + ffmpeg ile 1080x1920 örnek video; internet gerekir)", "e")):
        hat = hat_testi(hedef)

    vscode_dosyalari(hedef, proje_dizinleri, kok_ortamlari)
    rapor = raporla(hedef, kayitlar, hat)
    (hedef / ".son-kurulum.json").write_text(json.dumps(
        {"zaman": dt.datetime.now().isoformat(timespec="seconds"), "zip": zip_yolu.name,
         "projeler": [k["ad"] for k in kayitlar],
         "ozet": {k["ad"]: {"eksik": k["eksik"], "hatali": [h["modul"] for h in k["hatali"]],
                            "sozdizimi": len(k["sozdizimi"]), "uyumluluk": len(k["uyumluluk"]["bulgular"])}
                  for k in kayitlar}}, ensure_ascii=False, indent=2), encoding="utf-8")
    print()
    basarili(f"Rapor: {rapor}")
    basarili(f"VS Code çalışma alanı: {hedef / 'Projeler.code-workspace'}  (code {hedef / 'Projeler.code-workspace'})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
