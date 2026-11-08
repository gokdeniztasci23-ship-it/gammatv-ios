import UIKit
import WebKit

/// Tek ekran: ustte ve altta guvenli alan seritleri (sayfanin renginde), ortada arayuz.
final class AnaEkran: UIViewController, WKScriptMessageHandlerWithReply, WKNavigationDelegate, WKUIDelegate {
    private var web: WKWebView!
    private let ustAlan = UIView()
    private let altAlan = UIView()
    private let aktarici = Aktarici()
    private var acikCubuk = false
    private var tamEkran = false

    override var preferredStatusBarStyle: UIStatusBarStyle { acikCubuk ? .darkContent : .lightContent }
    override var prefersStatusBarHidden: Bool { tamEkran }
    override var prefersHomeIndicatorAutoHidden: Bool { tamEkran }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .allButUpsideDown }

    override func viewDidLoad() {
        super.viewDidLoad()
        let ilk = Yardimci.acilisRengi()
        acikCubuk = ilk.acik
        view.backgroundColor = ilk.renk
        ustAlan.backgroundColor = ilk.renk
        altAlan.backgroundColor = ilk.renk

        let ayar = WKWebViewConfiguration()
        ayar.setURLSchemeHandler(aktarici, forURLScheme: "gammatv")
        ayar.allowsInlineMediaPlayback = true
        ayar.mediaTypesRequiringUserActionForPlayback = []
        ayar.allowsAirPlayForMediaPlayback = true
        ayar.allowsPictureInPictureMediaPlayback = true
        ayar.userContentController.addScriptMessageHandler(self, contentWorld: .page, name: "gamma")

        let w = WKWebView(frame: .zero, configuration: ayar)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.scrollView.backgroundColor = .clear
        w.scrollView.contentInsetAdjustmentBehavior = .never
        w.scrollView.bounces = false
        w.scrollView.minimumZoomScale = 1
        w.scrollView.maximumZoomScale = 1
        w.scrollView.bouncesZoom = false
        w.navigationDelegate = self
        w.uiDelegate = self
        if #available(iOS 16.4, *) { w.isInspectable = true }
        web = w

        for v in [ustAlan, altAlan, w] as [UIView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(v)
        }
        let g = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            ustAlan.topAnchor.constraint(equalTo: view.topAnchor),
            ustAlan.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            ustAlan.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            ustAlan.bottomAnchor.constraint(equalTo: g.topAnchor),
            altAlan.topAnchor.constraint(equalTo: g.bottomAnchor),
            altAlan.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            altAlan.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            altAlan.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            w.topAnchor.constraint(equalTo: g.topAnchor),
            w.bottomAnchor.constraint(equalTo: g.bottomAnchor),
            w.leadingAnchor.constraint(equalTo: g.leadingAnchor),
            w.trailingAnchor.constraint(equalTo: g.trailingAnchor),
        ])
        // klavye kapaninca iOS sayfayi yukari kaydirilmis birakir: geri sifirlanir
        NotificationCenter.default.addObserver(self, selector: #selector(klavyeKapandi),
                                               name: UIResponder.keyboardDidHideNotification, object: nil)
        if let adres = URL(string: "gammatv://app/index.html") {
            w.load(URLRequest(url: adres))
        }
    }

    @objc private func klavyeKapandi() {
        web.scrollView.setContentOffset(.zero, animated: true)
    }

    // MARK: sayfadan gelen istekler (window.webkit.messageHandlers.gamma.postMessage)

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        guard let g = message.body as? [String: Any], let k = g["k"] as? String else {
            replyHandler(nil, "gecersiz istek")
            return
        }
        switch k {
        case "yukle":
            replyHandler(Yardimci.veriOku(), nil)
        case "kaydet":
            Yardimci.veriYaz(g["v"] as? String ?? "{}")
            replyHandler(true, nil)
        case "onbYaz":
            Yardimci.onbellekYaz(g["id"] as? String ?? "", g["t"] as? String ?? "")
            replyHandler(true, nil)
        case "onbSil":
            Yardimci.onbellekSil(g["id"] as? String ?? "")
            replyHandler(true, nil)
        case "tamEkran":
            tamEkran = (g["a"] as? Bool) ?? false
            if tamEkran {
                ustAlan.backgroundColor = .black
                altAlan.backgroundColor = .black
                view.backgroundColor = .black
            }
            setNeedsStatusBarAppearanceUpdate()
            setNeedsUpdateOfHomeIndicatorAutoHidden()
            replyHandler(tamEkran, nil)
        case "cubuk":
            if !tamEkran {
                if let u = Yardimci.renk(g["ust"] as? String) {
                    ustAlan.backgroundColor = u
                    view.backgroundColor = u
                }
                if let a = Yardimci.renk(g["alt"] as? String) { altAlan.backgroundColor = a }
            }
            acikCubuk = (g["acik"] as? Bool) ?? false
            setNeedsStatusBarAppearanceUpdate()
            if let s = g["acilis"] as? String { Yardimci.acilisKaydet(s) }
            replyHandler(true, nil)
        default:
            replyHandler(nil, "bilinmeyen istek")
        }
    }

    // MARK: gezinme: uygulama sayfasi disindaki baglantilar Safari'de acilir

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let u = navigationAction.request.url, u.scheme != "gammatv", u.scheme != "about",
           navigationAction.targetFrame?.isMainFrame ?? true {
            UIApplication.shared.open(u)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let u = navigationAction.request.url { UIApplication.shared.open(u) }
        return nil
    }

    /// Uygulama gibi davranir: iki parmakla ya da cift dokunusla yakinlastirma yok
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.scrollView.pinchGestureRecognizer?.isEnabled = false
        webView.scrollView.minimumZoomScale = 1
        webView.scrollView.maximumZoomScale = 1
    }

    /// Arayuz sureci (bellek yetersizligi gibi nedenlerle) kapanirsa sayfa yeniden yuklenir
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }
}
