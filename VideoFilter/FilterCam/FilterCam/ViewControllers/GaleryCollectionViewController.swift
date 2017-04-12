//
//  GaleryCollectionViewController.swift
//  FilterCam
//
//  Created by Shreesha on 31/08/16.
//  Copyright © 2016 YML. All rights reserved.
//

import UIKit
import AVFoundation
import Photos

private let reuseIdentifier = "GaleryCollectionViewCell"

class GaleryCollectionViewController: UIViewController, UICollectionViewDelegateFlowLayout, UICollectionViewDataSource {

    @IBOutlet weak var videoCollectionView: UICollectionView!
    fileprivate lazy var viewModel = GaleryCollectionViewModel()

    fileprivate var permissionService: PermissionService?

    var mediaType: PHAssetMediaType = .video

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Gallery"
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        permissionService = PermissionType.Photos.permissionService
        permissionService?.requestPermission({ (status) in
            switch status {
            case .Authorized:
                
                self.viewModel.fetchLibraryAssets(type: self.mediaType) {
                    Async.main {
                        self.videoCollectionView.reloadData()
                    }
                }
            default:()
            }
        })
    }

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return viewModel.libraryAssets.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: reuseIdentifier, for: indexPath) as! GaleryCollectionViewCell
        if mediaType == .video {
            cell.playButton.isHidden = false
        } else {
            cell.playButton.isHidden = true
        }

        return cell
    }

    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        let currentCell = cell as! GaleryCollectionViewCell
        if mediaType == .image {
            viewModel.fetchImageFor(asset: viewModel.libraryAssets[indexPath.item], size: CGSize(width: 150, height: 150) , completion: { (image) in
                if let currentImage = image {
                    currentCell.videoImageView.image = currentImage
                }
            })
        } else {
            currentCell.videoAsset = viewModel.libraryAssets[(indexPath as NSIndexPath).item]
        }
    }

    // MARK: UICollectionViewDelegate

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        return CGSize(width: 150, height: 150)
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        return 25
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        switch mediaType {
        case .video:
            let previewVC = storyboard?.instantiateViewController(withIdentifier: "VideoPreviewViewController") as! VideoPreviewViewController
            previewVC.playingPhAsset = viewModel.libraryAssets[(indexPath as NSIndexPath).item]
            navigationController?.pushViewController(previewVC, animated: true)
        case .image:
            let previewVC = storyboard?.instantiateViewController(withIdentifier: "ImagePreviewViewController") as! ImagePreviewViewController
            viewModel.fetchImageFor(asset: viewModel.libraryAssets[indexPath.item], size: CGSize(width: UIScreen.main.bounds.width * UIScreen.main.scale, height: UIScreen.main.bounds.height * UIScreen.main.scale), completion: { (image) in
                previewVC.image = image
                self.navigationController?.pushViewController(previewVC, animated: true)
            })
        default: break
        }

    }
}
