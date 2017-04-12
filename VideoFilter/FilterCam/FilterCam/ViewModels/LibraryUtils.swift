//
//  VideoPreviewViewModel.swift
//  FilterCam
//
//  Created by Shreesha on 24/02/17.
//  Copyright © 2017 YML. All rights reserved.
//

import Foundation
import Photos

class LibraryUtils {

    static let shared = LibraryUtils()

    let imageCachingManager = PHCachingImageManager()
    var assetCollection: PHAssetCollection!
    private let albumName = "FilterCam"

    init() {
        func fetchAssetCollectionForAlbum() -> PHAssetCollection! {

            let fetchOptions = PHFetchOptions()
            fetchOptions.predicate = NSPredicate(format: "title = %@", albumName)
            let collection = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: fetchOptions)

            if let firstObject: AnyObject = collection.firstObject {
                return firstObject as! PHAssetCollection
            }

            return nil
        }

        if let assetCollection = fetchAssetCollectionForAlbum() {
            self.assetCollection = assetCollection
            return
        }

        PHPhotoLibrary.shared().performChanges({
            PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: self.albumName)
        }) { success, _ in
            if success {
                self.assetCollection = fetchAssetCollectionForAlbum()
            }
        }
    }

    func saveVideo(videoURL: URL,completion: @escaping (_ saved: Bool) -> ()) {

        //save the video to Photos
        PHPhotoLibrary.shared().performChanges({
            if let assetRequest = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: videoURL)
            {
                if let assetPlaceholder = assetRequest.placeholderForCreatedAsset
                {
                    if self.assetCollection != nil
                    {
                        let photosAsset = PHAsset.fetchAssets(in: self.assetCollection, options: nil)
                        if let albumChangeRequest = PHAssetCollectionChangeRequest(for: self.assetCollection, assets: photosAsset)
                        {
                            albumChangeRequest.addAssets([assetPlaceholder] as NSArray)
                        }
                    }
                }
            }

        }, completionHandler: { success, error in
            completion(success)
        })
    }

    func saveVideoToLibrary(_ videoURL: URL, completion: @escaping (_ succeeded: Bool, _ error: NSError?) -> ()) {
        PHPhotoLibrary.requestAuthorization { status in
            // Return if unauthorized
            guard status == .authorized else {
                let error = NSError(domain: "Error saving video: unauthorized access", code: 0, userInfo: nil)
                completion(false, error)
                return
            }

            // If here, save video to library
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: videoURL)
            }) { success, error in
                completion(success, error as NSError?)
            }
        }
    }

    func saveImage(image: UIImage, completion: @escaping (_ saved: Bool) -> ()) {

        PHPhotoLibrary.shared().performChanges({
            let assetRequest:PHAssetChangeRequest? = PHAssetChangeRequest.creationRequestForAsset(from: image)
            if let assetPlaceholder = assetRequest?.placeholderForCreatedAsset {
                if self.assetCollection != nil {
                    let assets = PHAsset.fetchAssets(in: self.assetCollection, options: nil)
                    if let albumChangeRequest = PHAssetCollectionChangeRequest(for: self.assetCollection, assets: assets) {
                        albumChangeRequest.addAssets([assetPlaceholder] as NSArray)
                    }
                }
            }

        }, completionHandler: { success, error in
            completion(success)
        })
    }

    class func discardFileAt(url: URL) -> Bool {
        let fileManager = FileManager.default
        do {
            try fileManager.removeItem(at: url)
            return true
        }catch _ {
            print("could not delete the video.")
            return true
        }
    }


    class func getThumbnailImageFor(_ URL: Foundation.URL) -> UIImage {

        let asset = AVURLAsset(url: URL, options: nil)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = UIScreen.main.bounds.size

        do {
            let cgImage = try imageGenerator.copyCGImage(at: CMTimeMakeWithSeconds(2, 1), actualTime: nil)
            var thumbnailImage = UIImage(cgImage: cgImage)
            thumbnailImage = thumbnailImage.withRenderingMode(.alwaysOriginal)
            return thumbnailImage
        } catch _ {
            return UIImage()
        }
    }

    class func getURLofMedia(_ mPhasset: PHAsset, completionHandler : @escaping ((_ responseURL : URL?) -> Void)){

        if mPhasset.mediaType == .image {
            let options: PHContentEditingInputRequestOptions = PHContentEditingInputRequestOptions()

            options.canHandleAdjustmentData = {(adjustmeta: PHAdjustmentData) -> Bool in
                return true
            }
            mPhasset.requestContentEditingInput(with: options, completionHandler: {(contentEditingInput: PHContentEditingInput?, info: [AnyHashable: Any]) -> Void in
                completionHandler(contentEditingInput!.fullSizeImageURL)
            })
        } else if mPhasset.mediaType == .video {
            let options: PHVideoRequestOptions = PHVideoRequestOptions()
            options.version = .current
            options.deliveryMode = .fastFormat
            PHImageManager.default().requestAVAsset(forVideo: mPhasset, options: options, resultHandler: {(asset: AVAsset?, audioMix: AVAudioMix?, info: [AnyHashable: Any]?) -> Void in

                if let urlAsset = asset as? AVURLAsset {
                    let localVideoUrl : URL = urlAsset.url
                    completionHandler(localVideoUrl)
                } else {
                    completionHandler(nil)
                }
            })
        }
    }

    func fetchLastFor(mediaType: PHAssetMediaType, completion: @escaping (_ image: UIImage?, AVAsset?) -> ()) {

        // Note that if the request is not set to synchronous
        // the requestImageForAsset will return both the image
        // and thumbnail; by setting synchronous to true it
        // will return just the thumbnail
        let options = PHImageRequestOptions()
        options.isSynchronous = true
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .fastFormat


        // Sort the images by creation date
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key:"creationDate", ascending: false)]

        let fetchResult: PHFetchResult = PHAsset.fetchAssets(with: mediaType, options: fetchOptions)

        // If the fetch result isn't empty,
        // proceed with the image request
        if fetchResult.count > 0 {
            // Perform the image request
            if let asset = fetchResult.firstObject {
                if mediaType == .video {

                    let videoOptions = PHVideoRequestOptions()
                    videoOptions.deliveryMode = .fastFormat
                    videoOptions.isNetworkAccessAllowed = true

                    imageCachingManager.requestAVAsset(forVideo: asset, options: videoOptions, resultHandler: { (asset, audioMix, _) in
                        completion(nil, asset)
                    })
                } else {
                    imageCachingManager.requestImage(for: asset, targetSize: PHImageManagerMaximumSize, contentMode: .aspectFit, options: options) { (image, info) in
                        completion(image, nil)
                    }
                }

            } else {
                completion(nil, nil)
            }
        } else {
            completion(nil, nil)
        }

    }

    class func angleOffsetFromPortraitTo(_ orientation: AVCaptureVideoOrientation) -> CGFloat {
        var angle: CGFloat = 0.0

        switch orientation {
        case .portrait:
            angle = 0.0
        case .portraitUpsideDown:
            angle = M_PI.g
        case .landscapeRight:
            angle = -M_PI_2.g
        case .landscapeLeft:
            angle = M_PI_2.g
        }

        return angle
    }
}
