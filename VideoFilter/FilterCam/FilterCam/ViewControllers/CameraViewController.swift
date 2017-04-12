//
//  CameraViewController.swift
//  FilterCam
//
//  Created by Shreesha on 23/02/17.
//  Copyright © 2017 YML. All rights reserved.
//

import UIKit
import AVFoundation
import Photos

class CameraViewController: UIViewController {

    @IBOutlet weak var transitionView: UIView!
    @IBOutlet var panGesture: UIPanGestureRecognizer!
    @IBOutlet var swipeGesture: UISwipeGestureRecognizer!
    @IBOutlet weak var settingsContainerView: UIView!
    @IBOutlet weak var previewLayerView: UIView!
    @IBOutlet weak var captureButton: UIButton!
    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var settingsRightConstraint: NSLayoutConstraint!

    @IBOutlet weak var cameraSettingLabel: UILabel!
    @IBOutlet weak var cameraSwitch: UISwitch!
    @IBOutlet weak var galleryButton: UIButton!
    @IBOutlet weak var videoLabel: UILabel!
    fileprivate var filterManager: FilterPipeline?
    fileprivate var openGLView: OpenGLPixelBufferView?
    var filter: CIFilter?
    fileprivate var timer: Timer?
    fileprivate var flipLayer: CALayer?

    fileprivate var currentDevicePosition = AVCaptureDevicePosition.back
    fileprivate var currentCaptureType = PHAssetMediaType.video {
        didSet {
            switch currentCaptureType {
            case .image:
                videoLabel.isHidden = true
                captureButton.setImage(#imageLiteral(resourceName: "video_icon_white"), for: .normal)
                LibraryUtils.shared.fetchLastFor(mediaType: .image, completion: { (image, asset) in
                    Async.main {
                        if let _image = image {
                            self.galleryButton.setImage(_image, for: .normal)
                        }
                    }
                })
            default:
                videoLabel.isHidden = false
                captureButton.setImage(#imageLiteral(resourceName: "Button_recordvideo"), for: .normal)
                LibraryUtils.shared.fetchLastFor(mediaType: .video, completion: { (image, asset) in
                    Async.main {
                        if let _asset = asset {
                            if let _url = (_asset as? AVURLAsset)?.url {
                                let image = LibraryUtils.getThumbnailImageFor(_url)
                                Async.main {
                                    self.galleryButton.setImage(image, for: .normal)
                                }
                            }
                        }
                    }
                })
            }
        }
    }

    var timerCount: CGFloat = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        filterManager = FilterPipeline.shared()

        filterManager?.initializeWith(filterType: .live,
                                      videoSettings: [(kCVPixelBufferPixelFormatTypeKey as NSString) : NSNumber(value: kCVPixelFormatType_32BGRA as UInt32)])
        filterManager?.filterResidueDelegate.addDelegate(self)
        prepareOpenGLView()
        settingsContainerView.layer.cornerRadius = 10
        settingsContainerView.layer.masksToBounds = true
        videoLabel.isHidden = true
        cameraSettingLabel.text = "Video"

        settingsRightConstraint.constant = -95
        videoLabel.text = "0"
        LibraryUtils.shared.fetchLastFor(mediaType: .video, completion: { (image, asset) in
            Async.main {
                if let _asset = asset {
                    if let _url = (_asset as? AVURLAsset)?.url {
                        let image = LibraryUtils.getThumbnailImageFor(_url)
                        Async.main {
                            self.galleryButton.setImage(image, for: .normal)
                        }
                    }
                }
            }
        })
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        view.layoutIfNeeded()
        navigationController?.isNavigationBarHidden = true
        reloadViews()
    }

    private func reloadViews() {

        self.openGLView?.alpha = 0
        previewLayerView.backgroundColor = UIColor.black
        Async.global(.background) {
            self.filterManager?.startCameraSession()
            self.resetTheView()
            self.filterManager?.filteringType = .live
            Async.main {
                UIView.animate(withDuration: 0.3, animations: {
                    self.openGLView?.alpha = 1
                    self.previewLayerView.backgroundColor = UIColor(red: 223/255, green: 223/255, blue: 223/255, alpha: 1)
                })
            }
        }

        let current = currentCaptureType
        currentCaptureType = current
        switch currentCaptureType {
        case .video:
            captureButton.setImage(#imageLiteral(resourceName: "Button_recordvideo"), for: .normal)
            videoLabel.isHidden = false
        case .image:
            captureButton.setImage(#imageLiteral(resourceName: "video_icon_white"), for: .normal)
            videoLabel.isHidden = true
        default: break
        }

        let orientation = UIApplication.shared.statusBarOrientation
        filterManager?.changeVideoOrientation(orientation)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        NotificationCenter.default.removeObserver(self)
        openGLView?.reset()
        previewLayerView.backgroundColor = UIColor.black
        openGLView?.alpha = 0
        filterManager?.stopCameraSession()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        navigationController?.isNavigationBarHidden = false
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        print("----------------------------Recieved Memory warning---------------------------")
        // Dispose of any resources that can be recreated.
    }

    func prepareOpenGLView() {
        openGLView = OpenGLPixelBufferView(frame: CGRect.zero)
        openGLView?.autoresizingMask = [UIViewAutoresizing.flexibleHeight, UIViewAutoresizing.flexibleWidth]

        openGLView?.transform = filterManager!.transform(withMirroring: false)

        previewLayerView.insertSubview(openGLView!, at: 0)
        resetTheView()
    }

    @IBAction func panGestureHandler(_ sender: Any) {
        let panGesture = sender as! UIPanGestureRecognizer
        switch panGesture.state {
        case .began:
            break
        case .changed:
            let traslation = panGesture.translation(in: view)

            let minCenterX = (view.frame.width - 10) - (settingsContainerView.frame.width / 2)
            let maxCenterX = (view.frame.width + 95) - (settingsContainerView.frame.width / 2)

            var constant = settingsContainerView.center.x + traslation.x

            if constant < minCenterX {
                constant = minCenterX
            } else if constant > maxCenterX {
                constant = maxCenterX
            }

            settingsContainerView.center = CGPoint(x: constant, y: settingsContainerView.center.y)
            view.updateConstraints()
            panGesture.setTranslation(CGPoint.zero, in: view)
        case .ended:

            let velocity = panGesture.velocity(in: view)
            let constant: CGFloat = velocity.x < 0 ? 10: -95

            self.settingsRightConstraint.constant = constant
            UIView.animate(withDuration: 0.4, delay: 0.0, usingSpringWithDamping: 0.4, initialSpringVelocity: 0.2, options: .curveEaseInOut, animations: {
                self.view.layoutIfNeeded()
            }, completion: nil)
        default:
            let velocity = panGesture.velocity(in: view)
            let constant: CGFloat = velocity.x < 0 ? 10: -95

            self.settingsRightConstraint.constant = constant
            UIView.animate(withDuration: 0.4, delay: 0.0, usingSpringWithDamping: 0.4, initialSpringVelocity: 0.2, options: .curveEaseInOut, animations: {
                self.view.layoutIfNeeded()
            }, completion: nil)
            
        }

    }

    @IBAction func cameraSwitchDidSelect(_ sender: Any) {
        let text = cameraSwitch.isOn ? "Video" : "Photo"
        let mediaType = cameraSwitch.isOn ? PHAssetMediaType.video : .image
        currentCaptureType = mediaType
        cameraSettingLabel.text = text

    }

    func startShutterAnimation() {
        let shutterAnimation = CATransition()
        shutterAnimation.delegate = self
        shutterAnimation.duration = 0.8

        shutterAnimation.timingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseInEaseOut)
        shutterAnimation.type = "cameraIris"
        shutterAnimation.setValue("cameraIris", forKey: "cameraIris")
        flipLayer = CALayer()
        flipLayer?.bounds = view.bounds
        view.layer.addSublayer(flipLayer!)
        self.view.layer.add(shutterAnimation, forKey: "cameraIris")
    }

    @IBAction func swipeGestureHandlerRight(_ sender: Any) {
        openGLView?.alpha = 0
        startShutterAnimation()
        currentDevicePosition = currentDevicePosition == .front ? .back : .front
        filterManager?.changeDevicePositionTo(position: currentDevicePosition)
        reloadViews()
    }

    @IBAction func captureButtonDidClick(_ sender: Any) {
        handelCaptureAction()
    }

    @IBAction func galleryButtonDidClick(_ sender: Any) {
        let vc = storyboard?.instantiateViewController(withIdentifier: "GaleryCollectionViewController") as! GaleryCollectionViewController
        vc.mediaType = currentCaptureType
        navigationController?.pushViewController(vc, animated: true)
    }

    @IBAction func filterButtonDidClick(_ sender: Any) {
        let image = filterManager?.getCurrentImage()

        let filterViewController = storyboard?.instantiateViewController(withIdentifier: "FilterViewController") as! FilterViewController
        filterViewController.image = image
        filterViewController.delegate = self

        navigationController?.present(filterViewController, animated: true, completion: nil)
    }
    
    override func didRotate(from fromInterfaceOrientation: UIInterfaceOrientation) {
        filterManager?.reset()
        resetTheView()
    }

    override func willRotate(to toInterfaceOrientation: UIInterfaceOrientation, duration: TimeInterval) {
        filterManager?.changeVideoOrientation(toInterfaceOrientation)
        filterManager?.reset()
        resetTheView()
    }

    fileprivate func resetTheView(){
        Async.main {
            self.openGLView?.transform = self.filterManager!.transform(withMirroring: true)
            self.openGLView?.frame = self.view.bounds
            self.openGLView?.reset()
        }

    }

    fileprivate func handelCaptureAction() {

        if currentCaptureType == .video {
            if let filterManager = filterManager {
                if !filterManager.isRecordingVideo {
                    captureButton.setImage(#imageLiteral(resourceName: "Button_stoprecordvideo"), for: .normal)
                    startTimer()
                } else {
                    captureButton.setImage(#imageLiteral(resourceName: "Button_recordvideo"), for: .normal)
                    stopTimer()
                }
            } else {
                captureButton.setImage(#imageLiteral(resourceName: "Button_recordvideo"), for: .normal)
                stopTimer()
            }

            processVideo()
        } else {
            capturePhoto()
        }
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(CameraViewController.timerHandler(sender:)), userInfo: nil, repeats: true)
    }

    func timerHandler(sender: Timer) {
        timerCount += 1
        videoLabel.text = String(format: "%0.0f", timerCount)
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        timerCount = 0
        videoLabel.text = String(format: "%0.0f", timerCount)
    }

    private func capturePhoto() {
        filterManager?.capturedImage(withFilter: filter, completion: { (image) in
            if let _image = image {

                LibraryUtils.shared.saveImage(image: _image, completion: { (success) in
                    let current = self.currentCaptureType
                    self.currentCaptureType = current

                })
            }
        })

        view.backgroundColor = UIColor.white
        UIView.animate(withDuration: 0.1, animations: { 
            self.previewLayerView.alpha = 0
        }) { (animated) in
            UIView.animate(withDuration: 0.1, animations: { 
                self.previewLayerView.alpha = 1
                self.view.backgroundColor = UIColor.black
            })
        }
    }

    private func processVideo() {
        let outputFilePath = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("FilterCam" + "\(Date().timeIntervalSince1970)" + ".mov")

        guard let filterManager = filterManager else {
            return
        }

        if filterManager.isRecordingVideo {
            filterManager.stopRecording(completion: { (url, error) in
                LibraryUtils.shared.saveVideo(videoURL: url!, completion: { (success) in

                })
            })
        } else {
            filterManager.startRecording(atUrl: outputFilePath, size: view.bounds.size, transform: CGAffineTransform.identity)
        }
    }
}

extension CameraViewController: FilterResidueDelegate {
    func didCopySampleBuffer(buffer: CVPixelBuffer?) {
        openGLView?.displayPixelBuffer(buffer!)
    }
}

extension CameraViewController: FilterViewControllerDelegate {
    func filterViewController(viewController: FilterViewController, didSelectFilter filter: CIFilter?) {
        viewController.dismiss(animated: true) { 
            self.filterManager?.currentFilter = filter
            self.filter = filter
        }
    }
}

extension CameraViewController: SettingsViewControllerDelegate {
    func settingsViewController(vc: SettingsViewController, didSelectOPtion option: PHAssetMediaType) {
        dismiss(animated: true) {
        }
    }
}

extension CameraViewController: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer == swipeGesture {
            let location = swipeGesture.location(in: self.view)
            if location.x > (view.frame.width - view.frame.width / 3) {
                return false
            }
        } else {
            let location = panGesture.location(in: self.view)
            if location.x < (view.frame.width - view.frame.width / 3) {
                return false
            }
        }

        return true
    }
}

extension CameraViewController: CAAnimationDelegate {
    func animationDidStart(_ anim: CAAnimation) {
    }

    func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
        flipLayer?.removeFromSuperlayer()
        openGLView?.alpha = 1
    }
}
