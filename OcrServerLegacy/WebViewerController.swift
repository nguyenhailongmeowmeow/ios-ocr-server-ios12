//
//  WebViewerController.swift
//  OcrServer (iOS 12 Legacy)
//
//  WKWebView wrapper with progress bar.
//

import UIKit
import WebKit

class WebViewerController: UIViewController, WKNavigationDelegate {
    
    private var webView: WKWebView!
    private var progressView: UIProgressView!
    private var urlString: String
    private var progressObservation: NSKeyValueObservation?
    private var loadingObservation: NSKeyValueObservation?
    
    init(urlString: String) {
        self.urlString = urlString
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = urlString
        view.backgroundColor = .white
        
        // Close button
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "✕", style: .plain, target: self, action: #selector(dismissSelf)
        )
        
        // Progress view
        progressView = UIProgressView(progressViewStyle: .default)
        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.trackTintColor = .clear
        view.addSubview(progressView)
        
        // WebView
        webView = WKWebView(frame: .zero)
        webView.navigationDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        
        NSLayoutConstraint.activate([
            progressView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            progressView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            
            webView.topAnchor.constraint(equalTo: progressView.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        // KVO for progress
        progressObservation = webView.observe(\.estimatedProgress, options: .new) { [weak self] webView, _ in
            DispatchQueue.main.async {
                let progress = Float(webView.estimatedProgress)
                self?.progressView.setProgress(progress, animated: true)
                self?.progressView.isHidden = (progress >= 1.0)
            }
        }
        
        loadingObservation = webView.observe(\.isLoading, options: .new) { [weak self] webView, _ in
            DispatchQueue.main.async {
                if !webView.isLoading {
                    self?.progressView.isHidden = true
                }
                self?.updateBackButton()
            }
        }
        
        // Load URL
        if let url = URL(string: urlString) {
            webView.load(URLRequest(url: url))
        }
    }
    
    deinit {
        progressObservation?.invalidate()
        loadingObservation?.invalidate()
    }
    
    private func updateBackButton() {
        if webView.canGoBack {
            navigationItem.leftBarButtonItem = UIBarButtonItem(
                title: "◀", style: .plain, target: self, action: #selector(goBack)
            )
        } else {
            navigationItem.leftBarButtonItem = nil
        }
    }
    
    @objc private func goBack() {
        webView.goBack()
    }
    
    @objc private func dismissSelf() {
        dismiss(animated: true)
    }
}
