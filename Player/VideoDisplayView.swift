//
//  VideoDisplayView.swift
//  Sybau
//

import UIKit
import AVFoundation

final class VideoDisplayView: UIView {
    override class var layerClass: AnyClass { AVSampleBufferDisplayLayer.self }
    
    var displayLayer: AVSampleBufferDisplayLayer {
        layer as! AVSampleBufferDisplayLayer
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
        displayLayer.videoGravity = .resizeAspect
        displayLayer.backgroundColor = UIColor.black.cgColor
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        displayLayer.frame = bounds
        CATransaction.commit()
        
        if bounds.size != lastSize, bounds.width > 0, bounds.height > 0 {
            lastSize = bounds.size
            onViewSizeChanged?(bounds.size)
        }
    }
}
