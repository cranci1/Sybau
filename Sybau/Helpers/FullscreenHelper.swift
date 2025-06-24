//
//  FullscreenHelper.swift
//  Sybau
//
//  Created by Francesco on 24/06/25.
//

import SwiftUI
import UIKit

extension UIApplication {
    static func setOrientation(_ orientation: UIInterfaceOrientation, isPortrait: Bool) {
        if #available(iOS 16.0, *) {
            if let window = UIApplication.shared.windows.first {
                let value = orientation.rawValue
                UIDevice.current.setValue(value, forKey: "orientation")
                window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
        } else {
            let value = orientation.rawValue
            UIDevice.current.setValue(value, forKey: "orientation")
            UIViewController.attemptRotationToDeviceOrientation()
        }
    }
}

extension View {
    func onRotate(perform action: @escaping (UIDeviceOrientation) -> Void) -> some View {
        self.onAppear()
            .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
                action(UIDevice.current.orientation)
            }
    }
    
    func supportedOrientations(_ supportedOrientations: UIInterfaceOrientationMask) -> some View {
        return self
    }
}

class OrientationLock {
    static func lock(to orientation: UIInterfaceOrientationMask) {
        if let delegate = UIApplication.shared.delegate as? AppDelegate {
            delegate.orientationLock = orientation
        }
    }
    
    static var current: UIInterfaceOrientationMask {
        if let delegate = UIApplication.shared.delegate as? AppDelegate {
            return delegate.orientationLock
        }
        return .all
    }
}
