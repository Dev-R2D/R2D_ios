#if canImport(UIKit) && canImport(WebKit)
import UIKit
import WebKit

public final class GameWebViewController: UIViewController, WKScriptMessageHandler {
    private let webView: WKWebView

    public init() {
        let contentController = WKUserContentController()
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init(nibName: nil, bundle: nil)
        contentController.add(self, name: "r2dNative")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        title = "R2D Game"
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(close))
        view.backgroundColor = .black
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        loadPlaceholderGame()
    }

    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        // JS game events land here. Later this can forward ride/session data into R2DCore.
        print("R2D JS message:", message.body)
    }

    private func loadPlaceholderGame() {
        let html = """
        <!doctype html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            body { margin:0; background:#071114; color:white; font-family:-apple-system, BlinkMacSystemFont, sans-serif; }
            main { min-height:100vh; display:grid; place-items:center; text-align:center; padding:24px; box-sizing:border-box; }
            button { border:0; border-radius:10px; padding:14px 18px; background:#35d399; color:#06100d; font-weight:800; }
          </style>
        </head>
        <body>
          <main>
            <section>
              <h1>R2D JS Game Layer</h1>
              <p>JavaScript 게임 번들을 여기에 로드합니다.</p>
              <button onclick="window.webkit.messageHandlers.r2dNative.postMessage({type:'game-ready'})">Native Bridge Test</button>
            </section>
          </main>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }

    @objc private func close() {
        dismiss(animated: true)
    }
}
#endif
