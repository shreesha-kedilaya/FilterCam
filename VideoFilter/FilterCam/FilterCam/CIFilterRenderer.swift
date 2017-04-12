//
//  CIFilterRenderer.swift
//  FilterCam
//
//  Created by Shreesha on 01/03/17.
//  Copyright © 2017 YML. All rights reserved.
//

import Foundation
import CoreMedia
import CoreVideo
import CoreImage

enum CIFilterRendererErrorHandler: String, FilterCamErrorHandler {
    case CannotInitializeBuffer = "Cannot Initialize Buffer"
    case CannotCreateBufferPoolWithGivenParams = "Cannot Create Bufferpool With Given Params"
    case CannotCreateTempPixelBuffer = "Cannot Create Temp Pixelbuffer"
    case NoBufferIsCreated = "No Buffer Is Created"
    case PixelBufferRenderingFailedWhileCopying = "Pixelbuffer Rendering Failed While Copying"

    var description: String {
        return self.rawValue
    }
}

class CIFilterRenderer {

    private var mainBufferPool: CVPixelBufferPool?
    private var bufferPoolSettings: NSDictionary = [:]
    var coreImageContext: CIContext

    var colorSpace = CGColorSpaceCreateDeviceRGB()
    var outputFormatDescription: CMFormatDescription?
    var errorCallBack: CustomErrorCallback?

    init(_coreImageContext: CIContext) {
        coreImageContext = _coreImageContext
    }

    func prepareForInputWith(_ formatDescription: CMFormatDescription, maximumRetainedBuffer: Int, pixelFormat: OSType = kCVPixelFormatType_32BGRA) {
        //WARNING: Delete buffers

        reset()
        guard initializeBufferwWith(CMVideoFormatDescriptionGetDimensions(formatDescription), maximumBufferRetainedCount: maximumRetainedBuffer, pixelFormat: pixelFormat) else {
            errorCallBack?(nil, CIFilterRendererErrorHandler.CannotInitializeBuffer)
            return
        }
    }

    private func initializeBufferwWith(_ dimensions: CMVideoDimensions, maximumBufferRetainedCount: Int, pixelFormat: OSType) -> Bool {

        mainBufferPool = CIFilterRenderer.createPixelBufferPool(dimensions.width, dimensions.height, pixelFormat, maximumBufferRetainedCount.i)

        guard let mainBufferPool = mainBufferPool else {
            reset()
            errorCallBack?(nil, CIFilterRendererErrorHandler.CannotCreateBufferPoolWithGivenParams)
            return false
        }

        bufferPoolSettings = CIFilterRenderer.createPixelBufferPoolAuxAttributes(maximumBufferRetainedCount.i)
        CIFilterRenderer.preallocatePixelBuffersInPool(mainBufferPool, bufferPoolSettings)

        var tempBuffer: CVPixelBuffer? = nil
        CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault, mainBufferPool, bufferPoolSettings, &tempBuffer)

        guard let testBuffer = tempBuffer else {
            reset()
            errorCallBack?(nil, CIFilterRendererErrorHandler.CannotCreateTempPixelBuffer)
            return false
        }

        //Creating the outputFormatDescription for created buffer pool and settings and using it whenever wanted.
        var outputFormatDesc: CMFormatDescription? = nil
        CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, testBuffer, &outputFormatDesc)
        outputFormatDescription = outputFormatDesc
        return true
    }

    func copy(_ pixelBuffer: CMSampleBuffer, withFilter ciFilter: CIFilter?) -> CVPixelBuffer? {
        guard let mainBufferPool = mainBufferPool else {
            errorCallBack?(nil, CIFilterRendererErrorHandler.NoBufferIsCreated)
            return nil
        }
        var renderedBuffer: CVPixelBuffer? = nil
        let err = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, mainBufferPool, &renderedBuffer)

        guard err == 0 else {
            let customError = NSError(domain: errorFor(status: err), code: err.l, userInfo: nil)
            errorCallBack?(customError, CIFilterRendererErrorHandler.CannotCreateBufferPoolWithGivenParams)
            return nil
        }

        autoreleasepool {
            let sourceImage = CIImage(buffer: pixelBuffer)
            ciFilter?.setValue(sourceImage, forKey: kCIInputImageKey)
            let filteredImage = ciFilter?.value(forKey: kCIOutputImageKey) as? CIImage
            self.coreImageContext.render(filteredImage ?? sourceImage, to: renderedBuffer!, bounds: sourceImage.extent, colorSpace: self.colorSpace)
        }

        return renderedBuffer
    }

    func reset() {
        mainBufferPool = nil
        bufferPoolSettings = [:]
        outputFormatDescription = nil
    }

    deinit {
        reset()
    }
}

extension CIFilterRenderer {

    static fileprivate func createPixelBufferPool(_ width: Int32, _ height: Int32, _ pixelFormat: OSType, _ maxBufferCount: Int32) -> CVPixelBufferPool? {
        var outputPool: CVPixelBufferPool? = nil

        let sourcePixelBufferOptions: NSDictionary = [kCVPixelBufferPixelFormatTypeKey : pixelFormat,
                                                      kCVPixelBufferWidthKey : width,
                                                      kCVPixelBufferHeightKey : height,
                                                      kCVPixelBufferMetalCompatibilityKey: true,
                                                      kCVPixelBufferOpenGLCompatibilityKey: true,
                                                      kCVPixelBufferOpenGLESCompatibilityKey: true,
                                                      kCVPixelBufferCGImageCompatibilityKey: true,
                                                      kCVPixelBufferIOSurfacePropertiesKey : NSDictionary()]

        let pixelBufferPoolOptions: NSDictionary = [kCVPixelBufferPoolMinimumBufferCountKey : maxBufferCount]

        CVPixelBufferPoolCreate(kCFAllocatorDefault, pixelBufferPoolOptions, sourcePixelBufferOptions, &outputPool)

        return outputPool
    }

    static fileprivate func createPixelBufferPoolAuxAttributes(_ maxBufferCount: Int32) -> NSDictionary {
        // CVPixelBufferPoolCreatePixelBufferWithAuxAttributes() will return kCVReturnWouldExceedAllocationThreshold if we have already vended the max number of buffers
        let auxAttributes: NSDictionary = [kCVPixelBufferPoolAllocationThresholdKey : maxBufferCount]
        return auxAttributes
    }

    static fileprivate func preallocatePixelBuffersInPool(_ pool: CVPixelBufferPool, _ auxAttributes: NSDictionary) {
        // Preallocate buffers in the pool, since this is for real-time display/capture
        var pixelBuffers: [CVPixelBuffer] = []

        while true {
            var pixelBuffer: CVPixelBuffer? = nil
            let err = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault, pool, auxAttributes, &pixelBuffer)

            if err == kCVReturnWouldExceedAllocationThreshold {
                break
            }
            
            assert(err == noErr)
            pixelBuffers.append(pixelBuffer!)
        }
        pixelBuffers.removeAll()
    }
}
