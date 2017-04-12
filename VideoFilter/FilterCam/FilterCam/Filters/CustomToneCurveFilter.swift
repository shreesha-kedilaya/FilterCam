//
//  CustomToneCurveFilter.swift
//  FilterCam
//
//  Created by Shreesha on 15/03/17.
//  Copyright © 2017 YML. All rights reserved.
//

import Foundation
import UIKit

class CustomToneCurveFilter: CIFilter {

    var redCurve: [Float]!
    var greenCurve: [Float]!
    var blueCurve: [Float]!
    var rgbCompositeCurve: [Float]!
    var texture: CIImage!

    var inputImage: CIImage?

    func sampleKernel() -> CIKernel {

        let kernelString =
            "kernel vec4 filterKernel(sampler inputImage, sampler toneCurveTexture, float intensity) {" +
                "vec4 textureColor = sample(inputImage,samplerCoord(inputImage));" +
                "vec4 toneCurveTextureExtent = samplerExtent(toneCurveTexture);" +

                "vec2 redCoord = samplerTransform(toneCurveTexture,vec2(textureColor.r * 255.0 + 0.5 + toneCurveTextureExtent.x, toneCurveTextureExtent.y + 0.5));" +
                "vec2 greenCoord = samplerTransform(toneCurveTexture,vec2(textureColor.g * 255.0 + 0.5 + toneCurveTextureExtent.x, toneCurveTextureExtent.y + 0.5));" +
                "vec2 blueCoord = samplerTransform(toneCurveTexture,vec2(textureColor.b * 255.0 + 0.5 + toneCurveTextureExtent.x, toneCurveTextureExtent.y + 0.5));" +

                "float redCurveValue = sample(toneCurveTexture, redCoord).r;" +
                "float greenCurveValue = sample(toneCurveTexture, greenCoord).g;" +
                "float blueCurveValue = sample(toneCurveTexture, blueCoord).b;" +
                "return vec4(mix(textureColor.rgb,vec3(redCurveValue, greenCurveValue, blueCurveValue),intensity),textureColor.a);" +
        "}"

        let kernel = CIKernel(string: kernelString)
        return kernel!
    }

    override var outputImage: CIImage? {

        guard let _ = redCurve, let _ = greenCurve, let _ = blueCurve, let _ = rgbCompositeCurve else {
            return nil
        }

        let dod = inputImage?.extent
        return sampleKernel().apply(withExtent: dod!, roiCallback: { (index, rect) -> CGRect in
            if index == 0 {
                return rect
            } else {
                return self.texture.extent
            }
        }, arguments: [self.inputImage!, self.texture, 0.5])
    }

    func initializeWith(acvFile: String) {
        let filterParser = FilterParser(acvFileName: acvFile)
        redCurve = FilterParser.getPreparedSplineCurve(filterParser?.redPoints)
        greenCurve = FilterParser.getPreparedSplineCurve(filterParser?.greenPoints)
        blueCurve = FilterParser.getPreparedSplineCurve(filterParser?.bluePoints)
        rgbCompositeCurve = FilterParser.getPreparedSplineCurve(filterParser?.rgbComposer)

        updateTexture()
    }

    func updateTexture() {
        var toneCurveByteArray: [UInt8] = [UInt8](repeating: 0x00, count: 256 * 4)
        for currentCurveIndex in 0..<256 {
            // BGRA for upload to texture

            let b = currentCurveIndex > rgbCompositeCurve.count - 1 ? rgbCompositeCurve.count.f - 1.f : min(max(currentCurveIndex.f + CFloat(blueCurve[currentCurveIndex].g), 0), 255.f)
            let maxV1 = max(b + CFloat(rgbCompositeCurve[b.i].g), 0)
            toneCurveByteArray[currentCurveIndex * 4] = UInt8(min(maxV1, 255.f))

            var g = currentCurveIndex > greenCurve.count - 1 ? 255.f : min(max(currentCurveIndex.f + CFloat(greenCurve[currentCurveIndex].g), 0), 255.f)

            g = g.i > rgbCompositeCurve.count - 1 ? rgbCompositeCurve.count.f - 1.f : g

            let maxV2 = max(b + CFloat(rgbCompositeCurve[g.i].g), 0)
            toneCurveByteArray[currentCurveIndex * 4 + 1] = UInt8(min(maxV2, 255.f))

            var r = currentCurveIndex > redCurve.count - 1 ? 255.f : min(max(currentCurveIndex.f + CFloat(redCurve[currentCurveIndex].g), 0), 255.f)

            r = r.i > rgbCompositeCurve.count - 1 ? rgbCompositeCurve.count.f - 1.f : r

            let maxV3 = max(r + CFloat(self.rgbCompositeCurve[r.i].g), 0)
            toneCurveByteArray[currentCurveIndex * 4 + 2] = UInt8(min(maxV3, 255.f))
            toneCurveByteArray[currentCurveIndex * 4 + 3] = 255
        }

        let toneCurveTexture = CIImage(bitmapData: NSData(bytesNoCopy: &toneCurveByteArray, length: 256 * 4 * MemoryLayout<UInt8>.size, freeWhenDone: false) as Data, bytesPerRow: 256 * 4 * MemoryLayout<UInt8>.size, size: CGSize(width: 256, height: 1), format: kCIFormatRGBA8, colorSpace: nil)
        
        self.texture = toneCurveTexture
    }
}
