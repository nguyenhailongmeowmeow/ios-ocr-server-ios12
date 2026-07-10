//
//  AppDelegate.swift
//  OcrServer (iOS 12 Legacy)
//
//  UIKit-based AppDelegate for iOS 12+
//

import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        
        // Prevent screen from sleeping
        UIApplication.shared.isIdleTimerDisabled = true
        
        // Configure navigation bar appearance
        let navBarAppearance = UINavigationBar.appearance()
        navBarAppearance.barTintColor = UIColor(hex: "1C1C1E")
        navBarAppearance.tintColor = .white
        navBarAppearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        navBarAppearance.isTranslucent = false
        
        // Set status bar style
        UIApplication.shared.statusBarStyle = .lightContent
        
        // Set up window
        let window = UIWindow(frame: UIScreen.main.bounds)
        let mainVC = MainViewController()
        let navController = UINavigationController(rootViewController: mainVC)
        navController.navigationBar.barStyle = .black
        window.rootViewController = navController
        window.makeKeyAndVisible()
        self.window = window
        
        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {}
    func applicationDidEnterBackground(_ application: UIApplication) {}
    func applicationWillEnterForeground(_ application: UIApplication) {}
    func applicationDidBecomeActive(_ application: UIApplication) {}
    func applicationWillTerminate(_ application: UIApplication) {
        ServerManager.shared.stopServer()
    }
}
