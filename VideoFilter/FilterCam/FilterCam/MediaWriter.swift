//
//  VideoRecorder.swift
//  FilterCam
//
//  Created by Shreesha on 20/02/17.
//  Copyright © 2017 YML. All rights reserved.
//

import Foundation
import AVFoundation
import CoreImage
import CoreFoundation
typealias filterCompletionBlock = (_ savedUrl: URL?, _ error: Error?) -> Void

enum VideoWriterErrorHandler: String, FilterCamErrorHandler {
    case SampleBufferCreateFailed = "Sample buffer create failed"
    case AppendingToAssetWriterFailed = "Appending To Asset Writer Failed"
    case InputIsNotReadyForMediaData = "Input Is Not Ready For Media Data, dropping buffer"
    case InvalidMedia = "Invalid Media"

    var description: String {
        return self.rawValue
    }
}

enum MediaWriterType {
    case video
    case audio
}

class MediaWriter {

    fileprivate var mediaWriter: AVAssetWriter?
    fileprivate var videoWriterInput: AVAssetWriterInput?
    fileprivate var audioWriterInput: AVAssetWriterInput?

    fileprivate var writingPath: URL?
    fileprivate var mediaType: MediaWriterType

    private var pixelBufferAdopter: AVAssetWriterInputPixelBufferAdaptor?

    var isFinishedWritingVideo = true
    var isWritingVideo = false

    var errorCallback: CustomErrorCallback?

    init(_mediaType: MediaWriterType) {
        mediaType = _mediaType
    }

    func applyFilter(_ filter: CIFilter?, toVideo: AVAsset, atUrl: URL, completion: @escaping filterCompletionBlock, failed: () -> Void) {

        let videoComposition = AVVideoComposition(asset: toVideo) { (request) in
            let sourceImage = request.sourceImage
            filter?.setValue(sourceImage, forKey: kCIInputImageKey)

            let outputImage = filter?.outputImage?.cropping(to: sourceImage.extent)
            if let returnImage = outputImage {
                request.finish(with: returnImage, context: nil)
            } else {
                let error = NSError(domain: "Could not apply filter", code: 13, userInfo: nil)
                request.finish(with: error as Error)
            }
        }

        writingPath = atUrl
        finishWritingFilteredVideo(asset: toVideo, composition: videoComposition, path: atUrl, completion: completion)
    }

    //WARNING: Move this to filterManager
    func finishWritingFilteredVideo(asset: AVAsset, composition: AVVideoComposition, path: URL, completion: @escaping filterCompletionBlock) {
        let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetMediumQuality)
        exportSession?.outputURL = path
        exportSession?.videoComposition = composition
        exportSession?.outputFileType = AVFileTypeQuickTimeMovie
        exportSession?.exportAsynchronously {
            let error = exportSession?.error
            completion(path, error)
        }
    }

    func appendVideoPixelBuffer(_ pixelBuffer: CVPixelBuffer, withPresentationTime presentationTime: CMTime, formatDescription: CMFormatDescription) {

        if mediaType == .video {

            var sampleBuffer: CMSampleBuffer? = nil

            var timingInfo: CMSampleTimingInfo = CMSampleTimingInfo()
            timingInfo.duration = kCMTimeInvalid
            timingInfo.decodeTimeStamp = kCMTimeInvalid
            timingInfo.presentationTimeStamp = presentationTime

            let err = CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault, pixelBuffer, true, nil, nil, formatDescription, &timingInfo, &sampleBuffer)

            if let _sampleBuffer = sampleBuffer {
                self.appendSampleBuffer(_sampleBuffer, ofMediaType: AVMediaTypeVideo, atTime: presentationTime)
            } else {
                let exceptionReason = "sample buffer create failed (\(err)): \(errorFor(status: err))"
                let error = NSError(domain: exceptionReason, code: err.l, userInfo: nil)
                errorCallback?(error, VideoWriterErrorHandler.AppendingToAssetWriterFailed)
            }
        }
    }

    func appendSampleBuffer(_ sampleBuffer: CMSampleBuffer, ofMediaType mediaType: String, atTime time: CMTime) {

        if !isWritingVideo {
            let success = mediaWriter?.startWriting()

            mediaWriter?.startSession(atSourceTime: time)

            if let success = success, !success {
                mediaWriter?.cancelWriting()
            }

            isWritingVideo = success ?? false
        }

        if self.isWritingVideo {
            if mediaType == AVMediaTypeVideo {
                let input = self.videoWriterInput
                if input?.isReadyForMoreMediaData ?? false {
                    let success = input!.append(sampleBuffer)
                    if !success {
                        let error = self.mediaWriter?.error
                        errorCallback?(error, VideoWriterErrorHandler.AppendingToAssetWriterFailed)
                    }
                } else {
                    errorCallback?(nil, VideoWriterErrorHandler.InputIsNotReadyForMediaData)
                }
            } else {
                let input = self.audioWriterInput
                print(time)
                if input?.isReadyForMoreMediaData ?? false {
                    let success = input!.append(sampleBuffer)
                    if !success {
                        let error = self.mediaWriter?.error
                        errorCallback?(error, VideoWriterErrorHandler.AppendingToAssetWriterFailed)
                    }
                } else {
                    errorCallback?(nil, VideoWriterErrorHandler.InputIsNotReadyForMediaData)
                }
            }
        }
    }

    func abortWriting() {
        mediaWriter?.cancelWriting()
        _ = LibraryUtils.discardFileAt(url: writingPath!)
    }

    func finishWritingVideo(completion: @escaping filterCompletionBlock) {
        if isWritingVideo {
            guard let videoWriter = mediaWriter else {
                let error = NSError(domain: "Did not initialize properly", code: 2001, userInfo: nil)
                completion(writingPath, error)
                return
            }

            if videoWriter.status == .writing {
                videoWriterInput?.markAsFinished()
                audioWriterInput?.markAsFinished()

                mediaWriter?.finishWriting {
                    completion(self.writingPath, nil)
                }
            } else {
                let error = NSError(domain: "Not writing the media", code: 2002, userInfo: nil)
                completion(writingPath, error)
            }
        } else {
            let error = NSError(domain: "Not writing the media", code: 2002, userInfo: nil)
            completion(writingPath, error)
        }
        
        isWritingVideo = false
    }

    func initializeVideoWriter(_ atUrl: URL, size: CGSize = CGSize.zero, transform: CGAffineTransform = CGAffineTransform.identity, settings: [String: AnyObject]) {
        mediaWriter = createAssetWriter(atUrl, transform: transform, settings: settings)
        writingPath = atUrl

        if mediaType == .video {
            let sourceBufferAttributes : [String : AnyObject] = [
                kCVPixelBufferPixelFormatTypeKey as String : Int(kCVPixelFormatType_32ARGB) as AnyObject,
                kCVPixelBufferWidthKey as String : size.width as AnyObject,
                kCVPixelBufferHeightKey as String : size.height as AnyObject,
                ]
            if let assetWriterVideoInput = videoWriterInput {
                pixelBufferAdopter = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: assetWriterVideoInput, sourcePixelBufferAttributes: sourceBufferAttributes)
            }
        }
    }

    func createAssetWriter(_ atUrl: URL, transform: CGAffineTransform, settings: [String: AnyObject]) -> AVAssetWriter? {
        let pathURL = atUrl
        var writer: AVAssetWriter!

        if mediaType == .video {
            do {

                writer = try AVAssetWriter(outputURL: pathURL, fileType: AVFileTypeMPEG4)

                let videoSettings = settings

                //WARNING: add the transaform also
                videoWriterInput = AVAssetWriterInput(mediaType: AVMediaTypeVideo, outputSettings: videoSettings)
                videoWriterInput?.transform = transform

                videoWriterInput?.expectsMediaDataInRealTime = true
                if writer.canAdd(videoWriterInput!) {
                    writer.add(videoWriterInput!)
                }

            } catch _ {
            }
        } else {
            do {

                writer = try AVAssetWriter(outputURL: pathURL, fileType: AVFileTypeCoreAudioFormat)

                let audioSettings = settings

                //WARNING: add the transaform also
                audioWriterInput = AVAssetWriterInput(mediaType: AVMediaTypeAudio, outputSettings: audioSettings)
                audioWriterInput?.expectsMediaDataInRealTime = true
                if writer.canAdd(audioWriterInput!) {
                    writer.add(audioWriterInput!)
                }
            } catch _ {
            }
        }
        return writer
    }
}

extension CIImage {
    convenience init(buffer: CMSampleBuffer) {
        self.init(cvPixelBuffer: CMSampleBufferGetImageBuffer(buffer)!)
    }
}

extension CGRect {
    var center: CGPoint {
        return CGPoint(x: midX, y: midY)
    }
}


func errorFor(status: OSStatus) -> String {
    switch (status) {
    case kAudioFileUnspecifiedError:
        return "kAudioFileUnspecifiedError";

    case kAudioFileUnsupportedFileTypeError:
        return "kAudioFileUnsupportedFileTypeError";

    case kAudioFileUnsupportedDataFormatError:
        return "kAudioFileUnsupportedDataFormatError";

    case kAudioFileUnsupportedPropertyError:
        return "kAudioFileUnsupportedPropertyError";

    case kAudioFileBadPropertySizeError:
        return "kAudioFileBadPropertySizeError";

    case kAudioFilePermissionsError:
        return "kAudioFilePermissionsError";

    case kAudioFileNotOptimizedError:
        return "kAudioFileNotOptimizedError";

    case kAudioFileInvalidChunkError:
        return "kAudioFileInvalidChunkError";

    case kAudioFileDoesNotAllow64BitDataSizeError:
        return "kAudioFileDoesNotAllow64BitDataSizeError";

    case kAudioFileInvalidPacketOffsetError:
        return "kAudioFileInvalidPacketOffsetError";

    case kAudioFileInvalidFileError:
        return "kAudioFileInvalidFileError";

    case kAudioFileOperationNotSupportedError:
        return "kAudioFileOperationNotSupportedError";

    case kAudioFileNotOpenError:
        return "kAudioFileNotOpenError";

    case kAudioFileEndOfFileError:
        return "kAudioFileEndOfFileError";

    case kAudioFilePositionError:
        return "kAudioFilePositionError";

    case kAudioFileFileNotFoundError:
        return "kAudioFileFileNotFoundError";

    case kCMSampleBufferError_InvalidMediaFormat:
        return "kCMSampleBufferError_InvalidMediaFormat"
    default:
        return "unknown error";
    }
}
