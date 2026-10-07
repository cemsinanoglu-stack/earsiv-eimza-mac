// Kart sürücüsü kartı görüyor mu? (jjs, Java 8 — GİB aracının kullandığı SunPKCS11 yoluyla). PIN SORMAZ, GİRİŞ YAPMAZ.
// Kullanım: jjs kart_dogrula.js -- <sürücü.dylib>
// Çıktı tek satır: KART_VAR · KART_YOK · YUKLENEMEDI <ayrıntı>
var BAIS=Java.type('java.io.ByteArrayInputStream'), S=Java.type('java.lang.String');
try{
  var P=Java.type('sun.security.pkcs11.SunPKCS11');
  new P(new BAIS(new S('name=GibimzaKontrol\nlibrary='+arguments[0]+'\n').getBytes('UTF-8')));
  print('KART_VAR');
}catch(e){
  var t=String(e), c=e.getCause?String(e.getCause()):'';
  if((t+c).indexOf('CKR_TOKEN_NOT_PRESENT')>=0||(t+c).indexOf('no token')>=0||(t+c).indexOf('slotListIndex')>=0) print('KART_YOK');
  else print('YUKLENEMEDI '+(c||t).replace(/\s+/g,'_').substring(0,160));
}
