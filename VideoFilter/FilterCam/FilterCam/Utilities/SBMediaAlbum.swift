//
//  SBMediaAlbum.swift
//  SayBubble
//
//  Created by Ganesh on 29/08/16.
//  Copyright © 2016 Y MEDIA LABS. All rights reserved.
//

import Foundation
import Photos

class SBMediaAlbum {
    
    static let albumName = "SayBubble"
    static let sharedInstance = SBMediaAlbum()
    
    var assetCollection: PHAssetCollection!
    var photosAsset: PHFetchResult!
    
    init() {
        
        func fetchAssetCollectionForAlbum() -> PHAssetCollection! {
            
            let fetchOptions = PHFetchOptions()
            fetchOptions.predicate = NSPredicate(format: "title = %@", SBMediaAlbum.albumName)
            let collection = PHAssetCollection.fetchAssetCollectionsWithType(.Album, subtype: .Any, options: fetchOptions)
            
            if let firstObject: AnyObject = collection.firstObject {
                return firstObject as! PHAssetCollection
            }
            
            return nil
        }
        
        if let assetCollection = fetchAssetCollectionForAlbum() {
            self.assetCollection = assetCollection
            return
        }
        
        PHPhotoLibrary.sharedPhotoLibrary().performChanges({
            PHAssetCollectionChangeRequest.creationRequestForAssetCollectionWithTitle(SBMediaAlbum.albumName)
        }) { success, _ in
            if success {
                self.assetCollection = fetchAssetCollectionForAlbum()
            }
        }
    }
    
    func saveVideo(videoURL: NSURL,completion: (saved: Bool) -> ()) {
        
        //save the video to Photos
        PHPhotoLibrary.sharedPhotoLibrary().performChanges({
            if let assetRequest = PHAssetChangeRequest.creationRequestForAssetFromVideoAtFileURL(videoURL)
            {
                if let assetPlaceholder = assetRequest.placeholderForCreatedAsset
                {
                    if self.assetCollection != nil
                    {
                        self.photosAsset = PHAsset.fetchAssetsInAssetCollection(self.assetCollection, options: nil)
                        if let albumChangeRequest = PHAssetCollectionChangeRequest(forAssetCollection: self.assetCollection, assets: self.photosAsset)
                        {
                            albumChangeRequest.addAssets([assetPlaceholder])
                            
                        }
                    }
                }
            }
            
            }, completionHandler: { success, error in
                completion(saved: success)
        })
    }
    
    func saveMedia(urls: [(type:SBAssetMediaType, url: NSURL)],completion: ((saved: Bool) -> ())?) {
        
        //save the video to Photos
        PHPhotoLibrary.sharedPhotoLibrary().performChanges({
            
            for url in urls {
                
                let data = NSData(contentsOfURL: url.url)
                let fileName = (url.url.absoluteString! as NSString).lastPathComponent
                let fileURL = NSURL(fileURLWithPath: NSTemporaryDirectory()).URLByAppendingPathComponent(fileName)
                data?.writeToURL(fileURL!, atomically: true)
                
                var assetRequest: PHAssetChangeRequest?
                switch url.type {
                case .PhotoURL:
                    assetRequest = PHAssetChangeRequest.creationRequestForAssetFromImageAtFileURL(fileURL!)
                case .VideoURL:
                    assetRequest = PHAssetChangeRequest.creationRequestForAssetFromVideoAtFileURL(fileURL!)
                default: ()
                }
                
                if let assetRequest = assetRequest {
                    if let assetPlaceholder = assetRequest.placeholderForCreatedAsset {
                        if self.assetCollection != nil
                        {
                            self.photosAsset = PHAsset.fetchAssetsInAssetCollection(self.assetCollection, options: nil)
                            if let albumChangeRequest = PHAssetCollectionChangeRequest(forAssetCollection: self.assetCollection, assets: self.photosAsset) {
                                albumChangeRequest.addAssets([assetPlaceholder])
                            }
                        }
                    }
                }
            }
            
            }, completionHandler: { success, error in
                guard let completion = completion else { return }
                completion(saved: success)
        })
    }
    
    func saveImage(image: UIImage, completion: (saved: Bool) -> ()) {
        
        PHPhotoLibrary.sharedPhotoLibrary().performChanges({
            let assetRequest:PHAssetChangeRequest? = PHAssetChangeRequest.creationRequestForAssetFromImage(image)
            if let assetPlaceholder = assetRequest?.placeholderForCreatedAsset
            {
                if self.assetCollection != nil
                {
                    self.photosAsset = PHAsset.fetchAssetsInAssetCollection(self.assetCollection, options: nil)
                    if let albumChangeRequest = PHAssetCollectionChangeRequest(forAssetCollection: self.assetCollection, assets: self.photosAsset)
                    {
                        albumChangeRequest.addAssets([assetPlaceholder])
                    }
                }
                
            }
            
            }, completionHandler: { success, error in
                completion(saved: success)
        })
    }
    
    func fetchLastImageFromPhotoLibrary(completion: (image: UIImage?) -> ())
    {
        let imageManager = PHCachingImageManager.defaultManager()
        
        // Note that if the request is not set to synchronous
        // the requestImageForAsset will return both the image
        // and thumbnail; by setting synchronous to true it
        // will return just the thumbnail
        let options = PHImageRequestOptions()
        options.synchronous = true
        options.networkAccessAllowed = true
        options.deliveryMode = .FastFormat
        
        
        // Sort the images by creation date
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key:"creationDate", ascending: false)]
        
        if let fetchResult: PHFetchResult = PHAsset.fetchAssetsWithMediaType(PHAssetMediaType.Image, options: fetchOptions) {
            
            // If the fetch result isn't empty,
            // proceed with the image request
            if fetchResult.count > 0 {
                // Perform the image request
                if let asset = fetchResult.firstObject as? PHAsset
                {
                    imageManager.requestImageForAsset(asset, targetSize: PHImageManagerMaximumSize, contentMode: .AspectFill, options: options) { (image, info) in
                        completion(image: image)
                    }
                }
                else
                {
                    completion(image: nil)
                }
            }
            else
            {
                completion(image: nil)
            }
        }
        else
        {
            completion(image: nil)
        }
    }
    
    func fetchLastAssetFromPhotoLibrary(completion: (asset: PHAsset?) -> ())
    {
        
        // Note that if the request is not set to synchronous
        // the requestImageForAsset will return both the image
        // and thumbnail; by setting synchronous to true it
        // will return just the thumbnail
        let options = PHImageRequestOptions()
        options.synchronous = true
        options.networkAccessAllowed = true
        options.deliveryMode = .FastFormat
        
        
        // Sort the images by creation date
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key:"creationDate", ascending: false)]
        
        if let fetchResult: PHFetchResult = PHAsset.fetchAssetsWithMediaType(PHAssetMediaType.Image, options: fetchOptions) {
            
            // If the fetch result isn't empty,
            // proceed with the image request
            if fetchResult.count > 0 {
                // Perform the image request
                if let asset = fetchResult.firstObject as? PHAsset
                {
                    completion(asset: asset)
                }
                else
                {
                    completion(asset: nil)
                }
            }
            else
            {
                completion(asset: nil)
            }
        }
        else
        {
            completion(asset: nil)
        }
    }
}
