//
//  MainViewController.swift
//  OcrServer (iOS 12 Legacy)
//
//  Main screen showing server status and IP addresses.
//

import UIKit

class MainViewController: UIViewController {
    
    // MARK: - UI Elements
    
    private let titleLabel = UILabel()
    private let statusLabel = UILabel()
    private let addressStackView = UIStackView()
    private let readmeButton = UIButton(type: .system)
    private let refreshButton = UIButton(type: .system)
    private var refreshIndicator: UIActivityIndicatorView!
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        navigationController?.setNavigationBarHidden(true, animated: false)
        setupUI()
        updateUI()
        
        NotificationCenter.default.addObserver(
            self, selector: #selector(serverStatusChanged),
            name: .serverStatusDidChange, object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }
    
    // MARK: - Setup UI
    
    private func setupUI() {
        // Top-left: Donation button
        let donationBtn = createIconButton(systemName: "cup.and.saucer", fallbackText: "☕", target: self, action: #selector(openDonation))
        view.addSubview(donationBtn)
        donationBtn.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            donationBtn.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            donationBtn.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            donationBtn.widthAnchor.constraint(equalToConstant: 44),
            donationBtn.heightAnchor.constraint(equalToConstant: 44)
        ])
        
        // Top-right: Monitor + Settings buttons
        let monitorBtn = createIconButton(systemName: "waveform.path.ecg.rectangle", fallbackText: "📊", target: self, action: #selector(openMonitor))
        let settingsBtn = createIconButton(systemName: "gearshape", fallbackText: "⚙️", target: self, action: #selector(openSettings))
        
        let topRightStack = UIStackView(arrangedSubviews: [monitorBtn, settingsBtn])
        topRightStack.axis = .horizontal
        topRightStack.spacing = 12
        view.addSubview(topRightStack)
        topRightStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            topRightStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            topRightStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
        ])
        
        // Center content
        let contentStack = UIStackView()
        contentStack.axis = .vertical
        contentStack.alignment = .center
        contentStack.spacing = 10
        view.addSubview(contentStack)
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            contentStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            contentStack.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -40),
            contentStack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20)
        ])
        
        // README + Refresh buttons row
        configureButton(readmeButton, title: " README", color: UIColor(red: 0.3, green: 0.7, blue: 0.3, alpha: 1.0), iconName: "text.page", fallback: "📄")
        readmeButton.addTarget(self, action: #selector(openReadme), for: .touchUpInside)
        
        refreshIndicator = UIActivityIndicatorView(style: .white)
        refreshIndicator.hidesWhenStopped = true
        
        configureButton(refreshButton, title: " Refresh IP", color: UIColor(red: 0.3, green: 0.5, blue: 0.9, alpha: 1.0), iconName: "arrow.clockwise", fallback: "🔄")
        refreshButton.addTarget(self, action: #selector(refreshNetwork), for: .touchUpInside)
        
        let buttonRow = UIStackView(arrangedSubviews: [readmeButton, refreshButton])
        buttonRow.axis = .horizontal
        buttonRow.spacing = 12
        contentStack.addArrangedSubview(buttonRow)
        
        // Spacer
        let spacer1 = UIView()
        spacer1.heightAnchor.constraint(equalToConstant: 40).isActive = true
        contentStack.addArrangedSubview(spacer1)
        
        // Title
        titleLabel.text = "OCR Server v\(Bundle.main.appVersion)"
        titleLabel.font = UIFont.systemFont(ofSize: 22, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        contentStack.addArrangedSubview(titleLabel)
        
        // Status
        statusLabel.font = UIFont.systemFont(ofSize: 17, weight: .medium)
        statusLabel.textColor = .white
        statusLabel.textAlignment = .center
        contentStack.addArrangedSubview(statusLabel)
        
        // Spacer
        let spacer2 = UIView()
        spacer2.heightAnchor.constraint(equalToConstant: 60).isActive = true
        contentStack.addArrangedSubview(spacer2)
        
        // Network addresses container
        addressStackView.axis = .vertical
        addressStackView.alignment = .center
        addressStackView.spacing = 20
        contentStack.addArrangedSubview(addressStackView)
    }
    
    private func configureButton(_ button: UIButton, title: String, color: UIColor, iconName: String, fallback: String) {
        if #available(iOS 13.0, *) {
            let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
            let icon = UIImage(systemName: iconName, withConfiguration: config)
            button.setImage(icon, for: .normal)
        }
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        button.setTitleColor(.white, for: .normal)
        button.tintColor = .white
        button.backgroundColor = color
        button.layer.cornerRadius = 8
        button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
    }
    
    // MARK: - Update UI
    
    @objc private func serverStatusChanged() {
        DispatchQueue.main.async { [weak self] in
            self?.updateUI()
        }
    }
    
    private func updateUI() {
        let manager = ServerManager.shared
        statusLabel.text = "Status : \(manager.status)"
        
        // Update addresses
        addressStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        
        let sortedKeys = manager.networkAddresses.keys.sorted()
        for key in sortedKeys {
            guard let ip = manager.networkAddresses[key] else { continue }
            let displayName = getDisplayName(for: key)
            let addressString = "http://\(ip):\(manager.port)"
            
            let nameLabel = UILabel()
            nameLabel.text = displayName
            nameLabel.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
            nameLabel.textColor = .white
            nameLabel.textAlignment = .center
            
            let addrButton = UIButton(type: .system)
            addrButton.setTitle(addressString, for: .normal)
            addrButton.titleLabel?.font = UIFont.systemFont(ofSize: 22, weight: .regular)
            addrButton.setTitleColor(.white, for: .normal)
            addrButton.titleLabel?.minimumScaleFactor = 0.5
            addrButton.titleLabel?.adjustsFontSizeToFitWidth = true
            
            // Underline
            let attrs: [NSAttributedString.Key: Any] = [
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .foregroundColor: UIColor.white,
                .font: UIFont.systemFont(ofSize: 22)
            ]
            addrButton.setAttributedTitle(NSAttributedString(string: addressString, attributes: attrs), for: .normal)
            addrButton.accessibilityIdentifier = addressString
            addrButton.addTarget(self, action: #selector(addressTapped(_:)), for: .touchUpInside)
            
            let ifaceStack = UIStackView(arrangedSubviews: [nameLabel, addrButton])
            ifaceStack.axis = .vertical
            ifaceStack.alignment = .center
            ifaceStack.spacing = 5
            addressStackView.addArrangedSubview(ifaceStack)
        }
        
        if sortedKeys.isEmpty {
            let noIPLabel = UILabel()
            noIPLabel.text = NSLocalizedString("No available IP found", comment: "")
            noIPLabel.font = UIFont.systemFont(ofSize: 17)
            noIPLabel.textColor = UIColor.lightGray
            noIPLabel.textAlignment = .center
            addressStackView.addArrangedSubview(noIPLabel)
        }
    }
    
    private func getDisplayName(for interfaceName: String) -> String {
        switch interfaceName {
        case "en0": return "Wifi (en0)"
        default: return "Ethernet (\(interfaceName))"
        }
    }
    
    // MARK: - Actions
    
    @objc private func addressTapped(_ sender: UIButton) {
        guard let urlString = sender.accessibilityIdentifier else { return }
        let webVC = WebViewerController(urlString: urlString)
        let nav = UINavigationController(rootViewController: webVC)
        nav.modalPresentationStyle = .fullScreen
        present(nav, animated: true)
    }
    
    @objc private func refreshNetwork() {
        refreshButton.isEnabled = false
        refreshButton.backgroundColor = UIColor.gray.withAlphaComponent(0.7)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            ServerManager.shared.refreshNetworkAddresses()
            self?.updateUI()
            self?.refreshButton.isEnabled = true
            self?.refreshButton.backgroundColor = UIColor(red: 0.3, green: 0.5, blue: 0.9, alpha: 1.0)
        }
    }
    
    @objc private func openReadme() {
        let webVC = WebViewerController(urlString: "https://github.com/riddleling/iOS-OCR-Server/blob/main/README.md")
        webVC.title = "README"
        let nav = UINavigationController(rootViewController: webVC)
        nav.modalPresentationStyle = .fullScreen
        present(nav, animated: true)
    }
    
    @objc private func openSettings() {
        let settingsVC = SettingsViewController()
        let nav = UINavigationController(rootViewController: settingsVC)
        nav.modalPresentationStyle = .fullScreen
        present(nav, animated: true)
    }
    
    @objc private func openMonitor() {
        let monitorVC = MonitorViewController()
        let nav = UINavigationController(rootViewController: monitorVC)
        nav.modalPresentationStyle = .fullScreen
        present(nav, animated: true)
    }
    
    @objc private func openDonation() {
        let donationVC = DonationViewController()
        let nav = UINavigationController(rootViewController: donationVC)
        nav.modalPresentationStyle = .fullScreen
        present(nav, animated: true)
    }
}
