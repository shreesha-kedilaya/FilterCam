//
//  VideoPreviewViewController.swift
//  FilterCam
//
//  Created by Shreesha on 31/08/16.
//  Copyright © 2016 YML. All rights reserved.
//

import UIKit
import AVFoundation
import Photos

enum VideoPreviewType {
    case videoPreview
    case galleryVideoPreview
}

class VideoPreviewViewController: UIViewController {

    @IBOutlet weak var frameCollectionView: UIView!
    @IBOutlet weak var videoPreviewView: UIView!
    @IBOutlet weak var playButton: UIButton!
    @IBOutlet weak var videoButton: UIImageView!

    @IBOutlet weak var progressView: UIProgressView!
    @IBOutlet weak var endLabel: UILabel!
    fileprivate var playingAsset: AVAsset?
    fileprivate var currentPlayerItem: AVPlayerItem?
    
    @IBOutlet weak var filterButton: UIButton!
    @IBOutlet weak var startLabel: UILabel!
    fileprivate var playing = false
    fileprivate var totalDuration: Double = 0
    fileprivate var currentDuration: Double = 0
    fileprivate var fileNumber = 0

    fileprivate var periodicObserver: AnyObject?

    fileprivate lazy var videoPlayer = AVPlayer()
    fileprivate var videoPlayerLayer: AVPlayerLayer!

    fileprivate var filterManager: FilterPipeline?

    var playingPhAsset: PHAsset?
    var savedTempUrl: URL?
    var videoPreviewType = VideoPreviewType.videoPreview

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Video Preview"
        progressView.setProgress(0, animated: false)
        filterManager = FilterPipeline.shared()
        filterManager?.initializeWith(filterType: .onVideo)

        if let playingAsset = playingAsset {
            startLabel.text = String(format: "%0.0f", CMTimeGetSeconds(playingAsset.duration))
        } else if let playingPhAsset = playingPhAsset {
            startLabel.text = String(format: "%0.0f", playingPhAsset.duration)
        }

        view.layoutIfNeeded()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        view.layoutIfNeeded()
        addPlayerItemToPlayer(asset: nil)
    }

    @IBAction func discardButtonDidClick(_ sender: AnyObject) {

        let fileManager = FileManager.default
        do {
            if let savedTempUrl = savedTempUrl {
                try fileManager.removeItem(at: savedTempUrl)
            }
        } catch _{
            print("could not delete the video.")
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        removeObservers()
    }

    @IBAction func filterAction(_ sender: AnyObject) {
        let filterViewController = storyboard?.instantiateViewController(withIdentifier: "FilterViewController") as! FilterViewController

        if let playingAsset = playingAsset {

            let imageGenerator = AVAssetImageGenerator(asset: playingAsset)
            imageGenerator.appliesPreferredTrackTransform = true
            imageGenerator.maximumSize = UIScreen.main.bounds.size

            do {
                let cgImage = try imageGenerator.copyCGImage(at: CMTimeMakeWithSeconds(2, 1), actualTime: nil)
                var thumbnailImage = UIImage(cgImage: cgImage)
                thumbnailImage = thumbnailImage.withRenderingMode(.alwaysOriginal)
                filterViewController.image = thumbnailImage
            } catch _ {
                filterViewController.image = UIImage()
            }
        }

        filterViewController.delegate = self
        navigationController?.present(filterViewController, animated: true, completion: nil)
    }

    @IBAction func saveButtonDidClick(_ sender: AnyObject) {
        saveVideoToLibrary()
    }

    func saveVideoToLibrary() {

        let paths = NSSearchPathForDirectoriesInDomains(FileManager.SearchPathDirectory.documentDirectory, FileManager.SearchPathDomainMask.userDomainMask, true)
        let documentDirectory = paths.first
        let dataPath = (documentDirectory)! + "FilterCam \(fileNumber).mov"

        fileNumber += 1

        guard let savedTempUrl = savedTempUrl else{
            return
        }
        guard let exporter = AVAssetExportSession(asset: AVURLAsset(url: savedTempUrl), presetName: AVAssetExportPresetHighestQuality) else {
            return
        }
        exporter.outputURL = URL(string: dataPath)
        exporter.outputFileType = AVFileTypeQuickTimeMovie
        exporter.shouldOptimizeForNetworkUse = true

        exporter.exportAsynchronously() {
            DispatchQueue.main.async { _ in
                let alertController = UIAlertController(title: "Saved", message: "Video successfully saved", preferredStyle: .alert)
                self.present(alertController, animated: true, completion: nil)
            }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        videoPlayerLayer.frame = view.bounds
    }

    fileprivate func addPlayerItemToPlayer(asset: AVAsset?) {

        videoPlayerLayer?.removeFromSuperlayer()
        videoPlayerLayer = nil
        videoPlayerLayer = AVPlayerLayer(player: videoPlayer)
        videoPlayerLayer.videoGravity = AVLayerVideoGravityResizeAspect
        videoPreviewView.layoutIfNeeded()
        videoPlayerLayer.frame = view.bounds
        videoPreviewView.layer.insertSublayer(videoPlayerLayer, at: 0)

        if let asset = asset {
            setupThePlayerItem(asset)
        } else if let playingPhAsset = playingPhAsset {
            PHCachingImageManager.default().requestAVAsset(forVideo: playingPhAsset, options: nil) { (asset, audio, doctionaryObject) in
                Async.main{
                    self.setupThePlayerItem(asset)
                }
            }
        } else if let savedTempUrl = savedTempUrl{
            let asset = AVURLAsset(url: savedTempUrl, options: nil)
            setupThePlayerItem(asset)
        }
    }

    fileprivate func setupThePlayerItem(_ asset: AVAsset?) {
        self.playingAsset = asset
        self.currentPlayerItem = AVPlayerItem(asset: self.playingAsset!)
        self.totalDuration = CMTimeGetSeconds(self.playingAsset!.duration)
        self.videoPlayer.replaceCurrentItem(with: self.currentPlayerItem!)
        let interval = CMTimeMakeWithSeconds(0.5, Int32(NSEC_PER_SEC))
        self.periodicObserver = self.videoPlayer.addPeriodicTimeObserver(forInterval: interval, queue: nil, using: { (time) in
            self.reloadTimeAndProgress(time)
        }) as AnyObject?

        addObservers()
    }

    func addObservers() {
        self.currentPlayerItem?.addObserver(self, forKeyPath: "status", options: [NSKeyValueObservingOptions.new, NSKeyValueObservingOptions.initial], context: nil)
        self.currentPlayerItem?.addObserver(self, forKeyPath: "rate", options: [NSKeyValueObservingOptions.new], context: nil)
        self.currentPlayerItem?.addObserver(self, forKeyPath: "playbackBufferEmpty", options: [NSKeyValueObservingOptions.new, NSKeyValueObservingOptions.initial], context: nil)
        self.currentPlayerItem?.addObserver(self, forKeyPath: "playbackLikelyToKeepUp", options: [NSKeyValueObservingOptions.new, NSKeyValueObservingOptions.initial], context: nil)
        self.videoPlayer.actionAtItemEnd = .pause
        NotificationCenter.default.addObserver(self, selector: #selector(VideoPreviewViewController.handlePlayerItemOperation(_:)), name: NSNotification.Name.AVPlayerItemDidPlayToEndTime, object: self.videoPlayer.currentItem)
    }

    func handlePlayerItemOperation(_ notification: Notification) {

        let object = notification.object as? AVPlayerItem
        self.playing = false
        object?.seek(to: kCMTimeZero, completionHandler: { (flag) in
            Async.main{
                self.videoPlayer.pause()
                self.videoButton.isHidden = false
            }
        })

        print("handlePlayerItemOperation")
    }

    func reloadTimeAndProgress(_ time: CMTime) {

        if playing {
            let timeInSeconds = CMTimeGetSeconds(time)
            let progress = 1 - (Double(totalDuration) - timeInSeconds) / totalDuration
            currentDuration = Double(timeInSeconds)
            progressView.setProgress(Float(progress), animated: true)
            let string = String(format: "%0.0f", Float(timeInSeconds))
            endLabel.text = "\(string)"
            print("progress \(progress)")
        }
    }

    func removeObservers() {
        if let periodicObserver = periodicObserver {
            videoPlayer.removeTimeObserver(periodicObserver)
        }
        currentPlayerItem?.removeObserver(self, forKeyPath: "status")
        currentPlayerItem?.removeObserver(self, forKeyPath: "rate")
        currentPlayerItem?.removeObserver(self, forKeyPath: "playbackBufferEmpty")
        currentPlayerItem?.removeObserver(self, forKeyPath: "playbackLikelyToKeepUp")
        NotificationCenter.default.removeObserver(self)
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        guard let keyPath = keyPath else{
            return
        }
        guard let currentPlayerItem = currentPlayerItem else {
            return
        }

        if currentPlayerItem.isPlaybackBufferEmpty {
            if currentPlayerItem.isPlaybackBufferEmpty {
                playing = false
                videoPlayer.pause()
            }
        }

        if currentPlayerItem.isPlaybackLikelyToKeepUp {

        }
        switch NSNotification.Name(keyPath) {
        case NSNotification.Name.AVPlayerItemDidPlayToEndTime:
            videoPlayer.pause()
            playing = false
        case NSNotification.Name.AVPlayerItemTimeJumped:()
        default: ()
        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
    
    @IBAction func playButtonTapped(_ sender: AnyObject) {

        if !playing && videoPlayer.status == .readyToPlay{
            videoPlayer.play()
            videoButton.isHidden = true
        } else {
            videoPlayer.pause()
            videoButton.isHidden = false
        }
        playing = !playing
    }

    fileprivate func reloadAllSubviews() {
        videoPreviewView.layoutIfNeeded()
        videoPlayerLayer.frame = videoPreviewView.frame
    }

    override func didRotate(from fromInterfaceOrientation: UIInterfaceOrientation) {
        self.reloadAllSubviews()
    }

    override func willRotate(to toInterfaceOrientation: UIInterfaceOrientation, duration: TimeInterval) {
        UIView.animate(withDuration: duration, animations: {
            self.reloadAllSubviews()
        })
    }
}


extension VideoPreviewViewController: FilterViewControllerDelegate {
    func filterViewController(viewController: FilterViewController, didSelectFilter filter: CIFilter?) {

        viewController.dismiss(animated: true) { 
            let filemanager = FileManager.default
            let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("FilterCam" + "\(Date().timeIntervalSince1970)" + ".mov")

            filemanager.urls(for: .applicationSupportDirectory, in: .userDomainMask)

            self.showSpinner()
            if let playingAsset = self.playingAsset {
                self.filterManager?.applyFilter(filter, toVideo: playingAsset, atUrl: url, completion: { path in
                    print("Completed the writing")
                    LibraryUtils.shared.saveVideo(videoURL: url) { (success) in

                        Async.main {
                            self.hideSpinner()
                            self.removeObservers()
                            self.currentPlayerItem = nil
                            let asset = AVURLAsset(url: url)
                            self.addPlayerItemToPlayer(asset: asset)
                        }
                    }
                }) {
                    
                }
            }
        }
    }
}
