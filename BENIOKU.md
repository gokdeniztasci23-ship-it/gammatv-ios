# GammaTV — iPhone sürümü

Bu klasör GammaTV'nin iPhone uygulamasıdır. GitHub'ın Mac sunucusunda imzasız `GammaTV.ipa` olarak derlenir,
sonra Sideloadly ile **kendi Apple kimliğinle** imzalanıp yalnızca senin iPhone'una kurulur.

## 1. IPA'yı GitHub'da derlet
1. github.com'da oturum aç → sağ üstte **+** → **New repository** → ad: `gammatv-ios` → **Public** → **Create repository**.
2. Açılan sayfada **uploading an existing file** bağlantısına tıkla.
3. Bu klasörün **içindekilerin hepsini** (`.github` klasörü dahil) sayfaya sürükle → **Commit changes**.
4. **Actions** sekmesine geç: "iPhone IPA" işi kendiliğinden başlar (5–10 dk).
5. Yeşil tik çıkınca işe tıkla → sayfanın altındaki **Artifacts** → **GammaTV-ipa** indir → içinden `GammaTV.ipa` çıkar.

> `.github` klasörü yüklenmediyse Actions sekmesi boş kalır. O zaman **Add file → Create new file** ile
> `.github/workflows/ipa.yml` adında dosya açıp bu klasördeki aynı dosyanın içeriğini yapıştır.

## 2. iPhone'a kur (Windows)
1. sideloadly.io'dan **Sideloadly**'yi kur; kurulum sayfasında istenen iTunes / iCloud sürümlerini de kur.
2. iPhone'u kabloyla bağla, telefonda **Bu bilgisayara güven** de.
3. Sideloadly'de `GammaTV.ipa`'yı pencereye sürükle, Apple kimliğini yaz → **Start**.
4. iPhone: **Ayarlar → Gizlilik ve Güvenlik → Geliştirici Modu**'nu aç (telefon yeniden başlar).
5. iPhone: **Ayarlar → Genel → VPN ve Aygıt Yönetimi** → kendi Apple kimliğine **Güven**.

## Bilmen gerekenler
- Ücretsiz Apple kimliğiyle kurulan uygulama **7 günde bir** yenilenmeli. Sideloadly'de otomatik yenilemeyi açarsan
  bilgisayar açıkken ve telefon aynı Wi-Fi'deyken bunu kendisi yapar. Listelerin ve ayarların silinmez.
- `.ts` uzantılı canlı yayınlar için **iOS 17.1 veya üstü** gerekir; HLS (`.m3u8`) her sürümde oynar.
- Arayüzü güncellemek için: `python3 araclar/hazirla.py ../GammaTV.py web` → değişen `web` klasörünü GitHub'a yükle.
