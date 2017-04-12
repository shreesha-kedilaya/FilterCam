//
//  GaleryCollectionViewModel.swift
//  FilterCam
//
//  Created by Shreesha on 31/08/16.
//  Copyright © 2016 YML. All rights reserved.
//

import Foundation
import Photos
import AVFoundation

class GaleryCollectionViewModel {

    var libraryAssets = [PHAsset]()

    let imageCachingManager = PHCachingImageManager()

    func fetchLibraryAssets(type: PHAssetMediaType, _ completion: @escaping () -> ()) {
        fetchAlllibraryAssets(type: type) {

            self.libraryAssets.sort(by: { (asset1, asset2) -> Bool in
                if let creationDate1 = asset1.creationDate, let creationDate2 = asset2.creationDate {
                    return creationDate1.timeIntervalSince1970 > creationDate2.timeIntervalSince1970
                } else {
                    return true
                }
            })

            let cacheoptions = PHImageRequestOptions()
            cacheoptions.isSynchronous = false
            cacheoptions.version = .original
            cacheoptions.resizeMode = .exact

            self.imageCachingManager.startCachingImages(for: self.libraryAssets, targetSize: CGSize(width:UIScreen.main.bounds.size.width * UIScreen.main.scale,height:UIScreen.main.bounds.size.height * UIScreen.main.scale), contentMode: .aspectFit, options: cacheoptions)

            completion()
        }
    }

    func fetchImageFor(asset: PHAsset, size: CGSize, completion: @escaping (UIImage?) -> Void) {
        let cacheoptions = PHImageRequestOptions()
        cacheoptions.isSynchronous = false
        cacheoptions.version = .original
        cacheoptions.resizeMode = .exact
        cacheoptions.isNetworkAccessAllowed = true
        cacheoptions.deliveryMode = .highQualityFormat
        self.imageCachingManager.requestImage(for: asset, targetSize: size, contentMode: .aspectFit, options: cacheoptions, resultHandler: { (image, _) in
            completion(image)
        })
    }

    fileprivate func fetchAlllibraryAssets(type: PHAssetMediaType, _ completion: @escaping ()->()){

        self.imageCachingManager.stopCachingImagesForAllAssets()
        libraryAssets = []

        let results = PHAsset.fetchAssets(with: type, options: nil)

        results.enumerateObjects ({ (object, index, _) in
            self.libraryAssets.append(object)
        })

        completion()
    }
}
