//
//  MonitorViewController.swift
//  OcrServer (iOS 12 Legacy)
//
//  System monitor dashboard using UITableView + Timer.
//

import UIKit

class MonitorViewController: UITableViewController {
    
    private let systemMonitor = SystemMonitor()
    private let appMonitor = AppMonitor()
    private var timer: Timer?
    private var isMonitoring = true
    private var snapshot: ResourceSnapshot?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = NSLocalizedString("Monitor", comment: "")
        
        // Navigation buttons
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "✕", style: .plain, target: self, action: #selector(dismissSelf)
        )
        
        let resetBtn = UIBarButtonItem(title: "↻", style: .plain, target: self, action: #selector(resetData))
        let pauseBtn = UIBarButtonItem(title: isMonitoring ? "⏸" : "▶", style: .plain, target: self, action: #selector(toggleMonitoring))
        navigationItem.leftBarButtonItems = [resetBtn, pauseBtn]
        
        tableView = UITableView(frame: .zero, style: .grouped)
        tableView.register(MonitorCell.self, forCellReuseIdentifier: "MonitorCell")
        tableView.register(ProgressMonitorCell.self, forCellReuseIdentifier: "ProgressCell")
        
        startMonitoring()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopMonitoring()
    }
    
    // MARK: - Timer
    
    private func startMonitoring() {
        isMonitoring = true
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        tick() // initial sample
    }
    
    private func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        isMonitoring = false
    }
    
    private func tick() {
        let appInfo = appMonitor.read()
        snapshot = systemMonitor.readSnapshot(appInfo: appInfo)
        tableView.reloadData()
    }
    
    // MARK: - Actions
    
    @objc private func dismissSelf() {
        dismiss(animated: true)
    }
    
    @objc private func resetData() {
        snapshot = nil
        tableView.reloadData()
    }
    
    @objc private func toggleMonitoring() {
        if isMonitoring {
            stopMonitoring()
        } else {
            startMonitoring()
        }
        let pauseBtn = UIBarButtonItem(title: isMonitoring ? "⏸" : "▶", style: .plain, target: self, action: #selector(toggleMonitoring))
        let resetBtn = navigationItem.leftBarButtonItems?.first ?? UIBarButtonItem()
        navigationItem.leftBarButtonItems = [resetBtn, pauseBtn]
    }
    
    // MARK: - TableView DataSource
    
    // Sections: CPU, Memory, Thermal, Battery, Disk & Network, App
    override func numberOfSections(in tableView: UITableView) -> Int { return 6 }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0: return "CPU"
        case 1: return "Memory"
        case 2: return "Thermal"
        case 3: return "Battery"
        case 4: return "Disk & Network"
        case 5: return "This App"
        default: return nil
        }
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return 1  // CPU total
        case 1: return 1  // Memory
        case 2: return 1  // Thermal
        case 3: return 2  // Battery level + state
        case 4: return 3  // Disk avail, Disk total, Network
        case 5: return 2  // Memory footprint, Threads
        default: return 0
        }
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let snap = snapshot else {
            let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
            cell.textLabel?.text = "--"
            cell.selectionStyle = .none
            return cell
        }
        
        switch (indexPath.section, indexPath.row) {
        case (0, 0):
            // CPU with progress bar
            let cell = tableView.dequeueReusableCell(withIdentifier: "ProgressCell", for: indexPath) as! ProgressMonitorCell
            cell.configure(
                title: "CPU Usage",
                value: snap.cpuTotal.percentString,
                progress: Float(snap.cpuTotal),
                color: snap.cpuTotal < 0.5 ? .green : (snap.cpuTotal < 0.8 ? .yellow : .red)
            )
            return cell
            
        case (1, 0):
            // Memory with progress bar
            let cell = tableView.dequeueReusableCell(withIdentifier: "ProgressCell", for: indexPath) as! ProgressMonitorCell
            let usedStr = snap.memoryUsed.bytesHumanReadable
            let totalStr = snap.memoryTotal.bytesHumanReadable
            let ratio = snap.memoryTotal > 0 ? Float(snap.memoryUsed) / Float(snap.memoryTotal) : 0
            cell.configure(
                title: "Used: \(usedStr) / \(totalStr)",
                value: "Free: \(snap.memoryFree.bytesHumanReadable)",
                progress: ratio,
                color: ratio < 0.6 ? .green : (ratio < 0.85 ? .yellow : .red)
            )
            return cell
            
        case (2, 0):
            let cell = tableView.dequeueReusableCell(withIdentifier: "MonitorCell", for: indexPath) as! MonitorCell
            let (label, color) = thermalInfo(snap.thermalState)
            cell.configure(title: "State", value: label, valueColor: color)
            return cell
            
        case (3, 0):
            let cell = tableView.dequeueReusableCell(withIdentifier: "MonitorCell", for: indexPath) as! MonitorCell
            if let level = snap.batteryLevel {
                cell.configure(title: "Level", value: "\(Int(level * 100))%")
            } else {
                cell.configure(title: "Level", value: "--")
            }
            return cell
            
        case (3, 1):
            let cell = tableView.dequeueReusableCell(withIdentifier: "MonitorCell", for: indexPath) as! MonitorCell
            cell.configure(title: "State", value: batteryStateName(snap.batteryState))
            return cell
            
        case (4, 0):
            let cell = tableView.dequeueReusableCell(withIdentifier: "MonitorCell", for: indexPath) as! MonitorCell
            let avail = snap.diskAvailable.map { UInt64($0).bytesHumanReadable } ?? "--"
            cell.configure(title: "Disk Available", value: avail)
            return cell
            
        case (4, 1):
            let cell = tableView.dequeueReusableCell(withIdentifier: "MonitorCell", for: indexPath) as! MonitorCell
            let total = snap.diskTotal.map { UInt64($0).bytesHumanReadable } ?? "--"
            cell.configure(title: "Disk Total", value: total)
            return cell
            
        case (4, 2):
            let cell = tableView.dequeueReusableCell(withIdentifier: "MonitorCell", for: indexPath) as! MonitorCell
            cell.configure(title: "Network", value: snap.networkStatus)
            return cell
            
        case (5, 0):
            let cell = tableView.dequeueReusableCell(withIdentifier: "MonitorCell", for: indexPath) as! MonitorCell
            cell.configure(title: "Memory Footprint", value: snap.appMemoryFootprint.bytesHumanReadable)
            return cell
            
        case (5, 1):
            let cell = tableView.dequeueReusableCell(withIdentifier: "MonitorCell", for: indexPath) as! MonitorCell
            cell.configure(title: "Threads", value: "\(snap.appThreadCount)")
            return cell
            
        default:
            return UITableViewCell()
        }
    }
    
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        switch (indexPath.section, indexPath.row) {
        case (0, 0), (1, 0): return 70  // Progress cells are taller
        default: return 44
        }
    }
    
    // MARK: - Helpers
    
    private func thermalInfo(_ state: ProcessInfo.ThermalState) -> (String, UIColor) {
        switch state {
        case .nominal:  return (NSLocalizedString("Nominal", comment: ""), .green)
        case .fair:     return (NSLocalizedString("Fair", comment: ""), .yellow)
        case .serious:  return (NSLocalizedString("Serious", comment: ""), .orange)
        case .critical: return (NSLocalizedString("Critical", comment: ""), .red)
        @unknown default: return (NSLocalizedString("Unknown", comment: ""), .gray)
        }
    }
    
    private func batteryStateName(_ state: UIDevice.BatteryState) -> String {
        switch state {
        case .charging:  return NSLocalizedString("Charging", comment: "")
        case .full:      return NSLocalizedString("Full", comment: "")
        case .unplugged: return NSLocalizedString("Unplugged", comment: "")
        default:         return NSLocalizedString("Unknown", comment: "")
        }
    }
}

// MARK: - Custom Cells

class MonitorCell: UITableViewCell {
    
    private let titleLbl = UILabel()
    private let valueLbl = UILabel()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        
        titleLbl.font = UIFont.systemFont(ofSize: 15)
        titleLbl.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLbl)
        
        valueLbl.font = UIFont.systemFont(ofSize: 15, weight: .medium)
        valueLbl.textAlignment = .right
        valueLbl.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(valueLbl)
        
        NSLayoutConstraint.activate([
            titleLbl.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            titleLbl.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            valueLbl.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            valueLbl.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            valueLbl.leadingAnchor.constraint(greaterThanOrEqualTo: titleLbl.trailingAnchor, constant: 8)
        ])
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    func configure(title: String, value: String, valueColor: UIColor = .darkGray) {
        titleLbl.text = title
        valueLbl.text = value
        valueLbl.textColor = valueColor
    }
}

class ProgressMonitorCell: UITableViewCell {
    
    private let titleLbl = UILabel()
    private let valueLbl = UILabel()
    private let progressBar = UIProgressView(progressViewStyle: .default)
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        
        titleLbl.font = UIFont.systemFont(ofSize: 15)
        titleLbl.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLbl)
        
        valueLbl.font = UIFont.systemFont(ofSize: 20, weight: .bold)
        valueLbl.textAlignment = .right
        valueLbl.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(valueLbl)
        
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(progressBar)
        
        NSLayoutConstraint.activate([
            titleLbl.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            titleLbl.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            
            valueLbl.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            valueLbl.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            valueLbl.leadingAnchor.constraint(greaterThanOrEqualTo: titleLbl.trailingAnchor, constant: 8),
            
            progressBar.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
            progressBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            progressBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            progressBar.heightAnchor.constraint(equalToConstant: 6)
        ])
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    func configure(title: String, value: String, progress: Float, color: UIColor) {
        titleLbl.text = title
        valueLbl.text = value
        progressBar.progress = progress
        progressBar.progressTintColor = color
    }
}
