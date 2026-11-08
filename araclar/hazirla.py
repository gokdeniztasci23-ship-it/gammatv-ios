# GammaTV.py icindeki arayuzu ve kutuphaneleri iPhone uygulamasinin web/ klasorune donusturur.
# Kullanim: python3 araclar/hazirla.py ../GammaTV.py web
import importlib.util, os, sys
kaynak, hedef = sys.argv[1], sys.argv[2]
s = importlib.util.spec_from_file_location("gammatv", kaynak); m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
sayfa = m.SAYFA
def d(e, y):
    global sayfa
    assert sayfa.count(e) == 1, e
    sayfa = sayfa.replace(e, y)
d('url:location.origin+u}', 'url:new URL(u,location.href).href}')          # ozel adres semasinda tam adres
d('{enableWorker:true,enableStashBuffer:false', '{enableWorker:false,enableStashBuffer:false')   # iPhone: MPEG-TS ana is parcaciginda
d('if(!window.Hls||!Hls.isSupported())return basarisiz(o,"HLS oynatıcı yüklenemedi.",false);',
  'if(!window.Hls||!Hls.isSupported()){video.src=o.k.url;tamponla(o,Math.min(tamponHedef,3));return}')   # iOS 17.1 oncesi: yerlesik HLS
d('else video.src=u;', 'else video.src=o.k.url;')                         # dosya/radyo: iPhone oynaticisi dogrudan acar
d("'<i class=\"nokta\"></i>Bu bilgisayarda kapalı. Microsoft Store\\'dan ücretsiz “HEVC Video Extensions from Device Manufacturer” uzantısını kurup uygulamayı yeniden başlat.'",
  "'<i class=\"nokta\"></i>Bu cihaz H.265 yayınları donanımla çözemiyor.'")
kopru = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "kopru_ios.js"), encoding="utf-8").read()
i = sayfa.index("<head>") + len("<head>")
sayfa = sayfa[:i] + "\n<script>" + kopru + "</script>" + sayfa[i:]
os.makedirs(os.path.join(hedef, "lib"), exist_ok=True)
open(os.path.join(hedef, "index.html"), "w", encoding="utf-8").write(sayfa)
for ad in m._KUTUPHANE:
    open(os.path.join(hedef, "lib", ad), "wb").write(m._kutuphane(ad))
print("web:", sorted(os.listdir(hedef)), sorted(os.listdir(os.path.join(hedef, "lib"))))
