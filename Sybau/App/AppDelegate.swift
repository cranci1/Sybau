//
//  AppDelegate.swift
//  Sybau
//
//  Created by Francesco on 24/06/25.
//

import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
    var orientationLock: UIInterfaceOrientationMask = .all
    
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return orientationLock
    }
}
