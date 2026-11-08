import AVFoundation
import UIKit

/// GammaTV iPhone: tek ekranli uygulama; arayuz WKWebView icinde, yayin istekleri Aktarici uzerinden.
@main
final class Uygulama: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // sessiz dugmesi aciktayken de yayinin sesi gelsin
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        let w = UIWindow(frame: UIScreen.main.bounds)
        w.rootViewController = AnaEkran()
        w.makeKeyAndVisible()
        window = w
        return true
    }
}
