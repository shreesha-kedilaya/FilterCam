//
//  VideoCreator.swift
//  FilterCam
//
//  Created by Shreesha on 16/09/16.
//  Copyright © 2016 YML. All rights reserved.
//

import Foundation
import CoreImage
import AVFoundation
import UIKit
import Photos

enum CreationType {
    case fromVideo
    case fromSeparateImages
}

let ciFilter = CIFilter(name: "CIGaussianBlur")

class VideoCreator: NSObject {

    fileprivate var assetWriter: AVAssetWriter?
    fileprivate var assetWriterVideoInput: AVAssetWriterInput?
    fileprivate var pixelBufferAdopter: AVAssetWriterInputPixelBufferAdaptor?
    private var videoBufferHandler: VideoBufferHandler?

    fileprivate var writingPath: String?
    fileprivate var videoFPS: Int32 = 25
    fileprivate var frameDuration: CMTime!
    private var filter: Filter
    private var coreImageContext: CIContext?
    
    private var _status = RosyWriterRecordingStatus.idle

    var pixelFormat: OSType?
    var size: CGSize?
    var writingQueue: DispatchQueue?
    var videoCreationType = CreationType.fromSeparateImages
    
    private var _videoTrackSourceFormatDescription: CMFormatDescription?
    fileprivate var _videoTrackTransform: CGAffineTransform?
    fileprivate var _videoTrackSettings: [String: AnyObject] = [:]

    fileprivate (set) var sessionRunning = false
    fileprivate (set) var numberOfFrames = 0

    func applyFilterTo(_ video: AVAsset, inrect rect: CGRect,videoFPS: Int32, size: CGSize, filter: @escaping Filter, savingUrl: String, completion: @escaping (_ savedUrl: URL) -> ()) {

        startWrting(atPath: savingUrl, size: size, videoFPS: videoFPS)

        let duration = video.duration

        let imageGenerator = AVAssetImageGenerator(asset: video)
        var times = [NSValue]()

        let reader = try! AVAssetReader(asset: video)
        let videoTrack = video.tracks(withMediaType: AVMediaTypeVideo)[0]

        let readerOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: nil) // NB: nil, should give you raw frames
        reader.add(readerOutput)
        reader.startReading()

        var nFrames = 0

        while true {
            let sampleBuffer = readerOutput.copyNextSampleBuffer()
            if sampleBuffer == nil {
                break
            }
            
            nFrames += 1
        }

        if #available(iOS 9.0, *) {
            let composition = AVVideoComposition(asset: video) { request in
            }
        } else {

        }

        let videoFPS: Double = Double(nFrames) / CMTimeGetSeconds(duration)
        let frameTime: Double = 1.0 / Double(videoFPS)

        self.numberOfFrames = nFrames
        self.videoFPS = Int32(videoFPS)

        for frameCount in 0...nFrames {

            let time = NSNumber(value: Double(frameCount) * Double(frameTime))
            let lastFrameTime = CMTimeMake(Int64(frameCount), Int32(videoFPS))
            let presentationTime = frameCount == 0 ? lastFrameTime : CMTimeAdd(lastFrameTime, CMTimeMake(1, Int32(videoFPS)))
            times.append(CMTimeGetSeconds(presentationTime) as NSValue)
            
//            let lastFrameTime = CMTimeMake(Int64(self.numberOfFrames), self.videoFPS)
//            let presentationTime = self.numberOfFrames == 0 ? lastFrameTime : CMTimeAdd(lastFrameTime, self.frameDuration)
        }

//        print(times)
        var discardedImage = 0
        var nuOfImagesGenerated = 0

                    imageGenerator.generateCGImagesAsynchronously(forTimes: times, completionHandler: { (requestedTime, image, generatedTime, result, error) in
                        nuOfImagesGenerated += 1
                        if let error = error {
                            print("Some error happened while generating the image at time \(generatedTime) with error: \(error)")
                            discardedImage += 1
                        } else {
                            switch result {
                            case .succeeded:
//                                print("Succeeded generating the image at time \(generatedTime)")

                                if let image = image {
                                    let ciimage = CIImage(cgImage: image)
                                    let filteredImage = filter(ciimage)
                                    if let filteredImage = filteredImage {
//                                        let cgimage = self.coreImageContext?.createCGImage(filteredImage, from: filteredImage.extent)
//                                        if let ciimage = ciimage {

                                            self.appendImage(ciimage, inrect: rect, completion: { (numberOfFrames) in
                                            })
//                                        }

                                    } else {
                                        let cgimage = self.coreImageContext?.createCGImage(ciimage, from: ciimage.extent)
                                        if let cgimage = cgimage {
                                            self.appendImage(ciimage, inrect: rect, completion: { (numberOfFrames) in
                                            })
                                        }
                                    }
                                }
        
                            case .failed:
                                discardedImage += 1
                                print("Failed generating the image at time \(generatedTime)")
                            case .cancelled:
                                discardedImage += 1
                                print("Cancelled while generating the image at time \(generatedTime)")
                            }
        
                            if (nuOfImagesGenerated - discardedImage) == nFrames - 2 {
                                self.stopWriting({ (url) in
                                    completion(url)
                                })
                            }
        
                        }
                    })

        
//        for frameCount in 0..<nFrames {
//            
//            if frameCount == nFrames - 1 {
//                self.stopWriting({ (savedUrl) in
//                    completion(savedUrl)
//                })
//            }
//            
//            
//            do {
//                let image = try? imageGenerator.copyCGImage(at: CMTime(seconds: Double(frameCount.d * frameTime), preferredTimescale: Int32(videoFPS)), actualTime: nil)
//                
//                if let image = image {
//                    let ciimage = CIImage(cgImage: image)
//                    let filteredImage = filter(ciimage)
//                    if let filteredImage = filteredImage {
//                        let cgimage = self.coreImageContext?.createCGImage(filteredImage, from: CGRect(x: 0, y: 0, width: image.width, height: image.height))
//                        if let cgimage = cgimage {
//                            self.appendImage(cgimage, inrect: rect, completion: { (numberOfFrames) in
//                            })
//                        }
//                    } else {
//                        let cgimage = self.coreImageContext?.createCGImage(ciimage, from: ciimage.extent)
//                        if let cgimage = cgimage {
//                            self.appendImage(cgimage, inrect: rect, completion: { (numberOfFrames) in
//                            })
//                        }
//                    }
//                }
//            }
//        }
    }

    //TODO: Add endSessionAtSourceTime(_:_)
    func abortWriting() {
        assetWriter?.cancelWriting()
    }

    func startWrting(atPath path: String, size: CGSize, videoFPS: Int32) {
        self.size = size
        writingPath = path
        assetWriter = createAssetWriter(writingPath ?? "", size: size)
        self.videoFPS = videoFPS
        frameDuration = CMTimeMake(1, videoFPS)
        let eaglContext = EAGLContext(api: .openGLES2)
        coreImageContext = CIContext(eaglContext: eaglContext!)

        let sourceBufferAttributes : [String : AnyObject] = [
            kCVPixelBufferPixelFormatTypeKey as String : Int(pixelFormat ?? kCVPixelFormatType_32ARGB) as AnyObject,
            kCVPixelBufferWidthKey as String : size.width as AnyObject,
            kCVPixelBufferHeightKey as String : size.height as AnyObject,
            ]
        if let assetWriterVideoInput = assetWriterVideoInput {
            pixelBufferAdopter = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: assetWriterVideoInput, sourcePixelBufferAttributes: sourceBufferAttributes)
        }

        let success = assetWriter?.startWriting()

        assetWriter?.startSession(atSourceTime: kCMTimeZero)

        if let success = success, !success {
            assetWriter?.cancelWriting()
        }

        debugPrint("started to write to path \(path)")

        sessionRunning = true
    }

    init(_ filter: @escaping Filter) {
        self.filter = filter
        super.init()
    }

    //MARK: This method to be used when there is only 'CMSampleBuffer' to append with.
    //Avoid this method as far as possible.
    func appendSampleBuffer(_ sampleBuffer: CMSampleBuffer, transform: CGAffineTransform, rect: CGRect, completion: @escaping (_ numberOfFrames: Int) -> ()) {
        //let ciimage = CIImage(buffer: sampleBuffer).applying(transform)

        //let cgimage = coreImageContext?.createCGImage(ciimage, from: rect)

        /*if let cgimage = cgimage {
            /*appendImage(cgimage) { (numberOfFrames) in
                completion(numberOfFrames)
            }*/
        }*/
    }


    func saveVideoToLibrary(_ videoURL: URL) {
        PHPhotoLibrary.requestAuthorization { status in
            // Return if unauthorized
            guard status == .authorized else {
                self.debugPrint("Error saving video: unauthorized access")
                return
            }

            // If here, save video to library
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: videoURL)
            }) { success, error in
                if !success {
                    self.debugPrint("Error saving video: \(error)")
                }
            }
        }
    }

    func appendImage(_ image: CIImage, inrect rect: CGRect, completion: @escaping (_ numberOfFrames: Int) -> ()) {
        guard let assetWriterVideoInput = assetWriterVideoInput else {
            return
        }

        let lastFrameTime = CMTimeMake(Int64(self.numberOfFrames), self.videoFPS)
        let presentationTime = self.numberOfFrames == 0 ? lastFrameTime : CMTimeAdd(lastFrameTime, self.frameDuration)

        printTheStatusOfAssetWriter()

//        assetWriter?.startSession(atSourceTime: presentationTime)

        if assetWriterVideoInput.isReadyForMoreMediaData {
            if !self.appendPixelBufferForImageAtURL(image, pixelBufferAdaptor: self.pixelBufferAdopter!, presentationTime: presentationTime, inrect: rect) {
                self.debugPrint("Error converting images to video: AVAssetWriterInputPixelBufferAdapter failed to append pixel buffer")
                return
            }
            self.debugPrint("appended the pixel buffer at time \(presentationTime)")
            self.numberOfFrames += 1
            completion(self.numberOfFrames)
        }
    }

    private func printTheStatusOfAssetWriter() {
//        if let assetWriter = assetWriter {
//            switch assetWriter.status {
//            case .unknown:
//                print("Asset writer status: Unknown")
//            case .writing:
//                print("Asset writer status: Writing")
//            case .completed:
//                print("Asset writer status: Completed")
//            case .failed:
//                print("Asset writer status: Failed")
//            case .cancelled:
//                print("Asset writer status: Cancelled")
//            }
//        }

    }
    
    // Only one audio and video track each are allowed.
    // see AVVideoSettings.h for settings keys/values
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
    

    func appendVideoPixelBuffer(_ pixelBuffer: CVPixelBuffer, withPresentationTime presentationTime: CMTime) {
        var sampleBuffer: CMSampleBuffer? = nil

        var timingInfo: CMSampleTimingInfo = CMSampleTimingInfo()
        timingInfo.duration = kCMTimeInvalid
        timingInfo.decodeTimeStamp = kCMTimeInvalid
        timingInfo.presentationTimeStamp = presentationTime

        let err = CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault, pixelBuffer, true, nil, nil, _videoTrackSourceFormatDescription!, &timingInfo, &sampleBuffer)
        if sampleBuffer != nil {
            self.appendSampleBuffer(sampleBuffer: sampleBuffer!, ofMediaType: AVMediaTypeVideo)
        } else {
            let exceptionReason = "sample buffer create failed (\(err))"
            fatalError(exceptionReason)
        }
    }
    
    func appendSampleBuffer(sampleBuffer: CMSampleBuffer, ofMediaType: String) {
        
    }

    func stopWriting(_ completion: @escaping (_ savedUrl: URL) -> Void) {
        if sessionRunning {

            if assetWriter?.status == .writing {
                assetWriterVideoInput?.markAsFinished()
                assetWriter?.finishWriting {
                    self.saveVideoToLibrary(URL(string: self.writingPath!)!)
                    completion(URL(string: self.writingPath!)!)
                }
                debugPrint("stopped writing at path \(self.writingPath)")
                sessionRunning = false
            }
        }
    }

    func createAssetWriter(_ path: String, size: CGSize) -> AVAssetWriter? {
        let pathURL = URL(fileURLWithPath: path)

        do {

            let newWriter = try AVAssetWriter(outputURL: pathURL, fileType: AVFileTypeMPEG4)

            let videoSettings: [String : AnyObject] = [
                AVVideoCodecKey  : AVVideoCodecH264 as AnyObject,
                AVVideoWidthKey  : size.width as AnyObject,
                AVVideoHeightKey : size.height as AnyObject,
                ]

            assetWriterVideoInput = AVAssetWriterInput(mediaType: AVMediaTypeVideo, outputSettings: videoSettings)

            if newWriter.canAdd(assetWriterVideoInput!) {
                newWriter.add(assetWriterVideoInput!)
            }
            assetWriterVideoInput?.expectsMediaDataInRealTime = false

            debugPrint("Created asset writer for \(size.width)x\(size.height) video")
            return newWriter
        } catch {
            debugPrint("Error creating asset writer: \(error)")
            return nil
        }
    }

    func appendPixelBufferForImageAtURL(_ image: CIImage, pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor, presentationTime: CMTime, inrect rect: CGRect) -> Bool {
        var appendSucceeded = false

        if sessionRunning {
            if let assetWriter = assetWriter {
                if assetWriter.status == .writing {
                    if let imageBuffer = pixelBufferFromImage(image: image, pixelBufferAdopter: pixelBufferAdopter!, presentationTime: presentationTime){//pixelBufferFromImage(image, pixelBufferAdopter: pixelBufferAdaptor, presentationTime: presentationTime) {
                        appendSucceeded = pixelBufferAdaptor.append(imageBuffer, withPresentationTime: presentationTime)
                    }
                }
            }
        }

        return appendSucceeded
    }

    func pixelBufferFromImage(_ image: CGImage, pixelBufferAdopter: AVAssetWriterInputPixelBufferAdaptor, presentationTime: CMTime) -> CVPixelBuffer? {

        let options : [NSObject: Any] = [
            "kCVPixelBufferCGImageCompatibilityKey" as NSObject: true,
            "kCVPixelBufferCGBitmapContextCompatibilityKey" as NSObject: true
        ]

        var pixelBufferPointer: UnsafeMutablePointer<CVPixelBuffer?>?

        let width = image.width
        let height = image.height

        var appended = false

        autoreleasepool {
            pixelBufferPointer = UnsafeMutablePointer<CVPixelBuffer?>.allocate(capacity: 1)
            if let pixelBufferPointer = pixelBufferPointer {

                let buffered:CVReturn = CVPixelBufferCreate(kCFAllocatorDefault, width, height, OSType(kCVPixelFormatType_32ARGB), options as CFDictionary? , pixelBufferPointer)

                debugPrint(buffered)

                let lockBaseAddress = CVPixelBufferLockBaseAddress((pixelBufferPointer.pointee)!, CVPixelBufferLockFlags(rawValue: CVOptionFlags(0)))

                debugPrint(lockBaseAddress)

                let pixelData:UnsafeMutableRawPointer = CVPixelBufferGetBaseAddress((pixelBufferPointer.pointee)!)!

                debugPrint(pixelData)

                let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue)
                let space:CGColorSpace = CGColorSpaceCreateDeviceRGB()

                let context = CGContext(data: pixelData, width: width, height: height, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow((pixelBufferPointer.pointee)!), space: space, bitmapInfo: bitmapInfo.rawValue)

                context?.draw(image, in: CGRect(x:0, y:0, width: width, height: height))
                
                CVPixelBufferUnlockBaseAddress((pixelBufferPointer.pointee)!, CVPixelBufferLockFlags(rawValue: CVOptionFlags(0)))

            } else {
                debugPrint("failed to create the pixel buffer pointer")
            }
        }
        let pointee = pixelBufferPointer?.pointee

        pixelBufferPointer?.deinitialize()
        pixelBufferPointer?.deallocate(capacity: 1)

        return pointee
    }

    func debugPrint(_ string: Any){
//        print(string)
    }

    func pixelBufferFromImage(image: CIImage, pixelBufferAdopter: AVAssetWriterInputPixelBufferAdaptor, presentationTime: CMTime) -> CVPixelBuffer? {
        ciFilter?.setValue(image, forKey: kCIInputImageKey)

        var newPixelBuffer: CVPixelBuffer? = nil
        let pixelBufferPool = pixelBufferAdopter.pixelBufferPool

        CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pixelBufferPool!, &newPixelBuffer)

        self.coreImageContext?.render(
            ciFilter!.outputImage!,
            to: newPixelBuffer!,
            bounds: ciFilter!.outputImage!.extent,
            colorSpace: CGColorSpaceCreateDeviceRGB())

        return newPixelBuffer
    }
}

extension CIContext {
    func createCGImage_(image:CIImage, fromRect:CGRect) -> CGImage {
        let width = Int(fromRect.width)
        let height = Int(fromRect.height)

        let rawData =  UnsafeMutablePointer<UInt8>.allocate(capacity: width * height * 4)
        render(image, toBitmap: rawData, rowBytes: width * 4, bounds: fromRect, format: kCIFormatRGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())

        let dataprovide = CGDataProvider(dataInfo: nil, data: rawData, size: height * width * 4) { (info, data, size) in
            info?.deallocate(bytes: 0, alignedTo: 0)
        }
        return CGImage.init(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: dataprovide!, decode: nil, shouldInterpolate: false, intent: CGColorRenderingIntent.defaultIntent)!
    }
}
extension Int {
    var d: Double {
        return Double(self)
    }
}
