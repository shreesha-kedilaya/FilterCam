//
//  VideoRecorder.swift
//  FilterCam
//
//  Created by Shreesha on 21/11/16.
//  Copyright © 2016 YML. All rights reserved.
//

import Foundation
import CoreImage
import AVFoundation
import Photos

private enum MovieRecorderStatus: Int {
    case idle = 0
    case preparingToRecord
    case recording
    // waiting for inflight buffers to be appended
    case finishingRecordingPart1
    // calling finish writing on the asset writer
    case finishingRecordingPart2
    // terminal state
    case finished
    // terminal state
    case failed
    
    case aborted
}   // internal state machine


protocol VideoRecorderDelegate: class {
    func videoRecorderDidFinishPreparing(_ recorder: VideoRecorder)
    func videoRecorder(_ recorder: VideoRecorder, didFailWithError error: NSError)
    func videoRecorderDidFinishRecording(_ recorder: VideoRecorder)
    func videoRecorderAbortedWriting(recorder: VideoRecorder)
}

class VideoRecorder: NSObject{
    fileprivate var assetWriter: AVAssetWriter?
    fileprivate var assetWriterVideoInput: AVAssetWriterInput?
    fileprivate var pixelBufferAdopter: AVAssetWriterInputPixelBufferAdaptor?
    private var _status = RosyWriterRecordingStatus.idle
    private var URL: URL
    private var status = MovieRecorderStatus.idle
    private var haveStartedSession = false
    
    var pixelFormat: OSType?
    var size: CGSize?
    fileprivate var writingQueue: DispatchQueue?
    var videoCreationType = CreationType.fromSeparateImages
    
    private var _videoTrackSourceFormatDescription: CMFormatDescription?
    fileprivate var _videoTrackTransform: CGAffineTransform?
    fileprivate var _videoTrackSettings: [String: AnyObject] = [:]
    
    weak var delegate: VideoRecorderDelegate?
    fileprivate var delegateCallBackQueue: DispatchQueue?

    deinit {
        self.teardownAssetWriterAndInputs()
    }
    
    func startVideoTrackWith(_ formatDescription: CMFormatDescription, transform: CGAffineTransform, settings videoSettings: [String : AnyObject]) {
        
        let lockQueue = DispatchQueue(label: "Main queue")
        lockQueue.sync() {
            
            if _status != .idle {
                fatalError("Cannot add tracks while not idle")
            }
            
            if _videoTrackSourceFormatDescription != nil {
                fatalError("Cannot add more than one video track")
            }
            
            self._videoTrackSourceFormatDescription = formatDescription
            self._videoTrackTransform = transform
            self._videoTrackSettings = videoSettings
        }
    }
    
    //WARNING: fill this out
    init(URL: URL) {
        self.writingQueue = DispatchQueue(label: "writing queue")
        _videoTrackTransform = CGAffineTransform.identity
        self.URL = URL
        super.init()
    }
    
    //WARNING: Give a delegate queue back.
    
    func setDelegate(_ delegate: VideoRecorderDelegate?, callBackQueue: DispatchQueue) {
        self.delegate = delegate
        self.delegateCallBackQueue = callBackQueue
    }
    
    func prepareToRecord() {
        
        if _status != .idle {
            fatalError("Already prepared, cannot prepare again")
        }
        
        self.transitionToStatus(.preparingToRecord, error: nil)
        
        Async.global(.background, closer: {
            
            
            autoreleasepool {
                var error: NSError? = nil
                do {
                    // AVAssetWriter will not write over an existing file.
                    try FileManager.default.removeItem(at: self.URL)
                } catch _ {
                }
                
                do {
                    self.assetWriter = try AVAssetWriter(outputURL: self.URL, fileType: AVFileTypeQuickTimeMovie)
                } catch let error1 as NSError {
                    error = error1
                    self.assetWriter = nil
                } catch {
                    fatalError()
                }
                
                // Create and add inputs
                if error == nil && self._videoTrackSourceFormatDescription != nil {
                    do {
                        try self.setupAssetWriterVideoInputWithSourceFormatDescription(self._videoTrackSourceFormatDescription, transform: self._videoTrackTransform!, settings: self._videoTrackSettings)
                    } catch let error1 as NSError {
                        error = error1
                    } catch {
                        fatalError()
                    }
                }
                
                if error == nil {
                    let success = self.assetWriter?.startWriting() ?? false
                    if success {
                        error = self.assetWriter?.error as NSError?
                    }
                }
                
                if error != nil {
                    self.transitionToStatus(.failed, error: error)
                } else {
                    self.transitionToStatus(.recording, error: nil)
                }
            }
        })
    }
    
    
    fileprivate func setupAssetWriterVideoInputWithSourceFormatDescription(_ videoFormatDescription: CMFormatDescription?, transform: CGAffineTransform, settings _videoSettings: [String: AnyObject]) throws {
        var videoSettings = _videoSettings
        if videoSettings.isEmpty {
            var bitsPerPixel: Float
            let dimensions = CMVideoFormatDescriptionGetDimensions(videoFormatDescription!)
            let numPixels = dimensions.width * dimensions.height
            var bitsPerSecond: Int
            
            NSLog("No video settings provided, using default settings")
            
            // Assume that lower-than-SD resolutions are intended for streaming, and use a lower bitrate
            if numPixels < 640 * 480 {
                bitsPerPixel = 4.05; // This bitrate approximately matches the quality produced by AVCaptureSessionPresetMedium or Low.
            } else {
                bitsPerPixel = 10.1; // This bitrate approximately matches the quality produced by AVCaptureSessionPresetHigh.
            }
            
            bitsPerSecond = Int(numPixels.f * CGFloat(bitsPerPixel))
            
            let compressionProperties: NSDictionary = [AVVideoAverageBitRateKey : bitsPerSecond,
                                                       AVVideoExpectedSourceFrameRateKey : 30,
                                                       AVVideoMaxKeyFrameIntervalKey : 30]
            
            videoSettings = [AVVideoCodecKey : AVVideoCodecH264 as AnyObject,
                             AVVideoWidthKey : dimensions.width.n,
                             AVVideoHeightKey : dimensions.height.n,
                             AVVideoCompressionPropertiesKey : compressionProperties]
        }
        
        if assetWriter?.canApply(outputSettings: videoSettings, forMediaType: AVMediaTypeVideo) ?? false {
            assetWriterVideoInput = AVAssetWriterInput(mediaType: AVMediaTypeVideo, outputSettings: videoSettings, sourceFormatHint: videoFormatDescription)
            assetWriterVideoInput?.expectsMediaDataInRealTime = true
            assetWriterVideoInput?.transform = transform
            
            if assetWriter?.canAdd(assetWriterVideoInput!) ?? false {
                assetWriter?.add(assetWriterVideoInput!)
            } else {
                let error = NSError(domain: "CannotSetup", code: 0, userInfo: nil)
                throw error
            }
        } else {
            let error = NSError(domain: "CannotSetup", code: 0, userInfo: nil)
            throw error
        }
    }
    
    func appendVideoPixelBuffer(_ pixelBuffer: CVPixelBuffer, withPresentationTime presentationTime: CMTime) {
        var sampleBuffer: CMSampleBuffer? = nil
        
        var timingInfo: CMSampleTimingInfo = CMSampleTimingInfo()
        timingInfo.duration = kCMTimeInvalid
        timingInfo.decodeTimeStamp = kCMTimeInvalid
        timingInfo.presentationTimeStamp = presentationTime
        
        let err = CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault, pixelBuffer, true, nil, nil, _videoTrackSourceFormatDescription!, &timingInfo, &sampleBuffer)
        if sampleBuffer != nil {
            self.appendSampleBuffer(sampleBuffer!, ofMediaType: AVMediaTypeVideo)
        } else {
            let exceptionReason = "sample buffer create failed (\(err))"
            fatalError(exceptionReason)
        }
    }
    
    fileprivate func appendSampleBuffer(_ sampleBuffer: CMSampleBuffer, ofMediaType mediaType: String) {
        
        if _status.rawValue < MovieRecorderStatus.recording.rawValue {
            fatalError("Not ready to record yet")
        }
        
        writingQueue?.async {
            
            autoreleasepool {
                // From the client's perspective the movie recorder can asynchronously transition to an error state as the result of an append.
                // Because of this we are lenient when samples are appended and we are no longer recording.
                // Instead of throwing an exception we just release the sample buffers and return.
                if self._status.rawValue > MovieRecorderStatus.finishingRecordingPart1.rawValue {
                    return
                }
                
                if !self.haveStartedSession {
                    self.assetWriter?.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
                    self.haveStartedSession = true
                }
                
                let input = self.assetWriterVideoInput
                
                if input?.isReadyForMoreMediaData ?? false {
                    let success = input!.append(sampleBuffer)
                    if !success {
                        let error = self.assetWriter?.error
                        self.transitionToStatus(.failed, error: error as NSError?)
                    }
                } else {
                    NSLog("%@ input not ready for more media data, dropping buffer", mediaType)
                }
            }
        }
    }
    
    fileprivate func transitionToStatus(_ newStatus: MovieRecorderStatus, error: NSError?) {
        var shouldNotifyDelegate = false
        
        if newStatus != status {
            // terminal states
            if newStatus == .finished || newStatus == .failed {
                shouldNotifyDelegate = true
                // make sure there are no more sample buffers in flight before we tear down the asset writer and inputs
                
                writingQueue?.async {
                    self.teardownAssetWriterAndInputs()
                    if newStatus == .failed {
                        do {
                            try FileManager.default.removeItem(at: self.URL)
                        } catch _ {
                        }
                    }
                }
                
            } else if newStatus == .recording {
                shouldNotifyDelegate = true
            }
            
            status = newStatus
        }
        
        if shouldNotifyDelegate && self.delegate != nil {
            delegateCallBackQueue?.async {
                autoreleasepool {
                    switch newStatus {
                    case .recording:
                        self.delegate?.videoRecorderDidFinishPreparing(self)
                    case .finished:
                        self.delegate?.videoRecorderDidFinishRecording(self)
                    case .failed:
                        self.delegate?.videoRecorder(self, didFailWithError: error!)
                    case .aborted:
                        self.delegate?.videoRecorderAbortedWriting(recorder: self)
                    default:
                        break
                    }
                }
            }
        }
    }
    
    func finishRecording() {
        var shouldFinishRecording = false
        switch status {
        case .idle,
             .preparingToRecord,
             .finishingRecordingPart1,
             .finishingRecordingPart2,
             .finished,
             .aborted:
            fatalError("Not recording")
        case .failed:
            // From the client's perspective the movie recorder can asynchronously transition to an error state as the result of an append.
            // Because of this we are lenient when finishRecording is called and we are in an error state.
            NSLog("Recording has failed, nothing to do")
        case .recording:
            shouldFinishRecording = true
        }
        
        if shouldFinishRecording {
            self.transitionToStatus(.finishingRecordingPart1, error: nil)
        } else {
            return
        }
        
        writingQueue?.async {
            
            autoreleasepool {
                // We may have transitioned to an error state as we appended inflight buffers. In that case there is nothing to do now.
                if self.status != .finishingRecordingPart1 {
                    return
                }
                
                // It is not safe to call -[AVAssetWriter finishWriting*] concurrently with -[AVAssetWriterInput appendSampleBuffer:]
                // We transition to MovieRecorderStatusFinishingRecordingPart2 while on _writingQueue, which guarantees that no more buffers will be appended.
                self.transitionToStatus(.finishingRecordingPart2, error: nil)
            }
            
            self.assetWriter?.finishWriting {
                let error = self.assetWriter?.error
                if error != nil {
                    self.transitionToStatus(.failed, error: error as NSError?)
                } else {
                    self.transitionToStatus(.finished, error: nil)
                }
            }
        }
    }
    
    func abortWriting() {
        assetWriter?.cancelWriting()
        self.transitionToStatus(.aborted, error: nil)   
    }
    
    fileprivate func teardownAssetWriterAndInputs() {
        assetWriterVideoInput = nil
        assetWriter = nil
    }
}
//FourCharCode
extension UInt32 {
    public var n: NSNumber {
        return NSNumber(value: self as UInt32)
    }
}

extension Int32 {
    public var n: NSNumber {
        return NSNumber(value: self as Int32)
    }
}

