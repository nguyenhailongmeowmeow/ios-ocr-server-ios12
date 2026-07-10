//
//  Utilities.swift
//  OcrServer (iOS 12 Legacy)
//

import Foundation
import UIKit

// MARK: - Byte Formatting

extension UInt64 {
    var bytesHumanReadable: String {
        let units: [String] = ["B","KB","MB","GB","TB"]
        var value = Double(self)
        var idx = 0
        while value >= 1024 && idx < units.count - 1 { value /= 1024; idx += 1 }
        let fmt = value >= 10 ? String(format: "%.0f", value) : String(format: "%.1f", value)
        return "\(fmt) \(units[idx])"
    }
}

// MARK: - Percentage Formatting

extension Double {
    var percentString: String { String(format: "%.1f%%", self * 100) }
}

// MARK: - Bundle Version

extension Bundle {
    var appVersion: String {
        return infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }
    var buildNumber: String {
        return infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    }
    var fullVersion: String {
        return "\(appVersion) (\(buildNumber))"
    }
}

// MARK: - UIColor Hex Init

extension UIColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            red: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: CGFloat(a) / 255
        )
    }
}

// MARK: - Helper to create SF Symbol or fallback text button

func createIconButton(systemName: String, fallbackText: String, target: Any?, action: Selector) -> UIButton {
    let button = UIButton(type: .system)
    if #available(iOS 13.0, *) {
        let config = UIImage.SymbolConfiguration(pointSize: 22, weight: .regular)
        button.setImage(UIImage(systemName: systemName, withConfiguration: config), for: .normal)
    } else {
        button.setTitle(fallbackText, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 18)
    }
    button.tintColor = .white
    button.addTarget(target, action: action, for: .touchUpInside)
    return button
}
