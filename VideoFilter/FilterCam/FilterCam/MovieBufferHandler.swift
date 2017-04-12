//
//  VideoFilterHandler.swift
//  FilterCam
//
//  Created by Shreesha on 17/09/16.
//  Copyright © 2016 YML. All rights reserved.
//

import Foundation
import AVFoundation
import UIKit

enum MovieBufferErrorHandler: String, FilterCamErrorHandler {
    case CameraSessionInterrupted = "CaptureSession interupted"
    case FailedToAddCameraInput = "Failed To Add Camera Input"
    case FailedToAddCameraStillImageOutput = "Failed To Add Camera Still Image Output"
    case FailedToAddVideoCaptureOutput = "Failed To Add Video Capture Output"
    case FailedToAddAudioOutput = "Failed To Add Audio Output"

    var description: String {
        return self.rawValue
    }
}

typealias BufferCallBack = (CMSampleBuffer) -> ()

class MovieBufferHandler: NSObject, CaptureVideoDelagateProtocol, CaptureAudioDelagateProtocol {

    private (set) var currentDevicePosition = AVCaptureDevicePosition.back
    private (set) var videoOrientation: AVCaptureVideoOrientation
    fileprivate var captureCameraInput: AVCaptureDeviceInput?
    fileprivate var captureAudioInput: AVCaptureDeviceInput?
    fileprivate var captureVideoDelegate: CaptureVideoBufferDelegate?
    fileprivate var captureAudioDelegate: CaptureAudioBufferDelegate?

    fileprivate lazy var cameraStillImageOutput = AVCaptureStillImageOutput()
    fileprivate lazy var audioOutput = AVCaptureAudioDataOutput()
    fileprivate lazy var videoCaptureOutput = AVCaptureVideoDataOutput()
    fileprivate lazy var cameraCaptureSession: AVCaptureSession = {
        let session = AVCaptureSession()

        if session.canSetSessionPreset(self.resolutionQuality) {
            session.sessionPreset = self.resolutionQuality
        } else {
            print("Failed to set the preset value")
        }
        return session
    }()

    var resolutionQuality = AVCaptureSessionPresetPhoto {
        didSet {
            if cameraCaptureSession.canSetSessionPreset(resolutionQuality) {
                cameraCaptureSession.sessionPreset = resolutionQuality
            }
        }
    }

    var inputVideoDevice: AVCaptureDevice?
    var videoConnection: AVCaptureConnection?
    var cameraConnection: AVCaptureConnection?

    var cameraSettings: [String: String] {
        didSet {
            cameraCaptureSession.beginConfiguration()
            cameraCaptureSession.removeOutput(cameraStillImageOutput)
            setTheCameraStillImageOutputs()
            cameraCaptureSession.commitConfiguration()
        }
    }

    var bufferVideoCallBack: BufferCallBack?
    var bufferAudioCallback: BufferCallBack?
    var videoSettings: [AnyHashable: Any] {
        didSet {
            cameraCaptureSession.beginConfiguration()
            cameraCaptureSession.removeOutput(videoCaptureOutput)
            setTheVideoOutput()
            cameraCaptureSession.commitConfiguration()
        }
    }

    var errorCallBack: CustomErrorCallback?

    override init() {
        videoSettings = [(kCVPixelBufferPixelFormatTypeKey as NSString) : NSNumber(value: kCVPixelFormatType_32BGRA as UInt32)]
        cameraSettings = [AVVideoCodecKey:AVVideoCodecJPEG]
        videoOrientation = AVCaptureVideoOrientation.portrait
        super.init()
        initialize()
    }

    private func initialize() {
        addInputsToCameraSession()
        setTheVideoOutput()
        setTheCameraStillImageOutputs()
        setAudioOutput()
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        guard let keyPath = keyPath else {
            return
        }

        if NSNotification.Name(keyPath) == NSNotification.Name.AVCaptureSessionRuntimeError {
            let cameraSession = object as? AVCaptureSession

            guard let captureSession = cameraSession else {
                return
            }

            if captureSession.isInterrupted {
                errorCallBack?(nil, MovieBufferErrorHandler.CameraSessionInterrupted)
            }
        }
    }

    func changeCameraSettingsTo(settings: [String: String]) {
        cameraCaptureSession.removeOutput(cameraStillImageOutput)
        setTheCameraStillImageOutputs()
    }

    func changeVideoSettingsTo(settings: [AnyHashable: Any]) {
        cameraCaptureSession.removeOutput(videoCaptureOutput)
        setTheVideoOutput()
    }

    func changeToVideoOrientation(_ orientation: UIInterfaceOrientation) {
        switch orientation {
        case .portrait:
            videoConnection?.videoOrientation = .portrait
            cameraConnection?.videoOrientation = .portrait
        case .landscapeLeft:
            videoConnection?.videoOrientation = .landscapeLeft
            cameraConnection?.videoOrientation = .landscapeLeft
        case .landscapeRight:
            videoConnection?.videoOrientation = .landscapeRight
            cameraConnection?.videoOrientation = .landscapeRight
        case .portraitUpsideDown:
            videoConnection?.videoOrientation = .portraitUpsideDown
            cameraConnection?.videoOrientation = .portraitUpsideDown
        case .unknown: break
        }
    }

    fileprivate func addInputsToCameraSession() {

        inputVideoDevice = getCameraDevice(AVMediaTypeVideo, devicePosition: currentDevicePosition)
        let inputAudioDevice = AVCaptureDevice.defaultDevice(withMediaType: AVMediaTypeAudio)
        captureCameraInput = try? AVCaptureDeviceInput(device: inputVideoDevice)
        captureAudioInput = try? AVCaptureDeviceInput(device: inputAudioDevice)

        if cameraCaptureSession.canAddInput(captureCameraInput) {
            cameraCaptureSession.addInput(captureCameraInput)
        } else {
            errorCallBack?(nil, MovieBufferErrorHandler.FailedToAddCameraInput)
        }

        let permission = AudioPermission()
        permission.requestPermission { (status) in
            if status == .Authorized {
                if self.cameraCaptureSession.canAddInput(self.captureAudioInput) {
                    self.cameraCaptureSession.addInput(self.captureAudioInput)
                } else {
                    self.errorCallBack?(nil, MovieBufferErrorHandler.FailedToAddCameraInput)
                }
            }
        }
    }

    fileprivate func setTheCameraStillImageOutputs() {
        cameraStillImageOutput.outputSettings = cameraSettings

        if cameraCaptureSession.canAddOutput(cameraStillImageOutput) {
            cameraCaptureSession.addOutput(cameraStillImageOutput)
        } else {
            errorCallBack?(nil, MovieBufferErrorHandler.FailedToAddCameraStillImageOutput)
        }

        cameraConnection = cameraStillImageOutput.connection(withMediaType: AVMediaTypeVideo)
        cameraConnection?.videoOrientation = videoOrientation
    }

    fileprivate func setAudioOutput() {
        captureAudioDelegate = CaptureAudioBufferDelegate(delegate: self)
        audioOutput.setSampleBufferDelegate(captureAudioDelegate, queue: DispatchQueue.main)

        let permission = AudioPermission().status()

        if permission == .Authorized {
            if self.cameraCaptureSession.canAddOutput(self.audioOutput) {
                self.cameraCaptureSession.addOutput(self.audioOutput)
            } else {
                self.errorCallBack?(nil, MovieBufferErrorHandler.FailedToAddAudioOutput)
            }

        }
    }

    func recomendedSettingsForAssetWriter() -> [String: AnyObject] {
        return audioOutput.recommendedAudioSettingsForAssetWriter(withOutputFileType: AVFileTypeWAVE) as! [String : AnyObject]
    }

    fileprivate func setTheVideoOutput() {
        videoCaptureOutput.videoSettings = videoSettings

        captureVideoDelegate = CaptureVideoBufferDelegate(delegate: self)

        videoCaptureOutput.setSampleBufferDelegate(captureVideoDelegate, queue: DispatchQueue.main)
        if cameraCaptureSession.canAddOutput(videoCaptureOutput) {
            cameraCaptureSession.addOutput(videoCaptureOutput)
        } else {
            errorCallBack?(nil, MovieBufferErrorHandler.FailedToAddVideoCaptureOutput)
        }

        videoConnection = videoCaptureOutput.connection(withMediaType: AVMediaTypeVideo)
        videoConnection?.videoOrientation = videoOrientation
    }

    func layer() -> AVCaptureVideoPreviewLayer? {
        let videoPreviewLayer = AVCaptureVideoPreviewLayer(session: cameraCaptureSession)
        videoPreviewLayer!.connection?.videoOrientation = AVCaptureVideoOrientation.portrait
        return videoPreviewLayer
    }

    fileprivate func getCameraDevice(_ deviceType: String, devicePosition: AVCaptureDevicePosition) -> AVCaptureDevice? {
        var device = AVCaptureDevice.defaultDevice(withMediaType: deviceType)
        let devices : NSArray = AVCaptureDevice.devices(withMediaType: deviceType) as NSArray

        for dev in devices {
            if (dev as AnyObject).position == devicePosition {
                device = dev as? AVCaptureDevice
                break
            }
        }

        return device
    }

    func startSession() {
        if !cameraCaptureSession.isRunning {
            cameraCaptureSession.addObserver(self, forKeyPath: NSNotification.Name.AVCaptureSessionRuntimeError.rawValue, options: NSKeyValueObservingOptions.new, context: nil)
            let permissionService = PermissionType.Camera.permissionService
            permissionService.requestPermission { (status) in
                switch status {
                case .Authorized:
                    self.cameraCaptureSession.startRunning()
                default: ()
                }
            }
        }
    }

    func stopSession() {
        cameraCaptureSession.stopRunning()
    }

    func removeObservers() {
        cameraCaptureSession.removeObserver(self, forKeyPath: NSNotification.Name.AVCaptureSessionRuntimeError.rawValue)
    }

    func changeDeviceTypeTo(position: AVCaptureDevicePosition) {

        cameraCaptureSession.beginConfiguration()
        cameraCaptureSession.removeInput(captureCameraInput)
        cameraCaptureSession.removeOutput(cameraStillImageOutput)
        cameraCaptureSession.removeOutput(videoCaptureOutput)

        currentDevicePosition = position
        initialize()

        cameraCaptureSession.commitConfiguration()
    }

    func captureImage(withFilter filter: CIFilter?, callBack: @escaping (UIImage?) -> ()) {
        if let videoConnection = cameraConnection {
            cameraStillImageOutput.captureStillImageAsynchronously(from: videoConnection) {
                (imageDataSampleBuffer, error) -> Void in
                let fixedImage = UIImage(data: AVCaptureStillImageOutput.jpegStillImageNSDataRepresentation(imageDataSampleBuffer))


                let orientation = fixedImage?.imageOrientation
                let scale = fixedImage?.scale

                guard let filter = filter else {
                    callBack(fixedImage)
                    return
                }

                let ciimage = CIImage(cgImage: fixedImage!.cgImage!)

                filter.setValue(ciimage, forKey: kCIInputImageKey)

                let _filteredImage = filter.outputImage

                guard let filteredImage = _filteredImage else {
                    callBack(nil)
                    return
                }

                guard let cgImage = CIContext(options: nil).createCGImage(filteredImage, from: ciimage.extent) else {
                    callBack(nil)
                    return
                }

                let uiImage = UIImage(cgImage: cgImage, scale: scale!, orientation: orientation!)
                callBack(uiImage)
            }
        }
    }

    func didOutput(_ videoSampleBuffer: CMSampleBuffer) {
        if let bufferCallBack = bufferVideoCallBack {
            bufferCallBack(videoSampleBuffer)
        }
    }

    func didOutputAudio(_ audioSampleBuffer: CMSampleBuffer) {
        if let bufferCallBack = bufferAudioCallback {
            bufferCallBack(audioSampleBuffer)
        }
    }

    func transform(withMirroring: Bool) -> CGAffineTransform {
        let currentInterfaceOrientation = UIApplication.shared.statusBarOrientation
        return transformFor(AVCaptureVideoOrientation(rawValue: currentInterfaceOrientation.rawValue)!, withAutoMirroring: withMirroring)
    }

    func transformFor(_ orientation: AVCaptureVideoOrientation, withAutoMirroring mirror: Bool) -> CGAffineTransform {
        var transform = CGAffineTransform.identity

        // Calculate offsets from an arbitrary reference orientation (portrait)
        let orientationAngleOffset = LibraryUtils.angleOffsetFromPortraitTo(orientation)
        let videoOrientationAngleOffset = LibraryUtils.angleOffsetFromPortraitTo(videoConnection!.videoOrientation)

        // Find the difference in angle between the desired orientation and the video orientation
        let angleOffset = orientationAngleOffset - videoOrientationAngleOffset
        transform = CGAffineTransform(rotationAngle: angleOffset)

        if inputVideoDevice!.position == .front {
            if mirror {
                transform = transform.scaledBy(x: -1, y: 1)
            } else {
                if UIInterfaceOrientationIsPortrait(UIInterfaceOrientation(rawValue: orientation.rawValue)!) {
                    transform = transform.rotated(by: M_PI.g)
                }
            }
        }

        return transform
    }
}

private class CaptureVideoBufferDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let delegate: CaptureVideoDelagateProtocol?

    init(delegate: CaptureVideoDelagateProtocol) {
        self.delegate = delegate
    }

    @objc fileprivate func captureOutput(_ captureOutput: AVCaptureOutput!, didOutputSampleBuffer sampleBuffer: CMSampleBuffer!, from connection: AVCaptureConnection!) {
        delegate?.didOutput(sampleBuffer)
    }
}

private class CaptureAudioBufferDelegate: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    let delegate: CaptureAudioDelagateProtocol?

    init(delegate: CaptureAudioDelagateProtocol) {
        self.delegate = delegate
    }

    @objc fileprivate func captureOutput(_ captureOutput: AVCaptureOutput!, didOutputSampleBuffer sampleBuffer: CMSampleBuffer!, from connection: AVCaptureConnection!) {
        delegate?.didOutputAudio(sampleBuffer)
    }
}

protocol CaptureVideoDelagateProtocol{
    func didOutput(_ videoSampleBuffer: CMSampleBuffer)
}

protocol CaptureAudioDelagateProtocol{
    func didOutputAudio(_ audioSampleBuffer: CMSampleBuffer)
}
