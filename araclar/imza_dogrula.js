// GİB jar imza doğrulaması (jjs, Java 8). Kullanım:
//   jjs imza_dogrula.js -- <kokler.txt> <jar>...
// Her jar için tek satır:  OK <jar>  |  HATA <jar> <KOD> <ayrıntı>
// Denetlenenler:
//  - Her girdi (imza dosyaları dışındaki META-INF girdileri dahil) imzalı ve içeriği imzayla uyuşuyor.
//  - İmzalayan sertifikanın tek "O" alanı birebir "Gelir İdaresi Başkanlığı"; EKU'da kod imzalama amacı ZORUNLU.
//  - Sertifika zinciri Java PKIX ile doğrulanır: ara sertifikalar CA mı, yetki/uzunluk kısıtları, imza anında
//    geçerlilik (zaman damgası tarihi; damga yoksa bugün). Kök, zincirin son sertifikasıdır.
//  - Kök, güvenilen kök listesinde mi (SHA-256 parmak izi).
// KOD: DEGISMIS · IMZASIZ · KURUM_DEGIL · AMAC_DEGIL · ZINCIR_GECERSIZ · ACILAMADI
//      KOK_BILINMIYOR <parmak_izi> <kök adı> zincir=N damga=evet|hayir
//      (zincir PKIX'e göre geçerli, imzalayan GİB, yalnız kök listede yok → "gibimza kok-kabul" inceleyebilir)
// Çıkış: 0 = hepsi OK, 1 = en az bir HATA.
var JarFile=Java.type('java.util.jar.JarFile'), MD=Java.type('java.security.MessageDigest'), Byte=Java.type('byte[]');
var Files=Java.type('java.nio.file.Files'), Paths=Java.type('java.nio.file.Paths'), UTF8=Java.type('java.nio.charset.StandardCharsets').UTF_8;
var CF=Java.type('java.security.cert.CertificateFactory'), CPV=Java.type('java.security.cert.CertPathValidator');
var PKIXP=Java.type('java.security.cert.PKIXParameters'), TA=Java.type('java.security.cert.TrustAnchor');
var HashSet=Java.type('java.util.HashSet'), ArrayList=Java.type('java.util.ArrayList'), JDate=Java.type('java.util.Date');
var LdapName=Java.type('javax.naming.ldap.LdapName'), X500P=Java.type('javax.security.auth.x500.X500Principal');
var KURUM='Gelir \u0130daresi Ba\u015fkanl\u0131\u011f\u0131', KOD_IMZA='1.3.6.1.5.5.7.3.3';
// Konu adında tek bir "O" (organizationName) alanı olmalı ve DEĞERİ birebir KURUM olmalı (alt dizgi değil).
function kurum_mu(c){ var ln=new LdapName(c.getSubjectX500Principal().getName(X500P.RFC2253)), o=[];
  for(var i=0;i<ln.size();i++){ var r=ln.getRdn(i); if(String(r.getType()).toUpperCase()=='O') o.push(String(r.getValue())); }
  return o.length==1 && o[0]==KURUM; }
var KOKLER=[];
try{ var sat=Files.readAllLines(Paths.get(arguments[0]),UTF8);
  for(var i=0;i<sat.size();i++){var s=String(sat.get(i)).replace(/#.*/,'').replace(/[^0-9A-Fa-f]/g,'').toUpperCase(); if(s.length==64)KOKLER.push(s);} }
catch(x){ print('HATA - KOK_LISTESI_YOK '+arguments[0]); exit(1); }
function parmak(c){var d=MD.getInstance('SHA-256').digest(c.getEncoded()),s='';for(var i=0;i<d.length;i++){s+=('0'+(d[i]&255).toString(16)).slice(-2)}return s.toUpperCase();}
function ad(c){var n=String(c.getSubjectX500Principal().toString()),m=n.match(/CN=([^,]+)/);return (m?m[1]:n).replace(/\s+/g,'_');}
function imza_dosyasi(n){ return /^META-INF\/(MANIFEST\.MF|[^\/]+\.(SF|RSA|DSA|EC)|SIG-[^\/]+)$/i.test(n); }
// Bir imzacının değerlendirmesi: 'OK' ya da 'KOD ayrıntı'
function degerlendir(cs){
  var cl=cs.getSignerCertPath().getCertificates(), n=cl.size(), yaprak=cl.get(0);
  if(!kurum_mu(yaprak)) return 'KURUM_DEGIL '+ad(yaprak);
  var eku=null; try{eku=yaprak.getExtendedKeyUsage()}catch(x){}
  if(eku==null || !eku.contains(KOD_IMZA)) return 'AMAC_DEGIL '+ad(yaprak);
  if(n<2) return 'ZINCIR_GECERSIZ tek_halkali_oz_imzali';
  var kok=cl.get(n-1), yol=new ArrayList(); for(var i=0;i<n-1;i++) yol.add(cl.get(i));
  var p=new PKIXP(new HashSet(java.util.Collections.singleton(new TA(kok,null))));
  p.setRevocationEnabled(false);
  var ts=cs.getTimestamp(); p.setDate(ts?ts.getTimestamp():new JDate());
  try{ CPV.getInstance('PKIX').validate(CF.getInstance('X.509').generateCertPath(yol),p); }
  catch(x){ return 'ZINCIR_GECERSIZ '+String(x.getMessage()).replace(/\s+/g,'_').substring(0,100); }
  var fp=parmak(kok);
  if(KOKLER.indexOf(fp)<0) return 'KOK_BILINMIYOR '+fp+' '+ad(kok)+' zincir='+n+' damga='+(ts?'evet':'hayir');
  return 'OK';
}
var hata=0, buf=new Byte(65536);
for(var a=1;a<arguments.length;a++){var p=arguments[a], kisa=p.replace(/.*\//,''), sonuc='OK', jf=null, onbellek={};
 try{ jf=new JarFile(p,true); var en=jf.entries(), say=0;
  dongu: while(en.hasMoreElements()){var e=en.nextElement(); if(e.isDirectory())continue;
   var is=jf.getInputStream(e);
   try{ while(is.read(buf)!=-1){} }catch(x){ sonuc='DEGISMIS '+e.getName(); is.close(); break dongu; }
   is.close();
   var n=e.getName(); if(imza_dosyasi(n))continue; say++;
   var cs=e.getCodeSigners(); if(cs==null){sonuc='IMZASIZ '+n;break;}
   var en_iyi=null;
   for(var k=0;k<cs.length;k++){
     var anahtar=String(cs[k].hashCode()); var d=onbellek[anahtar]; if(d===undefined){d=degerlendir(cs[k]);onbellek[anahtar]=d;}
     if(d=='OK'){en_iyi='OK';break;} if(en_iyi==null||en_iyi.indexOf('KOK_BILINMIYOR')!=0)en_iyi=d; }
   if(en_iyi!='OK'){sonuc=en_iyi;break;}}
  if(sonuc=='OK'&&say==0)sonuc='IMZASIZ (bos)';
 }catch(x){ sonuc=(String(x).indexOf('SecurityException')>=0?'DEGISMIS ':'ACILAMADI ')+String(x).replace(/\s+/g,'_').substring(0,120); }
 try{ if(jf)jf.close(); }catch(x){}
 if(sonuc!='OK')hata++;
 print((sonuc=='OK'?'OK ':'HATA ')+kisa+(sonuc=='OK'?'':' '+sonuc));
}
exit(hata?1:0);
