//
//  FilterRenderer.swift
//  FilterCam
//
//  Created by Shreesha on 21/11/16.
//  Copyright © 2016 YML. All rights reserved.
//

import Foundation
import CoreImage
import CoreGraphics
import CoreMedia

//let filter = CIFilter(name: "CIGaussianBlur")
class FilterRenderer {
    private var ciContext: CIContext!
    private var customFilter: CIFilter!
    private var rgbColorSpace: CGColorSpace!
    private var bufferPool: CVPixelBufferPool!
    private var bufferPoolAuxAttributes: NSDictionary = [:]
    private var outputFormatDescription: CMFormatDescription!

    deinit {
        deleteBuffers()
    }

    func prepareForInputWith(inputFormatDescription: CMFormatDescription!, outputRetainedBufferCountHint: Int) {
        // The input and output dimensions are the same. This renderer doesn't do any scaling.
        let dimensions = CMVideoFormatDescriptionGetDimensions(inputFormatDescription)

        self.deleteBuffers()
        if !self.initializeBuffersWith(outputDimensions: dimensions, retainedBufferCountHint: outputRetainedBufferCountHint) {
            fatalError("Problem preparing renderer.")
        }

        rgbColorSpace = CGColorSpaceCreateDeviceRGB()
        let eaglContext = EAGLContext(api: .openGLES2)
        ciContext = CIContext(eaglContext: eaglContext!, options: [kCIContextWorkingColorSpace : NSNull()])

        customFilter = CIFilter(name: "CIColorMatrix")
        let greenCoefficients: [CGFloat] = [0, 0, 0, 0]
        customFilter.setValue(CIVector(values: greenCoefficients, count: 4), forKey: "inputGVector")
    }

    private func initializeBuffersWith(outputDimensions: CMVideoDimensions, retainedBufferCountHint clientRetainedBufferCountHint: size_t) -> Bool
    {
        var success = true

        let maxRetainedBufferCount = clientRetainedBufferCountHint
        bufferPool = createPixelBufferPool(width: outputDimensions.width, outputDimensions.height, kCVPixelFormatType_32BGRA, Int32(maxRetainedBufferCount))
        if bufferPool == nil {
            NSLog("Problem initializing a buffer pool.")
            success = false
        } else {

            bufferPoolAuxAttributes = createPixelBufferPoolAuxAttributes(maxBufferCount: Int32(maxRetainedBufferCount))
            preallocatePixelBuffersInPool(pool: bufferPool, bufferPoolAuxAttributes)

            var outputFormatDescription: CMFormatDescription? = nil
            var testPixelBuffer: CVPixelBuffer? = nil
            CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault, bufferPool, bufferPoolAuxAttributes, &testPixelBuffer)
            if testPixelBuffer == nil {
                NSLog("Problem creating a pixel buffer.")
                success = false
            } else {
                CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, testPixelBuffer!, &outputFormatDescription)
                self.outputFormatDescription = outputFormatDescription
            }
        }

        if !success {
            self.deleteBuffers()
        }
        return success
    }

    func copyRenderedPixelBuffer(pixelBuffer: CVPixelBuffer!) -> CVPixelBuffer! {
        var renderedOutputPixelBuffer: CVPixelBuffer? = nil

        let sourceImage = CIImage(cvPixelBuffer: pixelBuffer, options: nil)

        customFilter.setValue(sourceImage, forKey: kCIInputImageKey)
        let filteredImage = customFilter.value(forKey: kCIOutputImageKey) as! CIImage?

        let err = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, bufferPool, &renderedOutputPixelBuffer)
        if err != 0 {
            NSLog("Cannot obtain a pixel buffer from the buffer pool (%d)", Int(err))
        } else {

            // render the filtered image out to a pixel buffer (no locking needed as CIContext's render method will do that)
            ciContext.render(filteredImage!, to: renderedOutputPixelBuffer!, bounds: filteredImage!.extent, colorSpace: rgbColorSpace)
        }

        return renderedOutputPixelBuffer
    }


    private func deleteBuffers() {
        if bufferPool != nil {
            bufferPool = nil
        }
        bufferPoolAuxAttributes = [:]
        if outputFormatDescription != nil {
        }
        if ciContext != nil {
        }
        if customFilter != nil {
            customFilter = nil
        }
        if rgbColorSpace != nil {
            rgbColorSpace = nil
        }
    }
}
private func createPixelBufferPool(width: Int32, _ height: Int32, _ pixelFormat: OSType, _ maxBufferCount: Int32) -> CVPixelBufferPool?
{
    
    var outputPool: CVPixelBufferPool? = nil

    let sourcePixelBufferAttributes: [String: Any] = [kCVPixelBufferPixelFormatTypeKey.s : kCVPixelFormatType_32BGRA,
                                                  kCVPixelBufferWidthKey.s: 1920,
                                                  kCVPixelBufferHeightKey.s: 1080]
    let pixelBufferPoolOptions: [String: Int32] = [kCVPixelBufferPoolMaximumBufferAgeKey.s: 2]

    let status = CVPixelBufferPoolCreate(kCFAllocatorDefault, pixelBufferPoolOptions as CFDictionary, sourcePixelBufferAttributes as CFDictionary, &outputPool)

    print(status.stringValue())

    return outputPool
}

private func preallocatePixelBuffersInPool(pool: CVPixelBufferPool, _ auxAttributes: NSDictionary) {
    // Preallocate buffers in the pool, since this is for real-time display/capture
    let pixelBuffers: NSMutableArray = []
    while true {
        var pixelBuffer: CVPixelBuffer? = nil
        let err = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault, pool, auxAttributes, &pixelBuffer)

        if err == kCVReturnWouldExceedAllocationThreshold {
            break
        }
        assert(err == noErr)
        pixelBuffers.add(pixelBuffer!)
    }
}
extension CFString {
    public var ns: NSString {
        return self as NSString
    }

    public var s: String {
        return self as String
    }
}
extension Int32 {
    var l: Double {
        return Double(self)
    }
}
private func createPixelBufferPoolAuxAttributes(maxBufferCount: Int32) -> NSDictionary {
    // CVPixelBufferPoolCreatePixelBufferWithAuxAttributes() will return kCVReturnWouldExceedAllocationThreshold if we have already vended the max number of buffers
    let auxAttributes: NSDictionary = [kCVPixelBufferPoolAllocationThresholdKey.ns : maxBufferCount.l]
    return auxAttributes
}

extension CVReturn {

    func stringValue() -> String {

        var ret = ""

        switch self {
        case kCVReturnSuccess:
            ret = "kCVReturnSuccess"
        case kCVReturnFirst:
            ret = "kCVReturnFirst"
        case kCVReturnLast:
            ret = "kCVReturnLast"
        case kCVReturnInvalidArgument:
            ret = "kCVReturnInvalidArgument"
        case kCVReturnAllocationFailed:
            ret = "kCVReturnAllocationFailed"
        case kCVReturnInvalidDisplay:
            ret = "kCVReturnInvalidDisplay"
        case kCVReturnDisplayLinkAlreadyRunning:
            ret = "kCVReturnDisplayLinkAlreadyRunning"
        case kCVReturnDisplayLinkNotRunning:
            ret = "kCVReturnDisplayLinkNotRunning"
        case kCVReturnDisplayLinkCallbacksNotSet:
            ret = "kCVReturnDisplayLinkCallbacksNotSet"
        case kCVReturnInvalidPixelFormat:
            ret = "kCVReturnInvalidPixelFormat"
        case kCVReturnInvalidSize:
            ret = "kCVReturnInvalidSize"
        case kCVReturnInvalidPixelBufferAttributes:
            ret = "kCVReturnInvalidPixelBufferAttributes"
        case kCVReturnPixelBufferNotOpenGLCompatible:
            ret = "kCVReturnPixelBufferNotOpenGLCompatible"
        case kCVReturnPixelBufferNotMetalCompatible:
            ret = "kCVReturnPixelBufferNotMetalCompatible"
        case kCVReturnWouldExceedAllocationThreshold:
            ret = "kCVReturnWouldExceedAllocationThreshold"
        case kCVReturnPoolAllocationFailed:
            ret = "kCVReturnPoolAllocationFailed"
        case kCVReturnInvalidPoolAttributes:
            ret = "kCVReturnInvalidPoolAttributes"
        default:
            ret = "Unknown"
        }

        return ret;
    }
}
