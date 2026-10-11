#!/usr/bin/env python3
"""Projenin SANAL ORTAMINDAKİ Python ile çalıştırılır (projeler.py çağırır).

  proje_denetim.py tara KÖK          → sözdizimi hataları + üçüncü parti içe aktarmalar (JSON)
  proje_denetim.py ice-aktar MOD...  → her modülü ayrı süreçte içe aktarmayı dener (JSON)

Projenin kendi kodu çalıştırılmaz; yalnızca ast ile okunur.
"""
import ast
import json
import os
import subprocess
import sys

ISARET = "@@JSON@@"
ATLA = {"__pycache__", "node_modules", ".git", ".pytest_cache", ".mypy_cache", ".ruff_cache", ".ipynb_checkpoints"}
WINDOWS = {
    "winreg", "_winreg", "msvcrt", "winsound", "_winapi", "win32api", "win32con", "win32gui", "win32com",
    "win32clipboard", "win32process", "win32file", "win32event", "win32service", "pywintypes", "pythoncom",
    "wmi", "comtypes", "pywinauto", "winshell", "win10toast", "winotify",
}
HATA_TURLERI = {"ImportError", "ModuleNotFoundError", "Exception", "BaseException"}


def py_dosyalari(kok):
    for d, dizinler, dosyalar in os.walk(kok):
        dizinler[:] = [x for x in dizinler if x not in ATLA and not os.path.exists(os.path.join(d, x, "pyvenv.cfg"))]
        for f in dosyalar:
            if f.endswith(".py"):
                yield os.path.join(d, f)


def yerel_adlar(kok):
    adlar = set()
    for d, dizinler, dosyalar in os.walk(kok):
        dizinler[:] = [x for x in dizinler if x not in ATLA and not os.path.exists(os.path.join(d, x, "pyvenv.cfg"))]
        adlar.update(dizinler)
        adlar.update(f[:-3] for f in dosyalar if f.endswith(".py"))
    return adlar


def korumali_mi(dugum, ebeveyn):
    """try/except ImportError içinde ya da Windows'a özel if bloğunda mı?"""
    p = ebeveyn.get(dugum)
    while p is not None:
        if isinstance(p, ast.Try):
            for h in p.handlers:
                if h.type is None:
                    return "istege_bagli"
                adlar = {getattr(t, "id", getattr(t, "attr", "")) for t in
                         (h.type.elts if isinstance(h.type, ast.Tuple) else [h.type])}
                if adlar & HATA_TURLERI:
                    return "istege_bagli"
        if isinstance(p, ast.If):
            kosul = ast.unparse(p.test) if hasattr(ast, "unparse") else ""
            if any(k in kosul for k in ("win32", "'nt'", '"nt"', "Windows", "windows")):
                return "windows"
        p = ebeveyn.get(p)
    return None


def tara(kok):
    stdlib = set(getattr(sys, "stdlib_module_names", ())) | set(sys.builtin_module_names)
    yerel = yerel_adlar(kok)
    sozdizimi, ucuncu, windows, tam_adlar = [], set(), set(), set()
    test_var = False
    for yol in py_dosyalari(kok):
        rel = os.path.relpath(yol, kok)
        ad = os.path.basename(yol)
        if ad.startswith("test_") or ad.endswith("_test.py") or os.sep + "tests" + os.sep in os.sep + rel:
            test_var = True
        try:
            with open(yol, "rb") as f:
                agac = ast.parse(f.read(), filename=rel)
        except SyntaxError as e:
            sozdizimi.append({"dosya": rel, "satir": e.lineno or 0, "mesaj": e.msg})
            continue
        except (ValueError, OSError) as e:
            sozdizimi.append({"dosya": rel, "satir": 0, "mesaj": str(e)})
            continue
        ebeveyn = {}
        for d in ast.walk(agac):
            for c in ast.iter_child_nodes(d):
                ebeveyn[c] = d
        for d in ast.walk(agac):
            if isinstance(d, ast.Import):
                isimler = [a.name for a in d.names]
            elif isinstance(d, ast.ImportFrom) and d.level == 0 and d.module:
                isimler = [d.module]
            else:
                continue
            koruma = korumali_mi(d, ebeveyn)
            for tam in isimler:
                ust = tam.split(".")[0]
                if koruma:  # try/except ImportError ya da Windows'a özel if: Linux'ta sorun çıkarmaz
                    continue
                if ust in WINDOWS:
                    windows.add(ust)
                    continue
                if ust == "__future__" or ust in stdlib or ust in yerel:
                    continue
                ucuncu.add(ust)
                tam_adlar.add(tam)
    return {"sozdizimi_hatalari": sozdizimi, "ucuncu_parti": sorted(ucuncu), "windows_modulleri": sorted(windows),
            "tam_adlar": sorted(tam_adlar), "test_var": test_var}


DENEME = r"""
import json, sys
m = sys.argv[1]
try:
    __import__(m)
    s = {"durum": "tamam"}
except ModuleNotFoundError as e:
    s = {"durum": "yok" if (e.name or "").split(".")[0] == m else "hata", "mesaj": str(e)}
except BaseException as e:
    s = {"durum": "hata", "mesaj": type(e).__name__ + ": " + str(e)}
print("@@JSON@@" + json.dumps(s))
"""


def ice_aktar(moduller):
    sonuc = {}
    for m in moduller:
        try:
            p = subprocess.run([sys.executable, "-I", "-c", DENEME, m], capture_output=True, text=True,
                               timeout=180, errors="replace")
            satir = [s for s in p.stdout.splitlines() if s.startswith(ISARET)]
            if satir:
                sonuc[m] = json.loads(satir[-1][len(ISARET):])
            else:
                son = (p.stderr or p.stdout).strip().splitlines()
                sonuc[m] = {"durum": "hata", "mesaj": son[-1] if son else f"çıkış kodu {p.returncode}"}
        except subprocess.TimeoutExpired:
            sonuc[m] = {"durum": "hata", "mesaj": "içe aktarma 180 sn'de bitmedi"}
    return sonuc


if __name__ == "__main__":
    if len(sys.argv) >= 3 and sys.argv[1] == "tara":
        print(ISARET + json.dumps(tara(sys.argv[2]), ensure_ascii=False))
    elif len(sys.argv) >= 2 and sys.argv[1] == "ice-aktar":
        print(ISARET + json.dumps(ice_aktar(sys.argv[2:]), ensure_ascii=False))
    else:
        sys.exit(__doc__)
