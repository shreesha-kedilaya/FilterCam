//
//  FilterManager.swift
//  FilterCam
//
//  Created by Shreesha on 22/09/16.
//  Copyright © 2016 YML. All rights reserved.
//

import Foundation
import CoreImage
import AVFoundation
import UIKit
import Photos
enum RosyWriterRecordingStatus: Int {
    case idle = 0
    case startingRecording
    case recording
    case stoppingRecording
}


protocol FilterPipelineDelegate: class {
    func capturePipelineDidRunOutOfPreviewBuffers(_ capturePipeline: FilterPipeline)
    
    // Recording
    func capturePipelineRecordingDidStart(_ capturePipeline: FilterPipeline)
    // Can happen at any point after a startRecording call, for example: startRecording->didFail (without a didStart), willStop->didFail (without a didStop)
    func capturePipeline(_ capturePipeline: FilterPipeline, recordingDidFailWithError error: NSError)
    func capturePipelineRecordingWillStop(_ capturePipeline: FilterPipeline)
    func capturePipelineRecordingDidStop(_ capturePipeline: FilterPipeline)
    
}


private let RETAINED_BUFFER_COUNT = 6
class FilterPipeline {

    fileprivate var videoRecorder: VideoRecorder?
    private weak var videoBufferHandler: VideoBufferHandler?
    private var coreImageView: CoreImageView?
    
    fileprivate(set) var videoFrameRate: Float = 0.0
    
    fileprivate var _previousSecondTimestamps: [CMTime] = []

    fileprivate (set) var currentImage: CIImage?
    fileprivate (set) var numberOfFrames = 0
    fileprivate (set) var isRecordingVideo = false
    fileprivate (set) var currentFilter: CustomFilter?
    
    fileprivate var _videoCompressionSettings: [String : AnyObject]?
    fileprivate var _recordingURL: URL!

    fileprivate var filterRenderer = FilterRenderer()

    fileprivate var videoDimentions: CMVideoDimensions?
    fileprivate var outputFormatDescriptions: CMFormatDescription?
    var _renderingEnabled = true
    var _recordingStatus: RosyWriterRecordingStatus = .idle
    var recordingOrientation: AVCaptureVideoOrientation = .portrait
    fileprivate var videoOrientation: AVCaptureVideoOrientation = .portrait

    var filterHandler: ((_ filterImage: CIImage?) -> Void)?
    
    weak var delegate:FilterPipelineDelegate?

    var transForm = CGAffineTransform.identity {
        didSet {
            videoBufferHandler?.videoTransform = transForm
        }
    }

    func startCameraSession() {
        videoBufferHandler?.startSession()
    }

    func stopCameraSession() {
        videoBufferHandler?.stopSession()
    }

    func removeObservers(){
        videoBufferHandler?.removeObservers()
    }

    init() {}

    init(frame: CGRect, transForm: CGAffineTransform) {
        videoBufferHandler = VideoBufferHandler()
        coreImageView = CoreImageView(frame: frame)
        videoBufferHandler?.bufferCallBack = { [weak self] (buffer, transForm) -> () in
            self?.handleTheOutputBuffer(buffer, transform: transForm)
        }
        self.transForm = transForm
        videoBufferHandler?.videoTransform = self.transForm
    }

    func startWriting(withPath path: String, liveVideo: Bool, size: CGSize) {
        
        Async.synchronized {
            if self._recordingStatus != .idle {
                fatalError("Already recording")
            }
            
            self.transitionToRecordingStatus(.startingRecording, error: nil)
        }

        self._recordingURL = URL(string: path)

        let recorder = VideoRecorder(URL: _recordingURL)
        let videoOut = videoBufferHandler?.videoCaptureOutput
        _videoCompressionSettings = videoOut?.recommendedVideoSettingsForAssetWriter(withOutputFileType: AVFileTypeQuickTimeMovie) as? [String: AnyObject]
        
        // Front camera recording shouldn't be mirrored
        let videoTransform = self.transformFromVideoBufferOrientationToOrientation(self.recordingOrientation, withAutoMirroring: false)
        
        recorder.startVideoTrackWith(self.outputFormatDescriptions!, transform: videoTransform, settings: _videoCompressionSettings!)
        
        let callbackQueue = DispatchQueue(label: "com.apple.sample.capturepipeline.recordercallback", attributes: []); // guarantee ordering of callbacks with a serial queue
        recorder.setDelegate(self, callBackQueue: callbackQueue)
        self.videoRecorder = recorder
        
        // asynchronous, will call us back with recorderDidFinishPreparing: or recorder:didFailWithError: when done
        self.videoRecorder?.prepareToRecord()
    }

    func stopWriting(completion: @escaping (URL) -> Void) {

        var returnValue = false
        
        if _recordingStatus != .recording {
            returnValue = true
        } else {
            returnValue = false
        }
        
        self.transitionToRecordingStatus(.stoppingRecording, error: nil)
        
        if returnValue {return}
        
        self.videoRecorder?.finishRecording()
    }


    func applyFilter(filter: @escaping CustomFilter) {
        currentFilter = filter
    }

    func abortWriting() {
        videoRecorder?.abortWriting()
        videoRecorder = nil
    }

    func coreImageView(withFrame frame: CGRect? = nil) -> CoreImageView? {
        guard let frame = frame else {
            return coreImageView
        }
        coreImageView?.frame = frame
        return coreImageView
    }
    
    //MARK: New Implementations

    private func setupRenderer(formatDescription: CMFormatDescription) {
        videoDimentions = CMVideoFormatDescriptionGetDimensions(formatDescription)
        filterRenderer.prepareForInputWith(inputFormatDescription: formatDescription, outputRetainedBufferCountHint: RETAINED_BUFFER_COUNT)
        outputFormatDescriptions = formatDescription
    }

    func videoPipelineDidRunOutOfBuffers() {
        // We have run out of buffers.
        // Tell the delegate so that it can flush any cached buffers.
        if self.delegate != nil {
            Async.global {
                autoreleasepool {
                    self.delegate?.capturePipelineDidRunOutOfPreviewBuffers(self)
                }
            }
        }
    }
    
    fileprivate func calculateFramerateAtTimestamp(_ timestamp: CMTime) {
        _previousSecondTimestamps.append(timestamp)
        
        let oneSecond = CMTimeMake(1, 1)
        let oneSecondAgo = CMTimeSubtract(timestamp, oneSecond)
        
        while _previousSecondTimestamps[0] < oneSecondAgo {
            _previousSecondTimestamps.remove(at: 0)
        }
        
        if _previousSecondTimestamps.count > 1 {
            let duration: Double = CMTimeGetSeconds(CMTimeSubtract(_previousSecondTimestamps.last!, _previousSecondTimestamps[0]))
            let newRate = Float(_previousSecondTimestamps.count - 1) / Float(duration.f)
            self.videoFrameRate = newRate
        }
    }
    
    //WARNING: Tear down all the pipe line buffers
    //WARNING: Call all the delegates

    private func handleTheOutputBuffer(_ sampleBuffer: CMSampleBuffer, transform: CGAffineTransform) {
        let ciimage = CIImage(buffer: sampleBuffer).applying(AVCaptureDevicePosition.back.transform)
        currentImage = ciimage

        numberOfFrames += 1
        var image: CIImage? = ciimage
        if let filter = currentFilter {
            image = filter(image!).outputImage
        }

        let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer)
        if let _ = self.outputFormatDescriptions {

        } else {
            if let formatDescription = formatDescription {
                setupRenderer(formatDescription: formatDescription)
            }
        }

        filterHandler?(image)

        if _recordingStatus == .recording {

            if let _ = outputFormatDescriptions {
                renderVideoSampleBuffer(sampleBuffer)
            } else {
                if let formatDescription = formatDescription {
                    setupRenderer(formatDescription: formatDescription)
                }
            }
        }
    }

    fileprivate func renderVideoSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        var renderedPixelBuffer: CVPixelBuffer? = nil
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        self.calculateFramerateAtTimestamp(timestamp)

        // We must not use the GPU while running in the background.
        // setRenderingEnabled: takes the same lock so the caller can guarantee no GPU usage once the setter returns.
        var returnFlag: Bool {
            if _renderingEnabled {
                let sourcePixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
                renderedPixelBuffer = self.filterRenderer.copyRenderedPixelBuffer(pixelBuffer: sourcePixelBuffer)
                return false
            } else {
                return true //indicates return from func
            }
        }
        if returnFlag {return}

        if renderedPixelBuffer != nil {
            if _recordingStatus == .recording {
                self.videoRecorder?.appendVideoPixelBuffer(renderedPixelBuffer!, withPresentationTime: timestamp)
            }

        } else {
            self.videoPipelineDidRunOutOfBuffers()
        }
    }
    
    fileprivate func transitionToRecordingStatus(_ newStatus: RosyWriterRecordingStatus, error: NSError?) {
        var delegateClosure: (() -> Void)? = nil
        let oldStatus = _recordingStatus
        _recordingStatus = newStatus
        
        if newStatus != oldStatus && delegate != nil {
            if error != nil && newStatus == .idle {
                delegateClosure = {self.delegate?.capturePipeline(self, recordingDidFailWithError: error!)}
            } else {
                // only the above delegate method takes an error
                if oldStatus == .startingRecording && newStatus == .recording {
                    delegateClosure = {self.delegate?.capturePipelineRecordingDidStart(self)}
                } else if oldStatus == .recording && newStatus == .stoppingRecording {
                    delegateClosure = {self.delegate?.capturePipelineRecordingWillStop(self)}
                } else if oldStatus == .stoppingRecording && newStatus == .idle {
                    delegateClosure = {self.delegate?.capturePipelineRecordingDidStop(self)}
                }
            }
        }
        
        if delegateClosure != nil {
            Async.global(closer: { 
                autoreleasepool {
                    delegateClosure!()
                }
            })
        }
    }
    
    func transformFromVideoBufferOrientationToOrientation(_ orientation: AVCaptureVideoOrientation, withAutoMirroring mirror: Bool) -> CGAffineTransform {
        var transform = CGAffineTransform.identity
        
        // Calculate offsets from an arbitrary reference orientation (portrait)
        let orientationAngleOffset = angleOffsetFromPortraitOrientationToOrientation(orientation)
        let videoOrientationAngleOffset = angleOffsetFromPortraitOrientationToOrientation(self.videoOrientation)
        
        // Find the difference in angle between the desired orientation and the video orientation
        let angleOffset = orientationAngleOffset - videoOrientationAngleOffset
        transform = CGAffineTransform(rotationAngle: angleOffset)
        
        if let device = videoBufferHandler?.inputDevice {
            
            if device.position == .front {
                if mirror {
                    transform = transform.scaledBy(x: -1, y: 1)
                } else {
                    if UIInterfaceOrientationIsPortrait(UIInterfaceOrientation(rawValue: orientation.rawValue)!) {
                        transform = transform.rotated(by: M_PI.f)
                    }
                }
            }
        }
        
        return transform
    }
    
    
    fileprivate final func angleOffsetFromPortraitOrientationToOrientation(_ orientation: AVCaptureVideoOrientation) -> CGFloat {
        var angle: CGFloat = 0.0
        
        switch orientation {
        case .portrait:
            angle = 0.0
        case .portraitUpsideDown:
            angle = M_PI.f
        case .landscapeRight:
            angle = -M_PI_2.f
        case .landscapeLeft:
            angle = M_PI_2.f
        }
        
        return angle
    }
    
    deinit {
        print("Deinit for Filter manager is called")
    }
}

extension FilterPipeline: VideoRecorderDelegate {
    func videoRecorder(_ recorder: VideoRecorder, didFailWithError error: NSError) {
        self.videoRecorder = nil
        self.transitionToRecordingStatus(.idle, error: error)
    }

    //Convert the recording status to RosyWriterRecordingStatus.recording here
    func videoRecorderDidFinishPreparing(_ recorder: VideoRecorder) {
        if _recordingStatus != .startingRecording {
            fatalError("Expected to be in StartingRecording state")
        }
        self.transitionToRecordingStatus(.recording, error: nil)
    }
    
    func videoRecorderDidFinishRecording(_ recorder: VideoRecorder) {
            if _recordingStatus != .stoppingRecording {
                fatalError("Expected to be in StoppingRecording state")
            }
            
            // No state transition, we are still in the process of stopping.
            // We will be stopped once we save to the assets library.
        self.videoRecorder = nil
        
        saveVideoToLibrary(_recordingURL) { (success, error) in
            if !success {
                print("Failed to save the movie to the Library")
            }
            self.transitionToRecordingStatus(.idle, error: error)
        }
    }
    
    func saveVideoToLibrary(_ videoURL: URL, completion: @escaping (_ succeeded: Bool, _ error: NSError?) -> ()) {
        PHPhotoLibrary.requestAuthorization { status in
            // Return if unauthorized
            guard status == .authorized else {
//                self.debugPrint("Error saving video: unauthorized access")
                let error = NSError(domain: "Error saving video: unauthorized access", code: 0, userInfo: nil)
                completion(false, error)
                return
            }
            
            // If here, save video to library
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: videoURL)
            }) { success, error in
                if !success {
//                    self.debugPrint("Error saving video: \(error)")
                    completion(false, error as NSError?)
                } else {
                    completion(true, nil)
                }
            }
        }
    }
    
    func videoRecorderAbortedWriting(recorder: VideoRecorder) {
        do {
            try FileManager.default.removeItem(at: self._recordingURL)
        } catch {
            
        }
    }
}

extension Double {
    var f : CGFloat {
        return CGFloat(self)
    }
}

extension Int32 {
    var f : CGFloat {
        return CGFloat(self)
    }
}
