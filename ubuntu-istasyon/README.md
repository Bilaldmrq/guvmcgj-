# Ubuntu çalışma istasyonu kurulumu

**ASUS TUF Gaming A15 (RTX 3050) · Ubuntu 26.04 LTS · GNOME · Windows ile yan yana kurulu**

Bu betikler laptopu video üretimi, otomasyon ve yazılım işleri için düzenli bir çalışma istasyonuna dönüştürür.
Her aşama önce ne yapacağını ve sudo gerekip gerekmediğini söyler, onayını almadan başlamaz.
Hiçbir şeyi değiştirmeden önce ayarlarının yedeğini alır, istersen her şeyi tek komutla geri alırsın.

## Hızlı başlangıç

1. Bu klasörü laptopuna indir:
   - Tarayıcıdan (GitHub'a giriş yapmışken):
     <https://github.com/bilaldmrq/guvmcgj-/archive/refs/heads/claude/peaceful-brahmagupta-rqarjs.zip>
     İndirdikten sonra zip'i aç ve içindeki `ubuntu-istasyon` klasörünü ev klasörüne (`~/ubuntu-istasyon`) taşı.
   - ya da terminalden: `git clone -b claude/peaceful-brahmagupta-rqarjs https://github.com/bilaldmrq/guvmcgj-.git ~/istasyon-kaynak && cp -r ~/istasyon-kaynak/ubuntu-istasyon ~/ubuntu-istasyon`
2. Kod yedeğini (`kod_yedek_2026-10-11.zip`) Google Drive'dan **İndirilenler** klasörüne indir.
3. GNOME oturumunda bir terminal aç ve çalıştır:

```bash
cd ~/ubuntu-istasyon
bash kur.sh          # menü
bash kur.sh hepsi    # tüm aşamalar sırayla (her aşama yine önce onay ister)
```

> Betikleri `sudo` ile çalıştırma. Gerektiğinde şifreni kendileri ister ve neden istediklerini söyler.

## Aşamalar

| # | Betik | Ne yapar | sudo |
|---|---|---|---|
| 0 | `00-yedekle.sh` | `dconf dump /` ile tüm GNOME ayarlarını `~/ayar_yedek/`e yazar. Paket, snap, eklenti, servis ve otomatik başlatma listelerini de kaydeder. **Hiçbir şeyi değiştirmez.** | Hayır |
| 1 | `10-gorunum.sh` | Koyu stil ve mavi vurgu (Yaru koyu), Papirus-Dark simgeler, Bibata imleç, Inter + JetBrains Mono, koyu duvar kâğıdı. Dock altta, ortalı ve otomatik gizlenen. Eklentiler: Clipboard Indicator (pano geçmişi), Vitals (sıcaklık, RAM, fan), Caffeine. Masaüstü simgelerini gizlemek isteğe bağlı. | Paket kurmak için |
| 2 | `20-programlar.sh` | Chrome, VS Code, OBS, VLC, GIMP, Docker + Compose, Node.js, Python araçları (venv, pipx, uv), ffmpeg, git + LFS, yt-dlp, edge-tts, nvtop ve btop. VS Code'a JetBrains Mono ve eklentiler. Dock'a sık kullanılanlar. | Evet |
| 2b | `25-gereksizler.sh` | Ön yüklü gereksiz uygulamaları **yalnızca önerir**. Her biri için ayrı ayrı sorar, varsayılan cevap *hayır*dır. | Onay verirsen |
| 3 | `30-sistem.sh` | NVIDIA sürücüsünü kontrol eder ve gerekirse kurar. Hibrit grafiği `on-demand` yapar. Güç profillerini ve ASUS fan kiplerini kontrol eder. İsteğe bağlı %80 şarj sınırı koyar. Otomatik güvenlik güncellemelerini açar. Açılışı yavaşlatan servisleri tek tek sorar. | Evet |
| 4 | `40-projeler.sh` | Kod yedeğini `~/Projeler` altına düzenli açar. Sanal ortamları kurar ve test eder (ayrıntısı aşağıda). | Hayır |
| — | `rapor.sh` | Neyin değiştiğini listeler (`~/ayar_yedek/RAPOR.md`). | Hayır |
| — | `geri-al.sh` | Her şeyi kurulum öncesine döndürür. | Servisler/dosyalar için |

## Güvenlik kuralları

- **İlk yedek asla değişmez:** `~/ayar_yedek/dconf-ilk.ini`. Her aşamadan önce ayrıca anlık bir yedek alınır (`~/ayar_yedek/anlik/`).
- **GRUB, `/etc/default/grub`, fstab ve Windows bölümü hiçbir aşamada değiştirilmez.** GRUB bekleme süresine de dokunulmaz.
- Onaysız hiçbir şey silinmez. Servisler silinmez, yalnızca açılışta başlatılmaz (`disable`). Uygulamalar `remove` ile kaldırılır, `purge` kullanılmaz.
- Secure Boot'ta MOK kaydı isteyip açılış sürecine karışmasın diye OBS'in `v4l2loopback-dkms` önerisi kurulmaz. NVIDIA için Ubuntu'nun imzalı hazır modülleri kullanılır.
- Değiştirilen her ayar, dosya, servis ve paket `~/ayar_yedek/degisiklikler.log` dosyasına yazılır.

## Geri alma

```bash
bash ~/ayar_yedek/geri-al.sh                    # her şey (ayarlar, eklentiler, servisler, sistem dosyaları)
bash ~/ayar_yedek/geri-al.sh --sadece-ayarlar   # yalnızca GNOME görünüm/ayarları, sudo istemez
```

Kurulan programlar ayar sayılmadığı için varsayılan olarak kaldırılmaz; geri alma sırasında istersen kaldırılmalarını seçebilirsin.
Kaldırdığın ön yüklü uygulamaları yeniden kurmayı da teklif eder.

## Çalışma alanı (`40-projeler.sh`)

```
~/Projeler/
├── Kanallar/      QuietWealth, Unsolved, Anadolu'nun Sırları … (video üretim projeleri)
├── Otomasyon/     n8n iş akışları, botlar, JARVIS …
├── Yazilim/       diğer kod projeleri
├── Diger/         kod içermeyen klasörler ve tek başına dosyalar
├── Projeler.code-workspace   → VS Code'da hepsini birlikte aç
└── PROJELER_RAPORU.md        → ortamlar, test sonuçları, Linux uyumluluk bulguları
```

- Zip, Türkçe dosya adları (Windows CP857) ve ters bölülü yollar düzeltilerek açılır. `..`, mutlak yol ya da sembolik bağ içeren girdiler atlanır.
- Önce yerleşim planını gösterir. `d` ile planı düzenleyebilir, `h` ile vazgeçebilirsin. Var olan klasörlerin üzerine yazmaz.
- Windows'taki `.venv` / `.venv-asr` klasörleri Linux'ta çalışmaz. Bunlar açılmaz, ama içlerindeki paket listesi ve Python sürümü okunur ve ortam Linux'ta **aynı adla** yeniden kurulur ([uv](https://docs.astral.sh/uv/) ile). `requirements.txt`'de eksik kalan paketler bu kayıttan tamamlanır. `pywin32` gibi yalnızca Windows'ta çalışan paketler atlanır.
- Sabit sürüm Linux'ta bulunamazsa kurulum, sürüm serbest bırakılarak yeniden denenir.
- faster-whisper / ctranslate2 varsa RTX 3050 için cuBLAS ve cuDNN eklenir.
- **Test:** sözdizimi denetimi, her bağımlılığın ayrı süreçte içe aktarılması, GPU kontrolü (torch / ctranslate2) ve edge-tts → ffmpeg Ken Burns → altyazı → 1080x1920 örnek video. NVENC ayrıca denenir.
- **Projelerin kendi betikleri çalıştırılmaz.** Böylece yanlışlıkla video yüklenmez ya da API kotası harcanmaz.
- Kod otomatik değiştirilmez. `C:\` yolları, `.exe` çağrıları, PowerShell ve `os.startfile` gibi Linux'ta düzeltilmesi gereken satırlar rapora yazılır. `.env` değerleri rapora hiçbir zaman yazılmaz ve izinleri 600 yapılır.

## ASUS için öneri

Fan kipleri (Sessiz / Dengeli / Turbo) ve şarj sınırı, ek yazılım gerekmeden çekirdek ve GNOME ile çalışır. Güç kipini Hızlı Ayarlar'dan ya da Fn+F5 ile değiştirebilirsin.
Özel fan eğrisi ve klavye RGB istersen [asusctl](https://asus-linux.org) uygundur, ama Ubuntu'da kaynak koddan derlenmesi gerekir.
`supergfxctl` kurma: Ubuntu'nun `prime-select` düzeniyle çakışır.

## Dosyalar

```
kur.sh                 ana menü
00-yedekle.sh … 40-projeler.sh   aşamalar
geri-al.sh, rapor.sh   geri alma ve rapor (yedek klasörüne de kopyalanır)
lib/ortak.sh           ortak yardımcılar (onay, sudo, kayıt, gsettings, apt)
lib/projeler.py        zip açma, yerleşim, sanal ortam, test, rapor (yalnızca standart kütüphane)
lib/proje_denetim.py   projenin kendi Python'uyla çalışan sözdizimi/içe aktarma denetimi
assets/                duvar kâğıdı ve onu üreten betik
tests/                 Windows tuzaklarını içeren sahte yedek üretici (proje aşamasını denemek için)
```

Proje aşamasını kendi verine dokunmadan denemek için:

```bash
python3 tests/sahte_yedek_olustur.py /tmp/deneme.zip
PROJELER=/tmp/DenemeProjeler bash 40-projeler.sh /tmp/deneme.zip
```
