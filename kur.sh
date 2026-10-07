#!/bin/sh
# GİB e-Arşiv imzalama aracı (EFaturaWebSocket) — macOS tek komut kurulum
#   curl -fsSL https://raw.githubusercontent.com/cemsinanoglu-stack/earsiv-eimza-mac/main/kur.sh | sh
# Betik sudo istemez. Yalnız AKİS/e-Token sürücüsü kurulurken macOS kendi penceresinde Mac şifrenizi sorar.
# Kurulan yerler:
#   ~/Library/GIBImza                               Java, GİB aracı, sürücü kopyası (SafeSign), gibimza komutu
#   ~/Library/LaunchAgents/tr.gibimza.araci.plist   aracı arka planda açık tutar
#   ~/Applications/GIB e-Arsiv.app + Masaüstü        "GİB e-Arşiv" simgesi
#   /usr/local/lib/…                                yalnız AKİS/e-Token: üreticinin kendi kurulum paketi
# Doğrulama:
#   Java → Azul API (SHA-256) · GİB aracı → ebelge.gib.gov.tr (her jar: GİB imzası + güvenilen kök listesi)
#   AKİS → TÜBİTAK (Gatekeeper: Apple onaylı, 7ZWFF63P66) · SafeSign → E-Tuğra (Gatekeeper, 9UT52UVZVY)
#   e-Token → E-Güven (Gatekeeper, Gemalto TR37863VGD)
# Seçenekler (ortam değişkeni, ör. "| GIBIMZA_KART=akis sh"):
#   GIBIMZA_KART=akis|safesign|etoken   GIBIMZA_SURUCU_PAKET=<üreticinin paketinin yolu ya da adresi>
#   GIBIMZA_ARKAPLAN=0   GIBIMZA_UYGULAMA=0   GIBIMZA_MASAUSTU=0   GIBIMZA_CLAUDE=0   GIBIMZA_TARAYICI=0
#   GIBIMZA_SURUCU_KUR=0 (sürücüyü indir+doğrula, kurma)
# Sonra: ~/Library/GIBImza/gibimza teshis   ·   Kaldırma: sh ~/Library/GIBImza/kaldir.sh
#
# Tüm gövde ana() içindedir: bağlantı yarıda koparsa yarım betik çalışmaz.

ana(){
set -e
SURUM="1.0.0"
P="${GIBIMZA_DIZIN:-$HOME/Library/GIBImza}"
ETIKET="${GIBIMZA_ETIKET:-tr.gibimza.araci}"
PLIST="$HOME/Library/LaunchAgents/$ETIKET.plist"
KAYNAK="${GIBIMZA_KAYNAK:-https://raw.githubusercontent.com/cemsinanoglu-stack/earsiv-eimza-mac/main}"
JNLP_URL="https://ebelge.gib.gov.tr/EFaturaWebSocket/EFaturaWebSocket.jnlp"
say(){ printf '%s\n' "$*"; }
olmez(){ say "❌ $*"; say "   Yardım: ~/Library/GIBImza/gibimza teshis (kuruluysa) · README › Sorun giderme"; exit 1; }
GECICI=$(mktemp -d "${TMPDIR:-/tmp}/gibimza.XXXXXX")   # tüm geçici dosyalar burada; çıkışta silinir
gecici(){ mktemp -d "$GECICI/is.XXXXXX"; }
temizle(){ set +e; for m in "$GECICI"/is.*/mnt; do if [ -d "$m" ]; then hdiutil detach "$m" -quiet >/dev/null 2>&1; fi; done; case "$GECICI" in */gibimza.*) rm -rf "$GECICI";; esac; return 0; }
trap temizle EXIT INT TERM

say "== GİB e-Arşiv imzalama aracı · macOS kurulumu (sürüm $SURUM) =="
[ "$(uname -s)" = "Darwin" ] || olmez "Bu betik yalnız macOS içindir."
[ "$(id -u)" != "0" ] || olmez "Bu kurulumu 'sudo' ile çalıştırmayın; normal kullanıcı olarak çalıştırın."
case "$P" in *" "*|*'"'*|*"'"*|*'&'*|*'<'*|*'>'*|*'$'*|*'`'*|*'\'*) olmez "Kurulum klasörü boşluk ya da özel karakter içeremez: $P";; esac
P=${P%/}; case "$P" in "$HOME"/*) ;; *) olmez "Kurulum klasörü ev klasörünüzün içinde olmalı: $P";; esac
case "$P" in "$HOME"/Library|"$HOME"/Desktop|"$HOME"/Documents|"$HOME"/Downloads|"$HOME"/Applications) olmez "Bu klasör kurulum için kullanılamaz: $P";; esac
if [ -d "$P" ] && [ ! -f "$P/.gibimza_kurulum" ] && [ -n "$(ls -A "$P" 2>/dev/null)" ]; then olmez "Kurulum klasörü dolu ve bu kuruluma ait değil: $P
   Eski bir kurulumsa kenara alıp yeniden deneyin: mv \"$P\" \"${P}_eski\" (sonra bu komutu yeniden çalıştırın)"; fi
case "$ETIKET" in *[!A-Za-z0-9.-]*) olmez "Geçersiz GIBIMZA_ETIKET: $ETIKET";; esac
# Donanıma bak (Terminal Rosetta modunda açıksa uname x86_64 der ama sürücü arm64 olmalı)
if [ "$(sysctl -n hw.optional.arm64 2>/dev/null)" = "1" ]; then ARCH=aarch64; MIM=arm64
elif [ "$(uname -m)" = "x86_64" ]; then ARCH=x64; MIM=x86_64
else olmez "Desteklenmeyen işlemci: $(uname -m)"; fi
say "✅ İşlemci: $MIM · macOS $(sw_vers -productVersion 2>/dev/null)"
for k in curl tar shasum sed awk file lsof launchctl spctl codesign hdiutil unzip ditto; do command -v $k >/dev/null 2>&1 || olmez "$k bulunamadı"; done
mkdir -p "$P/jars" "$HOME/Library/LaunchAgents" "$HOME/Library/Application Support"
: > "$P/.gibimza_kurulum"

# 1) Yardımcı dosyalar (bu depodan)
indir(){ if curl -fsSL -m 60 -o "$2.yeni" "$KAYNAK/$1" && [ -s "$2.yeni" ]; then mv "$2.yeni" "$2"; else rm -f "$2.yeni"; olmez "İndirilemedi: $KAYNAK/$1"; fi; }
for f in guncelle.sh baslat.sh imza_dogrula.js kart_dogrula.js gibimza AppIcon.icns; do indir "araclar/$f" "$P/$f"; done
indir ai/claude-skill/gib-earsiv/SKILL.md "$P/SKILL.md"
T=$(gecici); indir araclar/guvenilen_kokler.txt "$T/kokler"
if [ -f "$P/guvenilen_kokler.txt" ]; then   # kullanıcının daha önce kabul ettiği kökler korunur
  { cat "$T/kokler"; grep -v -F -x -f "$T/kokler" "$P/guvenilen_kokler.txt" | grep -v '^#' || true; } > "$T/birlesik"; mv "$T/birlesik" "$P/guvenilen_kokler.txt"
else mv "$T/kokler" "$P/guvenilen_kokler.txt"; fi
chmod +x "$P/guncelle.sh" "$P/baslat.sh" "$P/gibimza"
printf '%s\n' "$SURUM" > "$P/surum.txt"; printf '%s\n' "$KAYNAK" > "$P/kaynak.txt"; printf '%s\n' "$ETIKET" > "$P/etiket.txt"
say "✅ Yardımcı dosyalar hazır"

# 2) Java: araçlar için her zaman Java 8 (GİB'in kart kütüphanesi Java 8'e özgü yapıcı kullanıyor);
#    GİB JNLP'si daha yeni bir Java isterse o sürüm de ayrıca kurulur ve araç onunla çalışır.
jalan(){ printf '%s' "$2" | tr ',' '\n' | sed -n "s/.*\"$1\" *: *\"\([^\"]*\)\".*/\1/p" | head -1; }
java_kur(){ # $1 ana sürüm, $2 hedef klasör
  if [ -x "$2/bin/java" ] && "$2/bin/java" -version 2>&1 | grep -q "\"1\.$1\.\|\"$1[.\"]"; then say "✅ Java $1 zaten kurulu"; return 0; fi
  say "… Java $1 ($ARCH) indiriliyor (Azul)"
  BILGI=$(curl -fsSL -m 60 "https://api.azul.com/metadata/v1/zulu/packages/?java_version=$1&os=macos&arch=$ARCH&archive_type=tar.gz&java_package_type=jre&javafx_bundled=false&release_status=ga&availability_types=CA&latest=true&page_size=1") || olmez "Azul'a ulaşılamadı — internet bağlantınızı kontrol edin"
  UUID=$(jalan package_uuid "$BILGI"); [ -n "$UUID" ] || olmez "Azul paket bilgisi alınamadı (Java $1)"
  DETAY=$(curl -fsSL -m 60 "https://api.azul.com/metadata/v1/zulu/packages/$UUID") || olmez "Azul paket ayrıntısı alınamadı"
  URL=$(jalan download_url "$DETAY"); [ -n "$URL" ] || olmez "Azul indirme adresi alınamadı"
  SHA=$(jalan sha256_hash "$DETAY"); [ -n "$SHA" ] || olmez "Azul SHA-256 vermedi — doğrulanamayan Java kurulmaz"
  T=$(gecici)
  curl -fL --progress-bar -o "$T/jre.tar.gz" "$URL" || olmez "Java indirilemedi"
  [ "$(shasum -a 256 "$T/jre.tar.gz" | cut -d' ' -f1)" = "$SHA" ] || olmez "Java SHA-256 tutmadı — kurulum durduruldu"
  mkdir -p "$T/x" && tar -xzf "$T/jre.tar.gz" -C "$T/x"
  H=$(dirname "$(dirname "$(find "$T/x" -path '*/bin/java' -type f | head -1)")")
  [ -x "$H/bin/java" ] || olmez "Java arşivi beklenmedik yapıda"
  [ -d "$2" ] && mv "$2" "$T/eski"
  mv "$H" "$2"
  "$2/bin/java" -version >/dev/null 2>&1 || olmez "Java $1 çalışmadı"
  say "✅ Java $1 kuruldu (SHA-256 doğrulandı)"
}
java_kur 8 "$P/jre"
[ -x "$P/jre/bin/jjs" ] || olmez "Java 8 araçları eksik (jjs)"
GEREK=8
if JN=$(curl -fsSL -m 20 "$JNLP_URL" 2>/dev/null); then
  v=$(printf '%s' "$JN" | tr '\n\r\t' '   ' | sed -n -E 's/.*<(j2se|java)[^>]*version="([^"]*)".*/\2/p' | head -1); v=${v%%+*}; v=${v%%\**}; v=${v#1.}; v=${v%%.*}
  case "$v" in ''|*[!0-9]*) ;; *) [ "$v" -gt 8 ] && GEREK=$v;; esac
fi
if [ "$GEREK" -gt 8 ]; then say "ℹ️  GİB Java $GEREK istiyor"; java_kur "$GEREK" "$P/jre_arac"; else rm -rf "$P/jre_arac"; fi

# 3) Kaldırıcı (yalnız kurulum işaretini taşıyan klasörü siler)
cat > "$P/kaldir.sh" <<EOS
#!/bin/sh
P="$P"
[ -f "\$P/.gibimza_kurulum" ] || { echo "Kurulum klasörü doğrulanamadı (\$P); hiçbir şey silinmedi."; exit 1; }
launchctl bootout "gui/\$(id -u)/$ETIKET" 2>/dev/null
rm -f "$PLIST"
[ -L "\$HOME/Desktop/GİB e-Arşiv" ] && rm -f "\$HOME/Desktop/GİB e-Arşiv"
[ -f "\$HOME/Applications/GIB e-Arsiv.app/Contents/MacOS/gibimza-ac" ] && rm -rf "\$HOME/Applications/GIB e-Arsiv.app"
[ -f "\$HOME/.claude/skills/gib-earsiv/SKILL.md" ] && rm -rf "\$HOME/.claude/skills/gib-earsiv"
rm -rf "\$P"
echo "GİB e-Arşiv imzalama aracı kaldırıldı. (AKİS/e-Token sürücüleri sistemde kalır; başka e-imza işleriniz onları kullanabilir.)"
EOS
chmod +x "$P/kaldir.sh"

# 4) GİB aracı: ilk indirme + imza doğrulaması
say "… GİB imzalama aracı indiriliyor (ebelge.gib.gov.tr) ve imzası doğrulanıyor"
if ! sh "$P/guncelle.sh" >/dev/null 2>&1; then
  say "$(cat "$P/uyari.txt" 2>/dev/null | head -3)"
  olmez "GİB aracı indirilemedi ya da GİB imzası doğrulanamadı"
fi
N=$(ls "$P/jars"/*.jar 2>/dev/null | wc -l | tr -d ' ')
say "✅ GİB aracı hazır: $N dosya, hepsi Gelir İdaresi Başkanlığı imzalı"

# 5) Arka plan ajanı (varsayılan açık)
if [ "${GIBIMZA_ARKAPLAN:-1}" = "1" ]; then
  launchctl bootout "gui/$(id -u)/$ETIKET" 2>/dev/null || true
  sleep 1
  cat > "$PLIST" <<EOS
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$ETIKET</string>
  <key>ProgramArguments</key><array><string>/bin/sh</string><string>$P/baslat.sh</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
  <key>ThrottleInterval</key><integer>30</integer>
  <key>ProcessType</key><string>Interactive</string>
  <key>StandardOutPath</key><string>/dev/null</string>
  <key>StandardErrorPath</key><string>/dev/null</string>
</dict></plist>
EOS
  if lsof -nP -iTCP:8543 -sTCP:LISTEN >/dev/null 2>&1; then
    say "⚠️  8543 portu dolu: başka bir imzalama aracı açık (ör. OpenWebStart ile açılmış eski kopya)."
    say "   Onu kapatın, sonra simgeye çift tıklayın ya da: ~/Library/GIBImza/gibimza baslat"
  fi
  i=0; until launchctl bootstrap "gui/$(id -u)" "$PLIST" 2>/dev/null || [ $i -ge 3 ]; do sleep 2; i=$((i+1)); done
  i=0; until lsof -nP -iTCP:8543 -sTCP:LISTEN >/dev/null 2>&1 || [ $i -ge 40 ]; do sleep 1; i=$((i+1)); done
  KIM=$(lsof -t -iTCP:8543 -sTCP:LISTEN 2>/dev/null | head -1)
  if [ -n "$KIM" ] && ps -o command= -p "$KIM" | grep -q "^$P/"; then say "✅ Araç arka planda çalışıyor (127.0.0.1:8543). macOS 'arka plan öğesi eklendi' bildirimi gösterebilir; bu odur."
  elif [ -n "$KIM" ]; then say "⚠️  8543'ü başka bir araç tutuyor. Onu kapatın, sonra simgeye çift tıklayın."
  else say "⚠️  Araç henüz dinlemiyor; birazdan simgeye çift tıklayın."; fi
else
  rm -f "$PLIST"
  say "ℹ️  Arka plan ajanı kurulmadı. Aracı simge ya da 'gibimza baslat' açar."
fi

# 6) Kart sürücüsü — sağlayıcınıza göre, RESMÎ kaynaktan, macOS Gatekeeper ile doğrulanarak
say ""
say "== Kart sürücüsü =="
SUR="$P/surucu"; mkdir -p "$SUR"
uygun(){ [ -f "$1" ] && file -L "$1" 2>/dev/null | grep -q "$MIM"; }
kart_yokla(){ perl -e 'alarm 40; exec @ARGV' "$P/jre/bin/jjs" -J-XX:ErrorFile=${TMPDIR:-/tmp}/gibimza_hs_err_%p.log "$P/kart_dogrula.js" -- "$1" 2>/dev/null | head -1; }
kart_goruyor(){ uygun "$1" || return 0; S=$(kart_yokla "$1"); case "$S" in KART_VAR|KART_YOK) ;; *) sleep 1; S=$(kart_yokla "$1");; esac; printf '%s\n' "$S"; }   # sürücü ara sıra çöker: bir kez yeniden dener
adaylar(){ # $1 = kart türü (boşsa hepsi); satır satır yol
  if [ -n "${GIBIMZA_SURUCU_ADAYLARI+x}" ]; then printf '%s\n' "$GIBIMZA_SURUCU_ADAYLARI" | tr ':' '\n'; return; fi
  case "${1:-hepsi}" in akis|hepsi) printf '%s\n' /usr/local/lib/libakisp11.dylib;; esac
  case "${1:-hepsi}" in safesign|hepsi) printf '%s\n' "$SUR/tokenadmin.app/Contents/Frameworks/libaetpkss.dylib" /Applications/tokenadmin.app/Contents/Frameworks/libaetpkss.dylib /usr/local/lib/libaetpkss1.dylib;; esac
  case "${1:-hepsi}" in etoken|hepsi) printf '%s\n' /usr/local/lib/libeTPkcs11.dylib /usr/local/lib/pkcs11/libIDPrimePKCS11.dylib;; esac
}
ilk_uygun(){ adaylar "$1" | while IFS= read -r d; do if [ -n "$d" ] && uygun "$d"; then printf '%s\n' "$d"; break; fi; done; return 0; }
tty_var(){ [ -r /dev/tty ] && ( : </dev/tty ) 2>/dev/null; }
# Gatekeeper: Apple onaylı (notarized) + imzalayan Team ID. Dosya adı denetime girmez (sabit adlı kopya).
gk_onayli(){ # $1 yol, $2 tür (install|execute), $3 Team ID
  C=$(spctl -a -vv -t "$2" "$1" 2>&1) || return 1
  printf '%s\n' "$C" | grep -q '^source=Notarized Developer ID$' || return 1
  printf '%s\n' "$C" | grep -q "^origin=Developer ID [A-Za-z]*: .* ($3)\$" || return 1
}
bekle_surucu(){ # $1 yol — kullanıcı macOS kurulum penceresini bitirene kadar (en çok 15 dk)
  say "   macOS kurulum penceresi açıldı: 'Devam' › 'Yükle' deyin; macOS Mac şifrenizi sorar (bu sizin onayınızdır)."
  say "   Pencereyi kapatırsanız kurulum yarıda kalır; bu komutu yeniden çalıştırmanız yeterli."
  i=0; until uygun "$1" || [ $i -ge 180 ]; do
    sleep 5; i=$((i+1))
    [ $i -gt 6 ] && ! pgrep -x Installer >/dev/null 2>&1 && ! uygun "$1" && olmez "Kurulum penceresi kapandı, sürücü kurulmadı. Komutu yeniden çalıştırın."
  done
  uygun "$1" || olmez "Sürücü kurulumu tamamlanmadı ($1). Kurulumu bitirip bu komutu yeniden çalıştırın."
}
# Paket getir: GIBIMZA_SURUCU_PAKET verilmişse onu (yerel yol ya da adres), yoksa varsayılan adres
paket_getir(){ # $1 varsayılan adres, $2 hedef dosya, $3 üretici sayfası
  K="${GIBIMZA_SURUCU_PAKET:-$1}"
  case "$K" in
    /*|~/*) cp "$K" "$2" 2>/dev/null || olmez "Paket okunamadı: $K";;
    *) curl -fL --progress-bar -o "$2" "$K" || olmez "İndirilemedi: $K
   Üretici adresi değişmiş olabilir. Paketi üreticinin sayfasından ($3) indirip şöyle verin:
   curl -fsSL $KAYNAK/kur.sh | GIBIMZA_KART=$KART GIBIMZA_SURUCU_PAKET=~/Downloads/<paket> sh";;
  esac
}
# Arşivi aç: zip/rar/dmg/pkg — içinden ilk .pkg'yi ya da tokenadmin.app'i bulup sabit ada kopyalar
paket_ac(){ # $1 dosya, $2 çalışma klasörü; çıktı: $2/paket.pkg ya da $2/tokenadmin.app
  mkdir -p "$2/x" "$2/mnt"
  case "$(file -b "$1")" in
    Zip*) ( cd "$2/x" && unzip -q "$1" ) || olmez "Arşiv açılamadı";;
    RAR*) tar -xf "$1" -C "$2/x" || olmez "Arşiv açılamadı";;
    xar*) cp "$1" "$2/x/paket.pkg";;
    *) cp "$1" "$2/x/paket.dmg";;
  esac
  DMG=$(find "$2/x" -name '*.dmg' -not -path '*/__MACOSX/*' | head -1)
  if [ -n "$DMG" ]; then
    hdiutil attach -nobrowse -readonly -noverify -mountpoint "$2/mnt" "$DMG" >/dev/null 2>&1 || olmez "Disk kalıbı açılamadı"
    if [ -d "$2/mnt/tokenadmin.app" ]; then ditto "$2/mnt/tokenadmin.app" "$2/tokenadmin.app"
    else PKG=$(find "$2/mnt" -maxdepth 2 -name '*.pkg' | head -1); [ -n "$PKG" ] && cp "$PKG" "$2/paket.pkg"; fi
    hdiutil detach "$2/mnt" -quiet 2>/dev/null || true
  else
    PKG=$(find "$2/x" -name '*.pkg' -not -path '*/__MACOSX/*' | head -1); [ -n "$PKG" ] && cp "$PKG" "$2/paket.pkg"
  fi
  [ -f "$2/paket.pkg" ] || [ -d "$2/tokenadmin.app" ] || olmez "Paketin içinde kurulum dosyası bulunamadı"
}

kur_akis(){
  [ "$MIM" = arm64 ] && K=arm || K=intel
  U=$(curl -fsSL -m 30 https://akiskart.bilgem.tubitak.gov.tr/tr/destek/ 2>/dev/null | grep -o "https://akiskart\.bilgem\.tubitak\.gov\.tr/wp-content/uploads/[^\"' ]*Akia_macos_${K}_[^\"' ]*\.pkg_\.zip" | sort -u | tail -1)
  [ -n "$U" ] || U="https://akiskart.bilgem.tubitak.gov.tr/wp-content/uploads/sites/33/2026/06/Akia_macos_${K}_6.8.10.pkg_.zip"
  say "… AKİS sürücüsü (TÜBİTAK Akia, $K): ${GIBIMZA_SURUCU_PAKET:-$U}"
  T=$(gecici); paket_getir "$U" "$T/indirilen" "https://akiskart.bilgem.tubitak.gov.tr/tr/destek/"; paket_ac "$T/indirilen" "$T"
  [ -f "$T/paket.pkg" ] || olmez "AKİS paketi değil"
  gk_onayli "$T/paket.pkg" install 7ZWFF63P66 || olmez "AKİS paketi TÜBİTAK imzalı ve Apple onaylı değil — kurulmadı"
  say "✅ Doğrulandı: TÜBİTAK imzalı (7ZWFF63P66), Apple onaylı"
  [ "${GIBIMZA_SURUCU_KUR:-1}" = "1" ] || { say "ℹ️  Prova: kurulmadı"; return 0; }
  cp "$T/paket.pkg" "$SUR/akis.pkg"; open "$SUR/akis.pkg"; bekle_surucu /usr/local/lib/libakisp11.dylib; rm -f "$SUR/akis.pkg"
  BUL=/usr/local/lib/libakisp11.dylib
}
kur_safesign(){
  U=https://e-tugra.com.tr/portals/6/downloads/MacOS-Safesign.rar
  say "… E-Tuğra SafeSign: ${GIBIMZA_SURUCU_PAKET:-$U}"
  T=$(gecici); paket_getir "$U" "$T/indirilen" "https://helpdesk.e-tugra.com.tr"
  [ "$(shasum -a 256 "$T/indirilen" | cut -d' ' -f1)" = e09a6fdf4d734840acb4a4e97315d03af214367da18b8d36cd83aa24b54229a8 ] \
    && say "✅ Paket bilinen sürümle aynı (SHA-256)" || say "ℹ️  Paket bilinen sürümden farklı; uygulama imzası ve Apple onayıyla doğrulanacak"
  paket_ac "$T/indirilen" "$T"
  [ -d "$T/tokenadmin.app" ] || olmez "SafeSign paketi değil (tokenadmin.app yok)"
  codesign --verify --deep --strict "$T/tokenadmin.app" 2>/dev/null && gk_onayli "$T/tokenadmin.app" execute 9UT52UVZVY \
    || olmez "SafeSign uygulaması A.E.T. Europe imzalı ve Apple onaylı değil — kullanılmadı"
  say "✅ Doğrulandı: A.E.T. Europe imzalı (9UT52UVZVY), Apple onaylı"
  uygun "$T/tokenadmin.app/Contents/Frameworks/libaetpkss.dylib" || olmez "SafeSign kütüphanesi bu işlemciyi ($MIM) desteklemiyor"
  rm -rf "$SUR/tokenadmin.app"; mv "$T/tokenadmin.app" "$SUR/tokenadmin.app"
  say "ℹ️  SafeSign'ı kullanmanız üreticinin lisansına tabidir: $SUR/tokenadmin.app/Contents/Resources/Safesign License Agreement.rtf"
  BUL="$SUR/tokenadmin.app/Contents/Frameworks/libaetpkss.dylib"
}
kur_etoken(){
  U=https://www.e-guven.com/Images/Software/safenetauthenticationclient108290-39047.zip
  say "… E-Güven e-Token (SafeNet): ${GIBIMZA_SURUCU_PAKET:-$U}"
  T=$(gecici); paket_getir "$U" "$T/indirilen" "https://www.e-guven.com/yazilim/etoken"; paket_ac "$T/indirilen" "$T"
  [ -f "$T/paket.pkg" ] || olmez "e-Token paketi değil"
  gk_onayli "$T/paket.pkg" install TR37863VGD || olmez "e-Token paketi Gemalto imzalı ve Apple onaylı değil — kurulmadı"
  say "✅ Doğrulandı: Gemalto imzalı (TR37863VGD), Apple onaylı"
  [ "${GIBIMZA_SURUCU_KUR:-1}" = "1" ] || { say "ℹ️  Prova: kurulmadı"; return 0; }
  cp "$T/paket.pkg" "$SUR/etoken.pkg"; open "$SUR/etoken.pkg"; bekle_surucu /usr/local/lib/libeTPkcs11.dylib; rm -f "$SUR/etoken.pkg"
  BUL=/usr/local/lib/libeTPkcs11.dylib
}

# Okuyucu ve kart (yalnız ATR okunur; sertifika ve kimlik bilgisi ekrana yazılmaz)
SC_BILGI=$(system_profiler SPSmartCardsDataType 2>/dev/null || true)
[ "${GIBIMZA_TEST_KARTSIZ:-0}" = "1" ] && SC_BILGI=""   # yalnız sınama içindir
if printf '%s' "$SC_BILGI" | grep -A2 'Readers:' | grep -q '#01'; then say "✅ Kart okuyucu görünüyor"
else say "⚠️  Kart okuyucu görünmüyor — takılı mı? (Okuyucunuz tanınmıyorsa üreticinin macOS sürücüsü gerekebilir.)"; fi
ATR=$(printf '%s' "$SC_BILGI" | sed -n 's/.*ATR:{length = [0-9]*, bytes = 0x\([0-9a-fA-F]*\)}.*/\1/p' | head -1)
KART="${GIBIMZA_KART:-}"
case "$KART" in ''|akis|safesign|etoken) ;; *) olmez "Bilinmeyen GIBIMZA_KART: $KART (akis | safesign | etoken)";; esac
TAHMIN=""
case "$ATR" in *4a434f50*|*4A434F50*) TAHMIN=safesign;; *414b4953*|*414B4953*|*55454b4145*|*55454B4145*) TAHMIN=akis;; esac
if [ -z "$KART" ] && [ -n "$TAHMIN" ]; then
  [ "$TAHMIN" = safesign ] && AD="JCOP kart → E-Tuğra SafeSign" || AD="AKİS kart"
  if tty_var; then
    printf 'Kartınız %s görünüyor. Doğru mu? [E/h]: ' "$AD"; read -r C </dev/tty || C=e
    case "$C" in h|H|hayir|hayır) TAHMIN="";; esac
  fi
  [ -n "$TAHMIN" ] && { KART=$TAHMIN; say "✅ Kart: $AD"; }
fi
if [ -z "$KART" ] && tty_var; then
  say "Hangi e-imzayı kullanıyorsunuz?"
  say "  1) AKİS kart  — Kamu SM, e-imzaTR, TÜRKTRUST; E-Güven/E-Tuğra'nın AKİS kartları (kartın üstünde 'AKİS' yazar)"
  say "  2) E-Tuğra    — SafeSign (JCOP) kart"
  say "  3) E-Güven    — USB e-Token (SafeNet)"
  say "  4) Bilmiyorum / kurulu sürücüyü kullan"
  printf 'Seçiminiz [1-4]: '; read -r C </dev/tty || C=4
  case "$C" in 1) KART=akis;; 2) KART=safesign;; 3) KART=etoken;; esac
fi
BUL=""
ESKI_YOL=$(cat "$P/surucu_yolu.txt" 2>/dev/null || true)
if [ -z "${GIBIMZA_KART:-}" ] && [ -z "${GIBIMZA_SURUCU_ADAYLARI+x}" ] && [ -n "$ESKI_YOL" ] && uygun "$ESKI_YOL"; then BUL="$ESKI_YOL"; fi
[ -n "$BUL" ] || BUL=$(ilk_uygun "$KART")
if [ -n "$BUL" ]; then
  say "✅ Sürücü hazır: $BUL"
elif [ -n "$KART" ]; then
  case "$KART" in akis) kur_akis;; safesign) kur_safesign;; etoken) kur_etoken;; esac
  [ -n "$BUL" ] && say "✅ Sürücü hazır: $BUL"
fi
# Sürücü kartı görüyor mu? (PIN sorulmaz) — görmüyorsa kartı gören kurulu bir sürücü aranır
if [ -n "$BUL" ] && [ -n "$ATR" ]; then
  case "$(kart_goruyor "$BUL")" in
    KART_VAR) say "✅ Sürücü kartınızı görüyor (PIN sorulmadan ölçüldü)";;
    KART_YOK)
      say "⚠️  Bu sürücü takılı kartı görmüyor; kurulu diğer sürücüler deneniyor"
      ESKI="$BUL"; BUL=""
      for d in $(adaylar); do uygun "$d" || continue; [ "$(kart_goruyor "$d")" = KART_VAR ] && { BUL="$d"; break; }; done
      if [ -n "$BUL" ]; then say "✅ Kartınızı gören sürücü: $BUL"
      else BUL="$ESKI"; say "⚠️  Kartınızı gören sürücü bulunamadı. Kart türünüz farklı olabilir: komutu GIBIMZA_KART=akis|safesign|etoken ile yeniden çalıştırın"; fi;;
  esac
fi
[ -n "$BUL" ] && printf '%s' "$BUL" | pbcopy 2>/dev/null && say "📋 Sürücü yolu panoya kopyalandı (portalda yapıştırın)."
[ "$KART" = safesign ] && say "ℹ️  E-Tuğra: kartın ilk aktivasyonu/PIN belirleme yalnız Windows'ta yapılabiliyor (E-Tuğra kılavuzu)."

# 7) Başlatıcılar: "GİB e-Arşiv" simgesi + yapay zekâ talimatı + ayarlar
say ""
say "== Başlatıcılar =="
sed '1,/^---$/{/^---$/!d;};1,/^---$/d' "$P/SKILL.md" > "$P/YAPAY_ZEKA_TALIMATI.md"
[ -n "$BUL" ] && printf '%s\n' "$BUL" > "$P/surucu_yolu.txt"   # sürücü bulunamazsa önceki kayıt korunur
bayrak(){ case "$1" in 0) echo 0;; *) echo 1;; esac; }   # ayarlar yalnız 0/1 ve bilinen kart türü olarak yazılır
{ echo "GIBIMZA_KART=${KART}"; echo "GIBIMZA_ARKAPLAN=$(bayrak "${GIBIMZA_ARKAPLAN:-1}")"; echo "GIBIMZA_UYGULAMA=$(bayrak "${GIBIMZA_UYGULAMA:-1}")";
  echo "GIBIMZA_MASAUSTU=$(bayrak "${GIBIMZA_MASAUSTU:-1}")"; echo "GIBIMZA_CLAUDE=$(bayrak "${GIBIMZA_CLAUDE:-1}")"; } > "$P/ayarlar.env"
say "✅ Komut: ~/Library/GIBImza/gibimza  (yardım: ~/Library/GIBImza/gibimza yardim · muayene: ~/Library/GIBImza/gibimza teshis)"
[ -d "/Applications/Google Chrome.app" ] || [ -d "$HOME/Applications/Google Chrome.app" ] || say "⚠️  Google Chrome bulunamadı. Portal Chrome'da sınandı: https://www.google.com/chrome/"

if [ "${GIBIMZA_UYGULAMA:-1}" = "1" ]; then
  UYG="$HOME/Applications/GIB e-Arsiv.app"
  mkdir -p "$UYG/Contents/MacOS" "$UYG/Contents/Resources"
  cat > "$UYG/Contents/MacOS/gibimza-ac" <<EOS
#!/bin/sh
exec "$P/gibimza" ac
EOS
  chmod +x "$UYG/Contents/MacOS/gibimza-ac"
  cat > "$UYG/Contents/Info.plist" <<EOS
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>gibimza-ac</string>
  <key>CFBundleIdentifier</key><string>tr.gibimza.baslatici</string>
  <key>CFBundleName</key><string>GİB e-Arşiv</string>
  <key>CFBundleDisplayName</key><string>GİB e-Arşiv</string>
  <key>CFBundleGetInfoString</key><string>Gayriresmî başlatıcı — GİB tarafından geliştirilmemiştir</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$SURUM</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSUIElement</key><true/>
</dict></plist>
EOS
  cp "$P/AppIcon.icns" "$UYG/Contents/Resources/AppIcon.icns"
  touch "$UYG"
  say "✅ Simge: Uygulamalar (~/Applications) ve Spotlight'ta \"GİB e-Arşiv\""
  if [ "${GIBIMZA_MASAUSTU:-1}" = "1" ] && [ -d "$HOME/Desktop" ]; then
    if ln -sfn "$UYG" "$HOME/Desktop/GİB e-Arşiv" 2>/dev/null; then say "✅ Masaüstü simgesi: GİB e-Arşiv"
    else say "ℹ️  Masaüstüne simge konamadı (macOS 'Masaüstü klasörüne erişim' izni verilmedi). Spotlight'tan \"GİB e-Arşiv\" yazarak açabilirsiniz."; fi
  fi
fi

if [ "${GIBIMZA_CLAUDE:-1}" = "1" ] && [ -d "$HOME/.claude" ]; then
  mkdir -p "$HOME/.claude/skills/gib-earsiv" && cp "$P/SKILL.md" "$HOME/.claude/skills/gib-earsiv/SKILL.md" \
    && say "✅ Claude Code bulundu: 'gib-earsiv' becerisi eklendi (~/.claude/skills; istemezseniz GIBIMZA_CLAUDE=0)."
fi
say "ℹ️  Yapay zekâ asistanınız için talimat: ~/Library/GIBImza/YAPAY_ZEKA_TALIMATI.md"

# 8) Son durum
say ""
if [ -z "$BUL" ]; then
  say "== Kurulum TAMAMLANMADI: kart sürücüsü yok =="
  say "Kartınızı takıp komutu yeniden çalıştırın ya da kart türünü belirtin:"
  say "  curl -fsSL $KAYNAK/kur.sh | GIBIMZA_KART=akis sh"
  say "  (akis yerine: safesign = E-Tuğra JCOP kart · etoken = E-Güven USB e-Token)"
  exit 3
fi
say "== Tamam =="
say "Her seferinde: Masaüstündeki \"GİB e-Arşiv\" simgesine çift tıklayın (ya da Spotlight: ⌘+Boşluk → GİB e-Arşiv)."
say "  → araç açılır, sürücü yolu panoya kopyalanır, e-Arşiv Google Chrome'da açılır."
say "  → İlk kez (ve Chrome unuttukça, yaklaşık haftada bir): açılan https://localhost:8543 sayfasında 'Gelişmiş' › 'localhost sitesine ilerle' deyin, sonra pencerede 'Yaptım'a basın."
say "Portalda: 'Akıllı kartınızın işlemcisi' = Gelişmiş (Elle Giriş) → yola ⌘V → PIN → Giriş Yap → sertifika → Giriş"
say "   (StarCOS'u SEÇMEYİN — Mac'te sayfa donar · sayfa 5 dk'dan uzun açık kaldıysa önce yenileyin)"
say "Sorun olursa: ~/Library/GIBImza/gibimza teshis   (yapay zekâ asistanınız için: ~/Library/GIBImza/gibimza teshis --json)"
if [ "${GIBIMZA_TARAYICI:-1}" = "1" ]; then "$P/gibimza" ac >/dev/null 2>&1 || true; fi
}
ana "$@"
