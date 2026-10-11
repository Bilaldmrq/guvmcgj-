#!/usr/bin/env python3
"""Windows'ta hazırlanmış bir kod yedeğinin tipik tuzaklarını taşıyan sahte zip üretir.

Kullanım: python3 sahte_yedek_olustur.py CIKTI.zip

İçerik: CP857 kodlu Türkçe adlar (UTF-8 bayrağı yok), ters bölülü yollar, Windows .venv / .venv-asr
(dist-info + REQUESTED), zip-slip girdisi, sembolik bağ, __pycache__/node_modules, CRLF .sh,
C:\\ yolları, .env, PowerShell betiği, sözdizimi hatalı dosya, n8n iş akışı, tek başına dosya.
"""
import sys
import zipfile

CIKTI = sys.argv[1]
KOK = "kod_yedek_2026-10-11"


class Cp857Info(zipfile.ZipInfo):
    """Windows Gezgini gibi: adı OEM kod sayfasıyla yazar, UTF-8 bayrağını koymaz."""

    def _encodeFilenameFlags(self):  # noqa: N802
        return self.filename.encode("cp437"), self.flag_bits & ~0x800


def ekle(zf, ad, veri, cp857=False, ters_bolu=True, symlink=False):
    if ters_bolu:
        ad = ad.replace("/", "\\")
    if cp857:
        info = Cp857Info(ad.encode("cp857").decode("cp437"))
    else:
        info = zipfile.ZipInfo(ad)
    info.date_time = (2026, 10, 11, 20, 30, 0)
    info.compress_type = zipfile.ZIP_DEFLATED
    if symlink:
        info.external_attr = (0o120777 << 16)
    zf.writestr(info, veri)


def venv(zf, yol, python, paketler):
    ekle(zf, f"{yol}/pyvenv.cfg", f"home = C:\\Python312\nversion = {python}\ninclude-system-site-packages = false\n")
    ekle(zf, f"{yol}/Scripts/python.exe", b"MZ\x90\x00 sahte")
    for ad, surum, istenen in paketler:
        dist = f"{yol}/Lib/site-packages/{ad.replace('-', '_')}-{surum}.dist-info"
        ekle(zf, f"{dist}/METADATA", f"Metadata-Version: 2.1\nName: {ad}\nVersion: {surum}\n")
        if istenen:
            ekle(zf, f"{dist}/REQUESTED", "")
        ekle(zf, f"{yol}/Lib/site-packages/{ad.replace('-', '_')}/__init__.py", "")


with zipfile.ZipFile(CIKTI, "w") as zf:
    qw = f"{KOK}/QuietWealth"
    ekle(zf, f"{qw}/AGENT_PLAYBOOK.md",
         "# Playbook\nTek doğru kaynak: C:\\Users\\bilal\\Videos\\QuietWealth\\AGENT_PLAYBOOK.md\n")
    ekle(zf, f"{qw}/uploads_log.txt", "ep001 yüklendi\n")
    ekle(zf, f"{qw}/ep001/meta.json", '{"baslik": "Quiet money"}')
    ekle(zf, f"{qw}/requirements.txt", "requests==2.32.3\npython-dotenv==1.0.1\npywin32==306\n")
    ekle(zf, f"{qw}/main.py", (
        "import os, subprocess\nimport requests\nfrom dotenv import load_dotenv\nimport edge_tts\n"
        "try:\n    import win32gui\nexcept ImportError:\n    win32gui = None\n"
        "CIKTI = r'C:\\Users\\bilal\\Videos\\QuietWealth\\out'\n"
        "def ac(yol):\n    os.startfile(yol)\n"
        "def kodla():\n    subprocess.run(['ffmpeg.exe', '-version'])\n"
    ))
    ekle(zf, f"{qw}/asr.py", "import srt\nfrom tqdm import tqdm\n")
    ekle(zf, f"{qw}/dlg.ps1", "Write-Host DIALOG_OPEN\n")
    ekle(zf, f"{qw}/.env", "GROQ_API_KEY=gizli-anahtar-123\nCIKTI_KLASORU=C:\\Users\\bilal\\Videos\n")
    ekle(zf, f"{qw}/calistir.sh", "#!/bin/bash\r\necho merhaba\r\n")
    ekle(zf, f"{qw}/__pycache__/main.cpython-312.pyc", b"\x00\x00")
    venv(zf, f"{qw}/.venv", "3.12.4", [("edge-tts", "7.0.0", True), ("requests", "2.32.3", True),
                                         ("python-dotenv", "1.0.1", True), ("pywin32", "306", True),
                                         ("certifi", "2024.8.30", False)])
    venv(zf, f"{qw}/.venv-asr", "3.12.4", [("srt", "3.5.3", True), ("tqdm", "4.66.5", True)])

    an = f"{KOK}/Anadolu'nun Sırları"
    ekle(zf, f"{an}/üret.py", "import yaml\nfrom PIL import Image\nprint('Sırlar')\n", cp857=True)
    ekle(zf, f"{an}/bozuk.py", "def f(:\n    pass\n", cp857=True)
    ekle(zf, f"{an}/Thumbs.db", b"\x00", cp857=True)

    ekle(zf, f"{KOK}/Unsolved/senaryo.py", "import json\nimport rich\n")
    ekle(zf, f"{KOK}/Unsolved/requirements.txt", "rich==99.0.0\n")

    ekle(zf, f"{KOK}/n8n-akislar/gunluk_shorts.json",
         '{"name": "Günlük", "nodes": [{"type": "n8n-nodes-base.executeCommand", '
         '"parameters": {"command": "C:\\\\ffmpeg\\\\bin\\\\ffmpeg.exe -version"}}], "connections": {}}')

    ekle(zf, f"{KOK}/web-arac/package.json", '{"name": "web-arac", "version": "1.0.0", "private": true}')
    ekle(zf, f"{KOK}/web-arac/index.js", "console.log('merhaba')\n")
    ekle(zf, f"{KOK}/web-arac/node_modules/x/index.js", "module.exports = 1\n")

    ekle(zf, f"{KOK}/notlar.txt", "genel notlar\n")
    ekle(zf, "../kacak.txt", "zip-slip denemesi\n", ters_bolu=False)
    ekle(zf, f"{KOK}/baglanti", "/etc/passwd", symlink=True)

print(f"Sahte yedek: {CIKTI}")
