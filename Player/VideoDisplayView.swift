//
//  VideoDisplayView.swift
//  Sybau
//

import UIKit
import Metal
import QuartzCore

final class VideoDisplayView: UIView {
    override class var layerClass: AnyClass { MetalLayer.self }

    var displayLayer: MetalLayer {
        layer as! MetalLayer
    }

    var onViewSizeChanged: ((CGSize) -> Void)?
    private var lastSize: CGSize = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        backgroundColor = .black
        isOpaque = true
        clipsToBounds = true

        displayLayer.device = MTLCreateSystemDefaultDevice()
        displayLayer.pixelFormat = .bgra8Unorm
        displayLayer.framebufferOnly = true
        displayLayer.contentsScale = UIScreen.main.nativeScale
        displayLayer.backgroundColor = UIColor.black.cgColor
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        displayLayer.frame = bounds
        displayLayer.contentsScale = window?.screen.nativeScale ?? UIScreen.main.nativeScale
        CATransaction.commit()

        if bounds.size != lastSize, bounds.width > 0, bounds.height > 0 {
            lastSize = bounds.size
            onViewSizeChanged?(bounds.size)
        }
    }
}

final class MetalLayer: CAMetalLayer {
    override var drawableSize: CGSize {
        get { super.drawableSize }
        set {
            if newValue.width > 1 && newValue.height > 1 {
                super.drawableSize = newValue
            }
        }
    }

}
