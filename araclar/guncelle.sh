#!/bin/sh
# GİB imzalama aracının dosyalarını GİB'den tazeler (ebelge.gib.gov.tr, HTTPS).
# - Yeni inen her jar imzası doğrulanmadan yerine konmaz (imza_dogrula.js + guvenilen_kokler.txt).
# - Doğrulanmış eski kopya, yenisi doğrulanana kadar silinmez.
# - Yalnız kökü tanınmayan ama GİB imzalı dosyalar jars/aday/ altında saklanır ("gibimza kok-kabul" inceler).
# - GİB'in istediği Java sürümü java_gerek.txt'ye yazılır.
# - Sorunlar uyari.txt'ye yazılır ("gibimza durum/teshis" gösterir). Çıkış 0 = doğrulanmış, eksiksiz yerel kopya var.
P="$(cd "$(dirname "$0")" && pwd)"; J="https://ebelge.gib.gov.tr/EFaturaWebSocket/"
cd "$P" || exit 1; mkdir -p jars; : > uyari.yeni
dogrula(){ "$P/jre/bin/jjs" -J-XX:ErrorFile=${TMPDIR:-/tmp}/gibimza_hs_err_%p.log "$P/imza_dogrula.js" -- "$P/guvenilen_kokler.txt" "$@" 2>/dev/null; }
liste(){ sed -n 's/.*<jar href="\([^"]*\)".*/\1/p' "$1"; }
uyar(){ echo "$*" >> uyari.yeni; echo "UYARI: $*"; }
# JNLP'de <j2se ya da <java etiketi birden çok satıra bölünebilir: önce tek satıra indirilir.
java_gerek(){ v=$(tr '\n\r\t' '   ' < "$1" | sed -n -E 's/.*<(j2se|java)[^>]*version="([^"]*)".*/\2/p' | head -1); v=${v%%+*}; v=${v%%\**}; v=${v#1.}; v=${v%%.*}; case "$v" in ''|*[!0-9]*) v=8;; esac; printf '%s' "$v"; }

if curl -fsSL -m 20 -o jnlp.yeni "${J}EFaturaWebSocket.jnlp" 2>/dev/null && grep -q 'main-class' jnlp.yeni; then
  RED=0
  for j in $(liste jnlp.yeni); do
    case "$j" in /*|*..*|*:*) uyar "GİB listesinde beklenmeyen dosya yolu: $j"; RED=1; continue;; esac
    f="jars/$(basename "$j")"
    if [ -f "$f" ]; then curl -fsSL -m 180 -z "$f" -o "$f.yeni" "$J$j" 2>/dev/null || rm -f "$f.yeni"
    else curl -fsSL -m 180 -o "$f.yeni" "$J$j" 2>/dev/null || rm -f "$f.yeni"; fi
    if [ -s "$f.yeni" ]; then
      S=$(dogrula "$f.yeni")
      if [ $? -eq 0 ]; then mv "$f.yeni" "$f"
      else
        case "$S" in
          *KOK_BILINMIYOR*) mkdir -p jars/aday; mv "$f.yeni" "jars/aday/$(basename "$j")"
            uyar "GİB yeni bir sertifika kuruluşu kullanıyor ($(basename "$j")); doğrulanmış önceki sürüm çalışıyor. İncelemek ve kabul etmek için: ~/Library/GIBImza/gibimza kok-kabul";;
          *) uyar "GİB güncellemesi doğrulanamadı ($(basename "$j"): ${S#HATA }); doğrulanmış önceki sürüm çalışıyor";;
        esac
        RED=1
      fi
    fi
    rm -f "$f.yeni"
    [ -s "$f" ] || RED=1
  done
  # Yeni liste ancak bütün dosyaları doğrulanmış olarak eldeyse benimsenir
  if [ $RED = 0 ]; then mv jnlp.yeni EFaturaWebSocket.jnlp; rm -rf jars/aday; else rm -f jnlp.yeni; fi
else
  rm -f jnlp.yeni
fi
[ -f EFaturaWebSocket.jnlp ] || { uyar "GİB aracı hiç indirilemedi (internet bağlantısı?)"; mv uyari.yeni uyari.txt; exit 1; }
G=$(java_gerek EFaturaWebSocket.jnlp); printf '%s\n' "$G" > java_gerek.txt
JV="$P/jre/bin/java"; [ -x "$P/jre_arac/bin/java" ] && JV="$P/jre_arac/bin/java"   # aracın gerçekten kullandığı Java
SURUM=$("$JV" -version 2>&1 | sed -n 's/.*version "\([^"]*\)".*/\1/p' | head -1); SURUM=${SURUM#1.}; SURUM=${SURUM%%.*}
[ -n "$SURUM" ] && [ "$G" -gt "$SURUM" ] 2>/dev/null && uyar "GİB artık Java $G istiyor (kurulu: Java $SURUM). Çözüm: ~/Library/GIBImza/gibimza onar"

EKSIK=0
for j in $(liste EFaturaWebSocket.jnlp); do
  case "$j" in /*|*..*|*:*) continue;; esac
  f="jars/$(basename "$j")"
  if [ ! -s "$f" ] || ! dogrula "$f" >/dev/null; then
    [ -f "$f" ] && mv "$f" "$f.bozuk"
    curl -fsSL -m 180 -o "$f.yeni" "$J$j" 2>/dev/null && dogrula "$f.yeni" >/dev/null && mv "$f.yeni" "$f"
    rm -f "$f.yeni"
    if [ -s "$f" ]; then rm -f "$f.bozuk"
    else [ -f "$f.bozuk" ] && mv "$f.bozuk" "$f"; uyar "$(basename "$j") doğrulanamadı ya da indirilemedi; araç güvenlik için başlatılmadı. Ayrıntı: ~/Library/GIBImza/gibimza teshis"; EKSIK=1; fi
  fi
done
mv uyari.yeni uyari.txt
[ $EKSIK = 0 ] || exit 1
exit 0
