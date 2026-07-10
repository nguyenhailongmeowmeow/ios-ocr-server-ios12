//
//  ResourceSnapshot.swift
//  OcrServer (iOS 12 Legacy)
//

import Foundation
import UIKit

struct ResourceSnapshot {
    let timestamp: Date
    let cpuTotal: Double        // 0.0 - 1.0
    let memoryUsed: UInt64
    let memoryFree: UInt64
    let memoryTotal: UInt64
    let thermalState: ProcessInfo.ThermalState
    let batteryLevel: Float?    // 0.0 - 1.0
    let batteryState: UIDevice.BatteryState
    let diskAvailable: Int64?
    let diskTotal: Int64?
    let networkStatus: String   // "Online", "Offline", etc.
    let appMemoryFootprint: UInt64
    let appThreadCount: Int
    let perCoreCPU: [Double]
}
