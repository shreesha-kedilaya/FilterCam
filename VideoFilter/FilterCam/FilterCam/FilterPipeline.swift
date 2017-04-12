//
//  FilterManager.swift
//  FilterCam
//
//  Created by Shreesha on 23/02/17.
//  Copyright © 2017 YML. All rights reserved.
//

import Foundation
import CoreImage
import AVFoundation
import CoreMedia
import UIKit
import CoreImage


typealias CustomErrorCallback = ((Error?, FilterCamErrorHandler?) -> Void)

protocol FilterCamErrorHandler: Error, CustomStringConvertible {

}

enum FilteringType: Int {
    case live = 0
    case onVideo
}

protocol FilterResidueDelegate: class {
    var filter: CIFilter? {get set}

    func didCopySampleBuffer(buffer: CVPixelBuffer?)
}

class CoreImageContextHandler {
    var coreImageContext: CIContext!

    init() {

        let eaglContext = EAGLContext(api: .openGLES2)
        EAGLContext.setCurrent(eaglContext)
        coreImageContext = CIContext(eaglContext: eaglContext!, options: [kCIContextWorkingColorSpace : NSNull()])
    }
}

class FilterPipeline {

    private static var sharedInstance: FilterPipeline? = nil

    class func shared() -> FilterPipeline {
        guard let sharedInstance = sharedInstance else {
            self.sharedInstance = FilterPipeline()
            return self.sharedInstance!
        }

        return sharedInstance
    }

    func reset() {
        outputFormatDescription = nil
    }

    class func reset() {
        sharedInstance = nil
    }

    private var movieBufferHandler: MovieBufferHandler?
    private var videoWriter: MediaWriter?
    private var audioWriter: MediaWriter?

    private (set) var videoFrameRate: CGFloat = 00
    private (set) var previousSecondTimestamps: [CMTime] = []

    private (set) var coreImageContextHandler: CoreImageContextHandler!
    private var currentCMBuffer: CMSampleBuffer?
    private var isCreatingImage = false

    var filterResidueDelegate: MulticastDelegate<FilterResidueDelegate> = MulticastDelegate<FilterResidueDelegate>()
    var filteringType: FilteringType!
    var currentFilter: CIFilter?
    var isRecordingVideo = false
    var filterRenderer: CIFilterRenderer?
    var outputFormatDescription: CMFormatDescription?

    var errorCallback: ((Error?, FilterCamErrorHandler?) -> Void)?
    var shouldWriteAudio = true {
        didSet {
            audioWriter?.abortWriting()
            audioWriter = nil
        }
    }

    private var stitchingUrl: URL!
    private var renderSize = CGSize.zero

    func initializeWith(filterType: FilteringType,
         videoSettings: [AnyHashable: Any] = [(kCVPixelBufferPixelFormatTypeKey as NSString) : NSNumber(value: kCVPixelFormatType_32BGRA as UInt32)],
         cameraSettings: [String: String] = [AVVideoCodecKey:AVVideoCodecJPEG],
         orientation: UIInterfaceOrientation = .portrait) {

        filteringType = filterType

        coreImageContextHandler = CoreImageContextHandler()

        switch filteringType! {
        case .live:
            movieBufferHandler = MovieBufferHandler()
            movieBufferHandler?.videoSettings = videoSettings
            movieBufferHandler?.cameraSettings = cameraSettings
            movieBufferHandler?.changeToVideoOrientation(orientation)
            movieBufferHandler?.resolutionQuality = AVCaptureSessionPresetHigh

            movieBufferHandler?.errorCallBack = { [weak self] (nserror, customError) in
                self?.errorCallback?(nserror, customError)
            }

            movieBufferHandler?.bufferVideoCallBack = { [weak self] (buffer) -> () in
                Async.main {
                    self?.handleOutputBuffer(buffer: buffer)
                }
            }

            movieBufferHandler?.bufferAudioCallback = { [weak self] (buffer) -> () in
                Async.main {
                    self?.handleAudioBuffer(buffer)
                }
            }

            createFilterRenderer()

        case .onVideo: break
        }
    }

    private func createFilterRenderer() {
        filterRenderer = CIFilterRenderer(_coreImageContext: coreImageContextHandler.coreImageContext)
        filterRenderer?.errorCallBack = { [weak self] (nserror, customError) in
            self?.errorCallback?(nserror, customError)
        }
    }

    private func handleOutputBuffer(buffer: CMSampleBuffer) {
        currentCMBuffer = buffer
        guard !isCreatingImage else {
            return
        }
        if let _ = outputFormatDescription {
            renderTheBuffer(sampleBuffer: buffer)
        } else {
            let formatDescription = CMSampleBufferGetFormatDescription(buffer)
            prepareRenderer(formatDescription: formatDescription!)
        }

        //Append the pixel buffer
    }

    private func handleAudioBuffer(_ buffer: CMSampleBuffer) {
        if isRecordingVideo {
            let timestamp = CMSampleBufferGetPresentationTimeStamp(buffer)
            audioWriter?.appendSampleBuffer(buffer, ofMediaType: AVMediaTypeAudio, atTime: timestamp)
        }
    }

    private func renderTheBuffer(sampleBuffer: CMSampleBuffer) {
        var renderedPixelBuffer: CVPixelBuffer? = nil

        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        filterResidueDelegate |> { delegate in
            currentFilter = delegate.filter

            let _renderedPixelBuffer = filterRenderer?.copy(sampleBuffer, withFilter: currentFilter)

            renderedPixelBuffer = _renderedPixelBuffer

            if !(filterResidueDelegate.delegates.count > 1) {
                if let _renderedPixelBuffer = renderedPixelBuffer {
                    if isRecordingVideo {
                        videoWriter?.appendVideoPixelBuffer(_renderedPixelBuffer, withPresentationTime: timestamp, formatDescription: outputFormatDescription!)
                    }
                }
            }

            delegate.didCopySampleBuffer(buffer: _renderedPixelBuffer)
        }


        calculateFramerateAtTimestamp(timestamp)
    }

    private func prepareRenderer(formatDescription: CMFormatDescription) {
        guard let filterRenderer = filterRenderer else {
            createFilterRenderer()
            return
        }

        filterRenderer.prepareForInputWith(formatDescription, maximumRetainedBuffer: 6)
        outputFormatDescription = filterRenderer.outputFormatDescription
    }

    private func calculateFramerateAtTimestamp(_ timestamp: CMTime) {
        previousSecondTimestamps.append(timestamp)

        let oneSecond = CMTimeMake(1, 1)
        let oneSecondAgo = CMTimeSubtract(timestamp, oneSecond)

        while previousSecondTimestamps[0] < oneSecondAgo {
            previousSecondTimestamps.remove(at: 0)
        }

        if previousSecondTimestamps.count > 1 {
            let duration: Double = CMTimeGetSeconds(CMTimeSubtract(previousSecondTimestamps.last!, previousSecondTimestamps[0]))
            let newRate = CGFloat(previousSecondTimestamps.count - 1) / CGFloat(duration.f)
            videoFrameRate = newRate
        }
    }

    func changeVideoOrientation(_ orientation: UIInterfaceOrientation) {
        movieBufferHandler?.changeToVideoOrientation(orientation)
    }

    func changeCameraSettingsTo(settings: [String: String]) {
        movieBufferHandler?.changeCameraSettingsTo(settings: settings)
    }

    func changeVideoSettingsTo(settings: [AnyHashable: Any]) {
        movieBufferHandler?.changeVideoSettingsTo(settings: settings)
    }

    func startRecording(atUrl: URL, size: CGSize, transform: CGAffineTransform, withFilter: CIFilter? = nil) {
        //Intitiate the callback to handle the buffer
        stitchingUrl = atUrl
        let size = CMVideoFormatDescriptionGetDimensions(outputFormatDescription!)
        renderSize = CGSize(width: size.width.g, height: size.height.g)
        switch filteringType! {
        case .live:
            videoWriter = MediaWriter(_mediaType: .video)
            videoWriter?.errorCallback = { [weak self] (nserror, customError) in
                self?.errorCallback?(nserror, customError)
            }

            currentFilter = withFilter ?? currentFilter
            let videoUrl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("FilterCamVideo" + "\(Date().timeIntervalSince1970)" + ".mov")
            let videoSettings: [String : AnyObject] = [
                AVVideoCodecKey  : AVVideoCodecH264 as AnyObject,
                AVVideoWidthKey  : size.width as AnyObject,
                AVVideoHeightKey : size.height as AnyObject,
                ]
            videoWriter?.initializeVideoWriter(videoUrl, size: renderSize, transform: transform, settings: videoSettings)

            if shouldWriteAudio {
                let audioUrl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("FilterCamAudio" + "\(Date().timeIntervalSince1970)" + ".wav")
                audioWriter = MediaWriter(_mediaType: .audio)
                audioWriter?.errorCallback = { [weak self] (nserror, customError) in
                    self?.errorCallback?(nserror, customError)
                }
                let settings2 = movieBufferHandler?.recomendedSettingsForAssetWriter()
                audioWriter?.initializeVideoWriter(audioUrl,settings: settings2!)
            }

            isRecordingVideo = true
        case .onVideo:
            return
        }
    }

    func applyFilter(_ filter: CIFilter?, toVideo video: AVAsset, atUrl url: URL, completion: @escaping filterCompletionBlock, failed: () -> Void) {
        switch filteringType! {
        case .live:
            failed()
            return
        case .onVideo:
            videoWriter = MediaWriter(_mediaType: .video)
            currentFilter = filter ?? currentFilter
            videoWriter?.applyFilter(filter, toVideo: video, atUrl: url, completion: completion, failed: failed)
        }
    }

    func startCameraSession() {
        movieBufferHandler?.startSession()
    }

    func stopCameraSession() {
        movieBufferHandler?.stopSession()
        movieBufferHandler?.removeObservers()
    }

    func changeDevicePositionTo(position: AVCaptureDevicePosition) {
        movieBufferHandler?.changeDeviceTypeTo(position: position)
        outputFormatDescription = nil
    }

    func capturedImage(withFilter: CIFilter?, completion: @escaping (UIImage?) -> Void) {

        guard let filter = withFilter else {
            movieBufferHandler?.captureImage(withFilter: withFilter, callBack: { (image) in
                completion(image)
            })
            return
        }

        if filter.name.lowercased().contains("distortion") {
            let image = getCurrentImage()
            FilterGenerator.filteredImageFor(buffer: nil, filter: withFilter, image: image, completion: completion)
        } else {
            movieBufferHandler?.captureImage(withFilter: withFilter, callBack: { (image) in
                completion(image)
            })
        }
    }

    func stopRecording(completion: @escaping filterCompletionBlock) {
        isRecordingVideo = false

        switch filteringType! {
        case .live:
            var audioUrl: URL?
            var videoUrl: URL?
            videoWriter?.finishWritingVideo(completion: { (url, error) in
                if error == nil {
                    videoUrl = url!
                }
                if self.shouldWriteAudio == false {
                    completion(url, error)
                } else {
                    self.audioWriter?.finishWritingVideo(completion: { (url, error) in
                        if error == nil {
                            audioUrl = url!
                            if let _audioUrl = audioUrl, let _videoUrl = videoUrl {
                                let stitcher = MediaStitch()
                                stitcher.mergeFilesWithUrl(videoUrl: _videoUrl, audioUrl: _audioUrl, renderSize: self.renderSize, savingUrl: self.stitchingUrl, completion: completion)
                            }
                        }
                    })
                }
            })
            
            //Stitch the video and audio

        case .onVideo:
            return
        }
    }

    func getCurrentImage() -> UIImage? {
        isCreatingImage = true
        if let currentCMBuffer = currentCMBuffer {
            let ciimage = CIImage(buffer: currentCMBuffer)
            isCreatingImage = false
            if let cgImage = coreImageContextHandler.coreImageContext.createCGImage(ciimage, from: ciimage.extent) {
                return UIImage(cgImage: cgImage)
            }

            return nil
        } else {
            return getCurrentImage()
        }
    }

    func transform(withMirroring: Bool = false) -> CGAffineTransform {
        return movieBufferHandler?.transform(withMirroring: withMirroring) ?? CGAffineTransform.identity
    }

    func abortRecording() {
        videoWriter?.abortWriting()
        audioWriter?.abortWriting()
    }
}
