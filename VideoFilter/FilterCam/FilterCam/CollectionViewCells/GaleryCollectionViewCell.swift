//
//  GaleryCollectionViewCell.swift
//  FilterCam
//
//  Created by Shreesha on 31/08/16.
//  Copyright © 2016 YML. All rights reserved.
//

import UIKit
import AVFoundation
import Photos

class GaleryCollectionViewCell: UICollectionViewCell {
    
    @IBOutlet weak var videoImageView: UIImageView!
    @IBOutlet weak var playButton: UIButton!

    var videoAsset: PHAsset? {
        didSet {
            applyThumbnailImage()
        }
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        playButton.isUserInteractionEnabled = false
        videoImageView.image = UIImage(named: "placeHolderVideo")
    }

    func applyThumbnailImage() {
        videoImageView.image = UIImage(named: "placeHolderVideo")
        if let videoAsset = videoAsset {
            Async.global(DispatchQoS.QoSClass.background) {
                LibraryUtils.getURLofMedia(videoAsset) { (url) in
                    if let videoURL = url {

                        let image = LibraryUtils.getThumbnailImageFor(videoURL)
                        Async.main{
                            self.videoImageView.image = image
                        }
                    }
                }
            }
        }
    }
}
