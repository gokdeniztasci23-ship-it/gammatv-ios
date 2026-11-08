import UIKit

/// Kayit (veri.json), liste onbellegi ve renk yardimcilari
enum Yardimci {
    static let klasor: URL = {
        let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GammaTV", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }()

    static let onbellekKlasoru: URL = {
        let u = klasor.appendingPathComponent("onbellek", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }()

    static func veriOku() -> String {
        (try? String(contentsOf: klasor.appendingPathComponent("veri.json"), encoding: .utf8)) ?? "{}"
    }

    static func veriYaz(_ s: String) {
        try? s.write(to: klasor.appendingPathComponent("veri.json"), atomically: true, encoding: .utf8)
    }

    /// Liste kimligi: yalnizca kucuk harf ve rakam, en fazla 40 karakter (masaustundeki kuralin aynisi)
    static func kimlikGecerli(_ id: String) -> Bool {
        guard !id.isEmpty, id.count <= 40 else { return false }
        return id.unicodeScalars.allSatisfy { ($0.value >= 97 && $0.value <= 122) || ($0.value >= 48 && $0.value <= 57) }
    }

    static func onbellekYolu(_ id: String) -> URL {
        onbellekKlasoru.appendingPathComponent(id + ".m3u")
    }

    static func onbellekYaz(_ id: String, _ metin: String) {
        guard kimlikGecerli(id) else { return }
        try? metin.write(to: onbellekYolu(id), atomically: true, encoding: .utf8)
    }

    static func onbellekSil(_ id: String) {
        guard kimlikGecerli(id) else { return }
        try? FileManager.default.removeItem(at: onbellekYolu(id))
    }

    /// "#rrggbb" -> UIColor
    static func renk(_ s: String?) -> UIColor? {
        guard let s = s?.trimmingCharacters(in: .whitespaces), s.hasPrefix("#"), s.count == 7,
              let n = UInt32(String(s.dropFirst()), radix: 16) else { return nil }
        return UIColor(red: CGFloat((n >> 16) & 0xFF) / 255,
                       green: CGFloat((n >> 8) & 0xFF) / 255,
                       blue: CGFloat(n & 0xFF) / 255, alpha: 1)
    }

    /// Bir sonraki acilisin ilk karesi: tema elle secildiyse onun rengi, yoksa telefonun temasi
    static func acilisKaydet(_ s: String) {
        UserDefaults.standard.set(s, forKey: "acilisRengi")
    }

    static func acilisRengi() -> (renk: UIColor, acik: Bool) {
        if let s = UserDefaults.standard.string(forKey: "acilisRengi"), let r = renk(s) {
            return (r, s.lowercased() == "#ffffff")
        }
        let koyu = UIScreen.main.traitCollection.userInterfaceStyle == .dark
        return (koyu ? UIColor.black : UIColor.white, !koyu)
    }
}
