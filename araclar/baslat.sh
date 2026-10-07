#!/bin/sh
# GİB aracını GİB'in istediği Java ile başlatır. 8543 doluysa ya da araç doğrulanamazsa başarıyla çıkar
# (arka plan ajanı boşuna yeniden denemesin); "gibimza baslat" yeniden dener. Sebep son_durum.txt'ye yazılır.
P="$(cd "$(dirname "$0")" && pwd)"; cd "$P" || exit 0
if lsof -nP -iTCP:8543 -sTCP:LISTEN >/dev/null 2>&1; then echo "8543 başka bir araçta" > son_durum.txt; exit 0; fi
if ! sh "$P/guncelle.sh" >/dev/null 2>&1; then echo "GİB aracı doğrulanamadı ya da indirilemedi" > son_durum.txt; exit 0; fi
CP=""; for j in $(sed -n 's/.*<jar href="\([^"]*\)".*/\1/p' EFaturaWebSocket.jnlp); do CP="$CP:jars/$(basename "$j")"; done
MAIN=$(sed -n 's/.*main-class="\([^"]*\)".*/\1/p' EFaturaWebSocket.jnlp | head -1)
case "$MAIN" in ''|-*|*[!A-Za-z0-9_.\$]*) echo "GİB listesindeki ana sınıf adı geçersiz: $MAIN" > son_durum.txt; exit 0;; esac
JAVA="$P/jre/bin/java"; [ -x "$P/jre_arac/bin/java" ] && JAVA="$P/jre_arac/bin/java"   # GİB yeni Java isterse
echo "son başlatma: $(date "+%Y-%m-%d %H:%M") ($JAVA)" > son_durum.txt
exec "$JAVA" -Xms64m -Xmx768m -XX:+UseG1GC -Dfile.encoding=UTF-8 -cp "${CP#:}" "$MAIN"
