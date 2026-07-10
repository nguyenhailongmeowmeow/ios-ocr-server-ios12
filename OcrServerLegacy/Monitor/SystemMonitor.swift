//
//  SystemMonitor.swift
//  OcrServer (iOS 12 Legacy)
//
//  Uses SCNetworkReachability instead of NWPathMonitor for iOS 12 compatibility.
//

import Foundation
import UIKit
import SystemConfiguration

final class SystemMonitor {
    
    // CPU state for delta calculation
    private var lastCPUTicks: host_cpu_load_info = host_cpu_load_info(cpu_ticks: (0,0,0,0))
    private var lastPerCoreTicks: [(UInt32, UInt32, UInt32, UInt32)] = []
    
    // Battery
    private(set) var currentBatteryLevel: Float?
    private(set) var currentBatteryState: UIDevice.BatteryState = .unknown
    
    init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = UIDevice.current.batteryLevel
        currentBatteryLevel = level >= 0 ? level : nil
        currentBatteryState = UIDevice.current.batteryState
        
        NotificationCenter.default.addObserver(
            self, selector: #selector(batteryLevelDidChange),
            name: UIDevice.batteryLevelDidChangeNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(batteryStateDidChange),
            name: UIDevice.batteryStateDidChangeNotification, object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    func readSnapshot(appInfo: AppMonitor.AppInfo) -> ResourceSnapshot {
        let cpu = readCPUTotalUsage()
        let perCore = readPerCoreUsage()
        let mem = readMemory()
        let thermal = ProcessInfo.processInfo.thermalState
        let (avail, total) = readDisk()
        let net = readNetworkStatus()
        
        return ResourceSnapshot(
            timestamp: Date(),
            cpuTotal: cpu,
            memoryUsed: mem.used,
            memoryFree: mem.free,
            memoryTotal: mem.total,
            thermalState: thermal,
            batteryLevel: currentBatteryLevel,
            batteryState: currentBatteryState,
            diskAvailable: avail,
            diskTotal: total,
            networkStatus: net,
            appMemoryFootprint: appInfo.footprint,
            appThreadCount: appInfo.threadCount,
            perCoreCPU: perCore
        )
    }
    
    // MARK: - Network Status (SCNetworkReachability)
    
    func readNetworkStatus() -> String {
        var zeroAddress = sockaddr_in()
        zeroAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        zeroAddress.sin_family = sa_family_t(AF_INET)
        
        guard let reachability = withUnsafePointer(to: &zeroAddress, { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                SCNetworkReachabilityCreateWithAddress(nil, sockaddrPtr)
            }
        }) else {
            return "Unknown"
        }
        
        var flags = SCNetworkReachabilityFlags()
        guard SCNetworkReachabilityGetFlags(reachability, &flags) else {
            return "Unknown"
        }
        
        let isReachable = flags.contains(.reachable)
        let needsConnection = flags.contains(.connectionRequired)
        
        if isReachable && !needsConnection {
            if flags.contains(.isWWAN) {
                return "Cellular"
            }
            return "Online"
        }
        return "Offline"
    }
    
    // MARK: - CPU
    
    struct MemoryInfo {
        let used: UInt64
        let free: UInt64
        let total: UInt64
    }
    
    func readCPUTotalUsage() -> Double {
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        var info = host_cpu_load_info()
        let result = withUnsafeMutablePointer(to: &info) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, intPtr, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        
        let user = Double(info.cpu_ticks.0 - lastCPUTicks.cpu_ticks.0)
        let sys  = Double(info.cpu_ticks.1 - lastCPUTicks.cpu_ticks.1)
        let idle = Double(info.cpu_ticks.2 - lastCPUTicks.cpu_ticks.2)
        let nice = Double(info.cpu_ticks.3 - lastCPUTicks.cpu_ticks.3)
        let totalTicks = user + sys + idle + nice
        
        lastCPUTicks = info
        
        guard totalTicks > 0 else { return 0 }
        let busy = user + sys + nice
        return max(0, min(1, busy / totalTicks))
    }
    
    func readPerCoreUsage() -> [Double] {
        var cpuInfo: processor_info_array_t? = nil
        var cpuInfoCount: mach_msg_type_number_t = 0
        var processorCount: natural_t = 0
        
        let kr = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO,
                                     &processorCount, &cpuInfo, &cpuInfoCount)
        guard kr == KERN_SUCCESS, let info = cpuInfo else { return [] }
        defer {
            let size = vm_size_t(cpuInfoCount) * vm_size_t(MemoryLayout<integer_t>.size)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), size)
        }
        
        let stride = Int(CPU_STATE_MAX)
        var usages: [Double] = []
        var newCache: [(UInt32, UInt32, UInt32, UInt32)] = []
        
        for i in 0..<Int(processorCount) {
            let base = i * stride
            let user = UInt32(info[base + Int(CPU_STATE_USER)])
            let sys  = UInt32(info[base + Int(CPU_STATE_SYSTEM)])
            let idle = UInt32(info[base + Int(CPU_STATE_IDLE)])
            let nice = UInt32(info[base + Int(CPU_STATE_NICE)])
            let curr = (user, sys, idle, nice)
            
            let prev = i < lastPerCoreTicks.count ? lastPerCoreTicks[i] : curr
            
            let dUser = Double(curr.0 &- prev.0)
            let dSys  = Double(curr.1 &- prev.1)
            let dIdle = Double(curr.2 &- prev.2)
            let dNice = Double(curr.3 &- prev.3)
            let total = dUser + dSys + dIdle + dNice
            let busy = max(0.0, dUser + dSys + dNice)
            
            usages.append(total > 0 ? min(1.0, busy / total) : 0.0)
            newCache.append(curr)
        }
        
        lastPerCoreTicks = newCache
        return usages
    }
    
    // MARK: - Memory
    
    func readMemory() -> MemoryInfo {
        var size = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        var vmStats = vm_statistics64()
        let result = withUnsafeMutablePointer(to: &vmStats) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(size)) { intPtr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, intPtr, &size)
            }
        }
        guard result == KERN_SUCCESS else {
            let total = ProcessInfo.processInfo.physicalMemory
            return MemoryInfo(used: 0, free: total, total: total)
        }
        
        let pageSize = UInt64(vm_kernel_page_size)
        let total = ProcessInfo.processInfo.physicalMemory
        let free = UInt64(vmStats.free_count) * pageSize
        let inactive = UInt64(vmStats.inactive_count) * pageSize
        
        let available = min(free + inactive, total)
        let used = total - available
        
        return MemoryInfo(used: used, free: available, total: total)
    }
    
    // MARK: - Disk
    
    func readDisk() -> (Int64?, Int64?) {
        do {
            let url = URL(fileURLWithPath: NSHomeDirectory())
            let resourceKeys: Set<URLResourceKey> = [
                .volumeAvailableCapacityForImportantUsageKey,
                .volumeTotalCapacityKey
            ]
            let values = try url.resourceValues(forKeys: resourceKeys)
            let available = values.volumeAvailableCapacityForImportantUsage
            let total = values.volumeTotalCapacity.map { Int64($0) }
            return (available, total)
        } catch {
            return (nil, nil)
        }
    }
    
    // MARK: - Battery
    
    @objc private func batteryLevelDidChange() {
        let level = UIDevice.current.batteryLevel
        currentBatteryLevel = level >= 0 ? level : nil
    }
    
    @objc private func batteryStateDidChange() {
        currentBatteryState = UIDevice.current.batteryState
    }
}
