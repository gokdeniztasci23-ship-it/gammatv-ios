import Foundation
import WebKit

/// Masaustundeki Python aktaricisinin iPhone karsiligi.
/// Sayfa gammatv://app adresinden yuklenir; /bilgi ve /p istekleri telefonun kendi ag katmanindan (URLSession)
/// yapilir, boylece CORS ve http engelleri olmaz, istenen tarayici kimligi ve Referer gonderilir.
final class Aktarici: NSObject, WKURLSchemeHandler, URLSessionDataDelegate {
    static let varsayilanUA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) GammaTV/3.0"
    static let bosluk: Set<UInt8> = [9, 10, 13, 32, 0xEF, 0xBB, 0xBF]

    private final class Kayit {
        let gorev: WKURLSchemeTask
        let bilgi: Bool
        let ua: String
        let ref: String
        let onbellek: String?
        var ag: URLSessionDataTask?
        var yanit: HTTPURLResponse?
        var tampon = Data()
        var asama = 0          // 0: ilk baytlar, 1: m3u okunuyor, 2: HLS listesi toplaniyor, 3: akiyor
        var bitti = false
        var dosya: FileHandle?
        var gecici: URL?
        var zamanlayici: Timer?

        init(gorev: WKURLSchemeTask, bilgi: Bool, ua: String, ref: String, onbellek: String?) {
            self.gorev = gorev
            self.bilgi = bilgi
            self.ua = ua
            self.ref = ref
            self.onbellek = onbellek
        }
    }

    private lazy var oturum: URLSession = {
        let c = URLSessionConfiguration.default
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.urlCache = nil
        c.timeoutIntervalForRequest = 20
        c.timeoutIntervalForResource = 7 * 24 * 3600      // canli yayin saatlerce surebilir
        c.httpMaximumConnectionsPerHost = 8
        return URLSession(configuration: c, delegate: self, delegateQueue: OperationQueue.main)
    }()
    private var agdan: [Int: Kayit] = [:]
    private var gorevden: [ObjectIdentifier: Kayit] = [:]
    private let webKlasoru: URL = Bundle.main.url(forResource: "web", withExtension: nil)
        ?? Bundle.main.bundleURL.appendingPathComponent("web")

    // MARK: WKURLSchemeHandler (ana is parcaciginda cagrilir)

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        let gorev = urlSchemeTask
        guard let url = gorev.request.url else {
            gorev.didFailWithError(URLError(.badURL))
            return
        }
        let yol = url.path
        if yol == "/" || yol == "/index.html" {
            dosyaGonder(gorev, webKlasoru.appendingPathComponent("index.html"), "text/html; charset=utf-8")
            return
        }
        if yol.hasPrefix("/lib/") {
            let ad = String(yol.dropFirst(5))
            if ad.isEmpty || ad.contains("/") || ad.contains("..") {
                yanitla(gorev, 404)
            } else {
                dosyaGonder(gorev, webKlasoru.appendingPathComponent("lib").appendingPathComponent(ad),
                            "text/javascript; charset=utf-8")
            }
            return
        }
        if yol.hasPrefix("/onbellek/") {
            let id = String(yol.dropFirst(10))
            if Yardimci.kimlikGecerli(id), let v = try? Data(contentsOf: Yardimci.onbellekYolu(id)) {
                yanitla(gorev, 200, v, "audio/x-mpegurl; charset=utf-8")
            } else {
                yanitla(gorev, 404)
            }
            return
        }
        guard yol == "/bilgi" || yol == "/p" else {
            yanitla(gorev, 404)
            return
        }
        let sorgu = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func al(_ ad: String) -> String { sorgu.first(where: { $0.name == ad })?.value ?? "" }
        let hedef = al("u")
        var hedefURL = URL(string: hedef)
        if hedefURL == nil, let e = hedef.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            hedefURL = URL(string: e)
        }
        guard hedef.hasPrefix("http://") || hedef.hasPrefix("https://"), let adres = hedefURL else {
            yanitla(gorev, 400, Data("Gecersiz adres".utf8))
            return
        }
        let onb = al("onbellek")
        let k = Kayit(gorev: gorev, bilgi: yol == "/bilgi", ua: al("ua"), ref: al("ref"),
                      onbellek: Yardimci.kimlikGecerli(onb) ? onb : nil)
        var istek = URLRequest(url: adres, cachePolicy: .reloadIgnoringLocalCacheData,
                               timeoutInterval: k.bilgi ? 12 : 20)
        istek.setValue(k.ua.isEmpty ? Aktarici.varsayilanUA : k.ua, forHTTPHeaderField: "User-Agent")
        istek.setValue("*/*", forHTTPHeaderField: "Accept")
        if !k.ref.isEmpty { istek.setValue(k.ref, forHTTPHeaderField: "Referer") }
        if !k.bilgi, let aralik = gorev.request.value(forHTTPHeaderField: "Range") {
            istek.setValue(aralik, forHTTPHeaderField: "Range")
        }
        let ag = oturum.dataTask(with: istek)
        k.ag = ag
        agdan[ag.taskIdentifier] = k
        gorevden[ObjectIdentifier(gorev as AnyObject)] = k
        ag.resume()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        guard let k = gorevden[ObjectIdentifier(urlSchemeTask as AnyObject)] else { return }
        k.bitti = true            // kanal degisti ya da sayfa istegi birakti: goreve artik yazilmaz
        kapat(k, iptal: true)
    }

    // MARK: URLSessionDataDelegate (ana kuyrukta)

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let k = agdan[dataTask.taskIdentifier], !k.bitti, let h = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            return
        }
        k.yanit = h
        completionHandler(.allow)
        if k.bilgi && h.statusCode < 400 {
            // canli yayinda ilk baytlar icin en fazla 6 sn beklenir
            k.zamanlayici = Timer.scheduledTimer(withTimeInterval: 6, repeats: false) { [weak self, weak k] _ in
                guard let self = self, let k = k, !k.bitti else { return }
                self.bilgiBitir(k, nil)
            }
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let k = agdan[dataTask.taskIdentifier], !k.bitti else { return }
        if k.bilgi {
            k.tampon.append(data)
            let sinir = (k.yanit?.statusCode ?? 0) >= 400 ? 4096 : 2048
            if k.tampon.count >= sinir { bilgiBitir(k, nil) }
            return
        }
        aktar(k, data, son: false, hata: nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let k = agdan[task.taskIdentifier], !k.bitti else { return }
        if k.bilgi {
            bilgiBitir(k, error)
        } else {
            aktar(k, Data(), son: true, hata: error)
        }
    }

    // MARK: /bilgi: yayin turunu bulur

    private func bilgiBitir(_ k: Kayit, _ hata: Error?) {
        guard !k.bitti else { return }
        k.bitti = true
        let sonuc: [String: Any]
        if let h = k.yanit {
            if h.statusCode >= 400 {
                sonuc = ["ok": false, "durum": h.statusCode, "hata": "HTTP \(h.statusCode)",
                         "detay": Aktarici.sunucuMesaji(k.tampon)]
            } else {
                let tip = h.value(forHTTPHeaderField: "Content-Type") ?? ""
                sonuc = ["ok": true, "durum": h.statusCode, "icerik": tip,
                         "tur": Aktarici.turBul([UInt8](k.tampon.prefix(2048)), tip)]
            }
        } else {
            sonuc = ["ok": false, "durum": 0, "hata": Aktarici.hataMetni(hata)]
        }
        let veri = (try? JSONSerialization.data(withJSONObject: sonuc)) ?? Data("{}".utf8)
        let gorev = k.gorev
        kapat(k, iptal: true)
        yanitla(gorev, 200, veri, "application/json")
    }

    // MARK: /p: yayini, HLS listesini ya da kanal listesini aktarir

    private func aktar(_ k: Kayit, _ data: Data, son: Bool, hata: Error?) {
        guard let h = k.yanit else {
            if son {
                k.bitti = true
                let gorev = k.gorev
                kapat(k, iptal: false)
                yanitla(gorev, 502, Data(Aktarici.hataMetni(hata).utf8))
            }
            return
        }
        if h.statusCode >= 400 {
            k.tampon.append(data)
            if son || k.tampon.count >= 4096 {
                k.bitti = true
                let gorev = k.gorev
                let mesaj = Aktarici.sunucuMesaji(k.tampon)
                kapat(k, iptal: true)
                yanitla(gorev, h.statusCode, Data(mesaj.utf8))
            }
            return
        }
        switch k.asama {
        case 0:
            k.tampon.append(data)
            guard son || k.tampon.count >= 16 else { return }
            if Aktarici.m3uMu(k.tampon) {
                k.asama = 1
                aktar(k, Data(), son: son, hata: hata)
                return
            }
            akisBaslat(k, h, tur: h.value(forHTTPHeaderField: "Content-Type") ?? "application/octet-stream", liste: false)
            akit(k, son: son, hata: hata)
        case 1:
            k.tampon.append(data)
            guard son || k.tampon.count >= 65536 else { return }
            if k.tampon.range(of: Data("#EXT-X-".utf8)) != nil {
                k.asama = 2              // HLS calma listesi: tamami toplanip adresleri yeniden yazilir
                aktar(k, Data(), son: son, hata: hata)
                return
            }
            akisBaslat(k, h, tur: "audio/x-mpegurl; charset=utf-8", liste: true)   // IPTV kanal listesi
            akit(k, son: son, hata: hata)
        case 2:
            k.tampon.append(data)
            let asiri = k.tampon.count > 50 * 1024 * 1024
            guard son || asiri else { return }
            k.bitti = true
            let gorev = k.gorev
            if let e = hata {
                kapat(k, iptal: true)
                yanitla(gorev, 502, Data(Aktarici.hataMetni(e).utf8))
                return
            }
            let metin = String(decoding: k.tampon, as: UTF8.self)
            let yeni = Aktarici.m3u8YenidenYaz(metin, h.url ?? k.ag?.originalRequest?.url, k.ua, k.ref)
            kapat(k, iptal: true)
            yanitla(gorev, 200, Data(yeni.utf8), "application/vnd.apple.mpegurl")
        default:
            k.tampon.append(data)
            akit(k, son: son, hata: hata)
        }
    }

    private func akisBaslat(_ k: Kayit, _ h: HTTPURLResponse, tur: String, liste: Bool) {
        k.asama = 3
        var b: [String: String] = ["Content-Type": tur, "Cache-Control": "no-store"]
        let sikistirma = (h.value(forHTTPHeaderField: "Content-Encoding") ?? "").lowercased()
        if sikistirma.isEmpty || sikistirma == "identity", let u = h.value(forHTTPHeaderField: "Content-Length") {
            b["Content-Length"] = u      // URLSession sikistirilmis govdeyi actiginda uzunluk gonderilmez
        }
        if !liste {
            for ad in ["Content-Range", "Accept-Ranges"] {
                if let v = h.value(forHTTPHeaderField: ad) { b[ad] = v }
            }
        }
        if let url = k.gorev.request.url,
           let r = HTTPURLResponse(url: url, statusCode: liste ? 200 : h.statusCode, httpVersion: "HTTP/1.1", headerFields: b) {
            k.gorev.didReceive(r)
        }
        if liste, let id = k.onbellek {
            let gecici = Yardimci.onbellekKlasoru.appendingPathComponent(id + "." + UUID().uuidString + ".tmp")
            if FileManager.default.createFile(atPath: gecici.path, contents: nil) {
                k.gecici = gecici
                k.dosya = try? FileHandle(forWritingTo: gecici)
            }
        }
    }

    private func akit(_ k: Kayit, son: Bool, hata: Error?) {
        if !k.tampon.isEmpty {
            k.gorev.didReceive(k.tampon)
            if let d = k.dosya { try? d.write(contentsOf: k.tampon) }
            k.tampon = Data()
        }
        guard son else { return }
        k.bitti = true
        if hata == nil, let d = k.dosya, let g = k.gecici, let id = k.onbellek {
            try? d.close()
            k.dosya = nil
            k.gecici = nil
            let hedef = Yardimci.onbellekYolu(id)
            try? FileManager.default.removeItem(at: hedef)
            try? FileManager.default.moveItem(at: g, to: hedef)
        }
        let gorev = k.gorev
        kapat(k, iptal: false)
        if let e = hata {
            gorev.didFailWithError(e)
        } else {
            gorev.didFinish()
        }
    }

    private func kapat(_ k: Kayit, iptal: Bool) {
        k.zamanlayici?.invalidate()
        k.zamanlayici = nil
        if let ag = k.ag {
            agdan.removeValue(forKey: ag.taskIdentifier)
            if iptal { ag.cancel() }
        }
        gorevden.removeValue(forKey: ObjectIdentifier(k.gorev as AnyObject))
        if let d = k.dosya {
            try? d.close()
            k.dosya = nil
            if let g = k.gecici { try? FileManager.default.removeItem(at: g) }
            k.gecici = nil
        }
    }

    // MARK: yanit yardimcilari

    private func yanitla(_ gorev: WKURLSchemeTask, _ kod: Int, _ veri: Data = Data(),
                         _ tur: String = "text/plain; charset=utf-8") {
        let basliklar = ["Content-Type": tur, "Content-Length": String(veri.count), "Cache-Control": "no-store"]
        guard let url = gorev.request.url,
              let r = HTTPURLResponse(url: url, statusCode: kod, httpVersion: "HTTP/1.1", headerFields: basliklar) else {
            gorev.didFailWithError(URLError(.badServerResponse))
            return
        }
        gorev.didReceive(r)
        if !veri.isEmpty { gorev.didReceive(veri) }
        gorev.didFinish()
    }

    private func dosyaGonder(_ gorev: WKURLSchemeTask, _ dosya: URL, _ tur: String) {
        if let v = try? Data(contentsOf: dosya) {
            yanitla(gorev, 200, v, tur)
        } else {
            yanitla(gorev, 404)
        }
    }

    // MARK: masaustundeki yardimcilarin karsiliklari

    static func m3uMu(_ d: Data) -> Bool {
        let b = [UInt8](d.prefix(64))
        var i = 0
        while i < b.count, bosluk.contains(b[i]) { i += 1 }
        let s = String(decoding: b[i...], as: UTF8.self)
        return s.hasPrefix("#EXTM3U") || s.hasPrefix("#EXTINF")
    }

    /// Gelen ilk baytlara ve basliga bakarak yayin turunu bulur
    static func turBul(_ b: [UInt8], _ tip: String) -> String {
        let t = tip.lowercased()
        var i = 0
        while i < b.count, bosluk.contains(b[i]) { i += 1 }
        let bas = String(decoding: b[i..<min(b.count, i + 8)], as: UTF8.self)
        if bas.hasPrefix("#EXTM3U") || bas.hasPrefix("#EXTINF") {
            return String(decoding: b, as: UTF8.self).contains("#EXT-X-") ? "hls" : "liste"
        }
        for j in 0..<min(188, b.count) where b[j] == 0x47 && b.count - j > 188 {   // MPEG-TS: her 188 baytta 0x47
            var tamam = true
            for n in [1, 2] where j + n * 188 < b.count && b[j + n * 188] != 0x47 { tamam = false }
            if tamam { return "ts" }
        }
        func esit(_ a: Int, _ s: String) -> Bool {
            let u = Array(s.utf8)
            return b.count >= a + u.count && Array(b[a..<(a + u.count)]) == u
        }
        if esit(0, "FLV") { return "flv" }
        if esit(4, "ftyp") || esit(0, "OggS") || esit(0, "fLaC") || esit(0, "RIFF") || esit(0, "ID3") { return "dogal" }
        if b.count > 1 && b[0] == 0xFF && (b[1] & 0xE0) == 0xE0 { return "dogal" }   // MP3 / AAC
        if t.contains("mpegurl") { return "hls" }
        if t.contains("mp2t") { return "ts" }
        if t.contains("flv") { return "flv" }
        if t.hasPrefix("audio/") || t.hasPrefix("video/") { return "dogal" }
        if t.contains("html") || bas.hasPrefix("<") { return "html" }
        return "bilinmiyor"
    }

    /// Sunucunun hata sayfasindaki kisa aciklama (etiketler ayiklanmis, en fazla 200 karakter)
    static func sunucuMesaji(_ d: Data) -> String {
        var m = String(decoding: d.prefix(4096), as: UTF8.self)
        m = m.replacingOccurrences(of: "(?is)<(script|style|head)[^>]*>.*?</\\1>", with: " ", options: .regularExpression)
        m = m.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        for (a, b) in [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&amp;", "&")] {
            m = m.replacingOccurrences(of: a, with: b)
        }
        m = m.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return String(m.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
    }

    static func hataMetni(_ e: Error?) -> String {
        guard let e = e else { return "Sunucuya bağlanılamadı" }
        guard let u = e as? URLError else { return String(e.localizedDescription.prefix(160)) }
        switch u.code {
        case .timedOut: return "Sunucu zamanında cevap vermedi"
        case .cannotFindHost, .dnsLookupFailed: return "Sunucu adresi bulunamadı"
        case .cannotConnectToHost: return "Sunucu bağlantıyı reddetti"
        case .notConnectedToInternet, .networkConnectionLost: return "İnternet bağlantısı yok ya da koptu"
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot:
            return "Güvenli bağlantı (SSL) kurulamadı"
        default: return String(u.localizedDescription.prefix(160))
        }
    }

    static let izinli = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~")

    static func kodla(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: izinli) ?? s
    }

    static func vekil(_ u: String, _ ua: String, _ ref: String) -> String {
        var s = "/p?u=" + kodla(u)
        if !ua.isEmpty { s += "&ua=" + kodla(ua) }
        if !ref.isEmpty { s += "&ref=" + kodla(ref) }
        return s
    }

    /// HLS listesindeki tum adresleri yerel aktarici uzerinden gecirir
    static func m3u8YenidenYaz(_ metin: String, _ taban: URL?, _ ua: String, _ ref: String) -> String {
        func tam(_ s: String) -> String {
            if let u = URL(string: s, relativeTo: taban) { return u.absoluteString }
            if let e = s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
               let u = URL(string: e, relativeTo: taban) { return u.absoluteString }
            return s
        }
        var cikti: [String] = []
        let satirlar = metin.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false)
        for parca in satirlar {
            var satir = String(parca)
            let s = satir.trimmingCharacters(in: .whitespaces)
            if !s.isEmpty && !s.hasPrefix("#") {
                satir = vekil(tam(s), ua, ref)
            } else if let a = s.range(of: "URI=\"") {
                let kalan = s[a.upperBound...]
                if let b = kalan.firstIndex(of: "\"") {
                    satir = String(s[..<a.upperBound]) + vekil(tam(String(kalan[..<b])), ua, ref) + String(kalan[b...])
                }
            }
            cikti.append(satir)
        }
        return cikti.joined(separator: "\n")
    }
}
