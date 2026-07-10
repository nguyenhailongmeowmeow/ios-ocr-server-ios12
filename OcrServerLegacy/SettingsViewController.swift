//
//  SettingsViewController.swift
//  OcrServer (iOS 12 Legacy)
//
//  Settings screen with UITableView.
//

import UIKit

class SettingsViewController: UITableViewController {
    
    private var recognitionLevel = Settings.shared.recognitionLevel
    private var languageCorrection = Settings.shared.languageCorrection
    private var autoDetectLanguage = Settings.shared.automaticallyDetectsLanguage
    private var httpPort = String(Settings.shared.httpPort)
    
    private let langCorrectionSwitch = UISwitch()
    private let autoDetectSwitch = UISwitch()
    private var applyButton: UIButton!
    private var activityIndicator: UIActivityIndicatorView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = NSLocalizedString("Settings", comment: "")
        
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "✕", style: .plain, target: self, action: #selector(dismissSelf)
        )
        
        tableView = UITableView(frame: .zero, style: .grouped)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        
        langCorrectionSwitch.isOn = languageCorrection
        langCorrectionSwitch.addTarget(self, action: #selector(langCorrectionChanged), for: .valueChanged)
        
        autoDetectSwitch.isOn = autoDetectLanguage
        autoDetectSwitch.addTarget(self, action: #selector(autoDetectChanged), for: .valueChanged)
    }
    
    // MARK: - TableView DataSource
    
    override func numberOfSections(in tableView: UITableView) -> Int { return 3 }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return 3  // Recognition Level, Language Correction, Auto Detect
        case 1: return 1  // HTTP Port
        case 2: return 1  // Apply button
        default: return 0
        }
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0: return "Text Recognition"
        case 1: return "Server"
        default: return nil
        }
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: "Cell")
        cell.selectionStyle = .none
        
        switch (indexPath.section, indexPath.row) {
        case (0, 0):
            // Recognition Level
            if #available(iOS 13.0, *) {
                cell.imageView?.image = UIImage(systemName: "text.viewfinder")
            }
            cell.textLabel?.text = NSLocalizedString("Recognition Level", comment: "")
            cell.detailTextLabel?.text = getLocalizedLevel(recognitionLevel)
            cell.accessoryType = .disclosureIndicator
            cell.selectionStyle = .default
            
        case (0, 1):
            // Language Correction
            if #available(iOS 13.0, *) {
                cell.imageView?.image = UIImage(systemName: "text.badge.checkmark")
            }
            cell.textLabel?.text = NSLocalizedString("Language Correction", comment: "")
            cell.accessoryView = langCorrectionSwitch
            
        case (0, 2):
            // Auto Detect Language
            if #available(iOS 13.0, *) {
                cell.imageView?.image = UIImage(systemName: "globe")
            }
            cell.textLabel?.text = NSLocalizedString("Auto Detects Language", comment: "")
            cell.accessoryView = autoDetectSwitch
            
        case (1, 0):
            // HTTP Port
            if #available(iOS 13.0, *) {
                cell.imageView?.image = UIImage(systemName: "server.rack")
            }
            cell.textLabel?.text = "HTTP Port"
            cell.detailTextLabel?.text = httpPort
            cell.accessoryType = .disclosureIndicator
            cell.selectionStyle = .default
            
        case (2, 0):
            // Apply button cell
            cell.textLabel?.text = nil
            let container = UIView()
            container.translatesAutoresizingMaskIntoConstraints = false
            cell.contentView.addSubview(container)
            NSLayoutConstraint.activate([
                container.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 8),
                container.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -8),
                container.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 16),
                container.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -16),
                container.heightAnchor.constraint(equalToConstant: 44)
            ])
            
            applyButton = UIButton(type: .system)
            applyButton.setTitle("Apply & Restart server", for: .normal)
            applyButton.setTitleColor(.white, for: .normal)
            applyButton.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .bold)
            applyButton.backgroundColor = UIColor(hex: "EA7500")
            applyButton.layer.cornerRadius = 8
            applyButton.translatesAutoresizingMaskIntoConstraints = false
            applyButton.addTarget(self, action: #selector(applyAndRestart), for: .touchUpInside)
            container.addSubview(applyButton)
            
            activityIndicator = UIActivityIndicatorView(style: .white)
            activityIndicator.hidesWhenStopped = true
            activityIndicator.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(activityIndicator)
            
            NSLayoutConstraint.activate([
                applyButton.topAnchor.constraint(equalTo: container.topAnchor),
                applyButton.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                applyButton.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                applyButton.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                activityIndicator.centerYAnchor.constraint(equalTo: applyButton.centerYAnchor),
                activityIndicator.trailingAnchor.constraint(equalTo: applyButton.trailingAnchor, constant: -16)
            ])
            
        default:
            break
        }
        
        return cell
    }
    
    // MARK: - TableView Delegate
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        switch (indexPath.section, indexPath.row) {
        case (0, 0):
            // Push recognition level picker
            let levelVC = RecognitionLevelViewController(currentLevel: recognitionLevel) { [weak self] newLevel in
                self?.recognitionLevel = newLevel
                Settings.shared.recognitionLevel = newLevel
                self?.tableView.reloadRows(at: [indexPath], with: .none)
            }
            navigationController?.pushViewController(levelVC, animated: true)
            
        case (1, 0):
            // Show port input alert
            showPortInputAlert()
            
        default:
            break
        }
    }
    
    // MARK: - Actions
    
    @objc private func langCorrectionChanged() {
        languageCorrection = langCorrectionSwitch.isOn
        Settings.shared.languageCorrection = languageCorrection
    }
    
    @objc private func autoDetectChanged() {
        autoDetectLanguage = autoDetectSwitch.isOn
        Settings.shared.automaticallyDetectsLanguage = autoDetectLanguage
    }
    
    @objc private func applyAndRestart() {
        applyButton.isEnabled = false
        applyButton.backgroundColor = .gray
        activityIndicator.startAnimating()
        
        ServerManager.shared.restartServer()
        
        // Re-enable after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.applyButton.isEnabled = true
            self?.applyButton.backgroundColor = UIColor(hex: "EA7500")
            self?.activityIndicator.stopAnimating()
        }
    }
    
    @objc private func dismissSelf() {
        dismiss(animated: true)
    }
    
    private func showPortInputAlert() {
        let alert = UIAlertController(title: "Set HTTP Port", message: nil, preferredStyle: .alert)
        alert.addTextField { [weak self] tf in
            tf.text = self?.httpPort
            tf.keyboardType = .numberPad
            tf.placeholder = "1-65535"
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Confirm", style: .default) { [weak self] _ in
            guard let text = alert.textFields?.first?.text,
                  let port = Int(text.trimmingCharacters(in: .whitespaces)),
                  (1...65535).contains(port) else { return }
            self?.httpPort = String(port)
            Settings.shared.httpPort = port
            self?.tableView.reloadData()
        })
        present(alert, animated: true)
    }
    
    private func getLocalizedLevel(_ level: String) -> String {
        switch level {
        case "Accurate": return NSLocalizedString("Accurate", comment: "")
        case "Fast": return NSLocalizedString("Fast", comment: "")
        default: return level
        }
    }
}

// MARK: - Recognition Level Picker

class RecognitionLevelViewController: UITableViewController {
    
    private let levels = ["Accurate", "Fast"]
    private var currentLevel: String
    private var onSelect: (String) -> Void
    
    init(currentLevel: String, onSelect: @escaping (String) -> Void) {
        self.currentLevel = currentLevel
        self.onSelect = onSelect
        super.init(style: .grouped)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Recognition Level"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "LevelCell")
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return levels.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "LevelCell", for: indexPath)
        let level = levels[indexPath.row]
        cell.textLabel?.text = NSLocalizedString(level, comment: "")
        cell.accessoryType = (level == currentLevel) ? .checkmark : .none
        return cell
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        currentLevel = levels[indexPath.row]
        Settings.shared.recognitionLevel = currentLevel
        onSelect(currentLevel)
        tableView.reloadData()
        navigationController?.popViewController(animated: true)
    }
}
