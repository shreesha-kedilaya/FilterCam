//
//  Filters.swift
//  FilterCam
//
//  Created by Shreesha on 22/02/17.
//  Copyright © 2017 YML. All rights reserved.
//

import Foundation
import CoreImage
import UIKit
import CoreMedia
import CoreGraphics

struct AllCIFilters {

    //Blur filters
    enum CICategoryBlur: String{
        case CIDiscBlur = "CIDiscBlur"
        case CIGaussianBlur = "CIGaussianBlur"
        case CIZoomBlur = "CIZoomBlur"
    }

    //CICategoryColorAdjustment
    enum CICategoryColorAdjustment: String {
        case CIColorClamp = "CIColorClamp"
        case CIColorControls = "CIColorControls"
        case CIColorMatrix = "CIColorMatrix"
        case CIHueAdjust = "CIHueAdjust"
        case CITemperatureAndTint = "CITemperatureAndTint"
        case CIToneCurve = "CIToneCurve"
        case CIVibrance = "CIVibrance"
        case CIWhitePointAdjust = "CIWhitePointAdjust"
    }

    //CICategoryColorEffect
    enum CICategoryColorEffect: String {
        case CIColorCrossPolynomial = "CIColorCrossPolynomial"
        case CIColorCube = "CIColorCube"
        case CIColorInvert = "CIColorInvert"
        case CIColorMap = "CIColorMap"
        case CIColorMonochrome = "CIColorMonochrome"
        case CIColorPosterize = "CIColorPosterize"
        case CIFalseColor = "CIFalseColor"
        //Black and white
        case CIMaskToAlpha = "CIMaskToAlpha"
        case CIPhotoEffectChrome = "CIPhotoEffectChrome"
        case CIPhotoEffectFade = "CIPhotoEffectFade"
        case CIPhotoEffectInstant = "CIPhotoEffectInstant"
        //Black and white with low contrast
        case CIPhotoEffectMono = "CIPhotoEffectMono"
        //black-and-white photography film with exaggerated contrast.
        case CIPhotoEffectNoir = "CIPhotoEffectNoir"
        //Vintage effect
        case CIPhotoEffectProcess = "CIPhotoEffectProcess"

        //black-and-white photography film with nominal contrast.
        case CIPhotoEffectTonal = "CIPhotoEffectTonal"
        //Vintage
        case CIPhotoEffectTransfer = "CIPhotoEffectTransfer"
        case CISepiaTone = "CISepiaTone"
        case CIVignette = "CIVignette"
        case CIVignetteEffect = "CIVignetteEffect"
    }

    //CICategoryCompositeOperation
    enum CICategoryCompositeOperation: String {
        case CIColorBlendMode = "CIColorBlendMode"
        case CICategoryCompositeOperation = "CICategoryCompositeOperation"
        case CIColorBurnBlendMode = "CIColorBurnBlendMode"
        case CIColorDodgeBlendMode = "CIColorDodgeBlendMode"
        case CIDarkenBlendMode = "CIDarkenBlendMode"
        case CIDifferenceBlendMode = "CIDifferenceBlendMode"
        case CIDivideBlendMode = "CIDivideBlendMode"
        case CIExclusionBlendMode = "CIExclusionBlendMode"
        case CIHardLightBlendMode = "CIHardLightBlendMode"
        case CIHueBlendMode = "CIHueBlendMode"
        case CILightenBlendMode = "CILightenBlendMode"
        case CILinearBurnBlendMode = "CILinearBurnBlendMode"
        case CILinearDodgeBlendMode = "CILinearDodgeBlendMode"
        case CILuminosityBlendMode = "CILuminosityBlendMode"
        case CIMultiplyCompositing = "CIMultiplyCompositin"
        case CISourceAtopCompositing = "CISourceAtopCompositing"
    }

    enum CICategoryDistortionEffect: String {
        case CIBumpDistortion = "CIBumpDistortion"
        case CIBumpDistortionLinear = "CIBumpDistortionLinear"
        case CICircleSplashDistortion = "CICircleSplashDistortion"
        case CICircularWrap = "CICircularWrap"
        case CIDroste = "CIDroste"
        case CIDisplacementDistortion = "CIDisplacementDistortion"
        case CIGlassDistortion = "CIGlassDistortion"
        case CIGlassLozenge = "CIGlassLozenge"
        case CIHoleDistortion = "CIHoleDistortion"
        case CILightTunnel = "CILightTunnel"
        case CIPinchDistortion = "CIPinchDistortion"
        case CIStretchCrop = "CIStretchCrop"
        case CITorusLensDistortion = "CITorusLensDistortion"
        case CITwirlDistortion = "CITwirlDistortion"
        case CIVortexDistortion = "CIVortexDistortion"
    }
}

struct FilterGenerator {

    static func filteredImageFor(buffer: CMSampleBuffer? = nil, filter: CIFilter?, image: UIImage? = nil, completion: @escaping (UIImage?) -> Void) {
        Async.global(.background) {
            guard let filter = filter else {
                completion(nil)
                return
            }

            guard let _image = image?.cgImage else {
                completion(nil)
                return
            }

            let ciimage = CIImage(cgImage: _image)

            filter.setValue(ciimage, forKey: kCIInputImageKey)

            let _filteredImage = filter.outputImage

            guard let filteredImage = _filteredImage else {
                completion(nil)
                return
            }

            guard let cgImage = FilterPipeline.shared().coreImageContextHandler.coreImageContext.createCGImage(filteredImage, from: ciimage.extent) else {
                completion(nil)
                return
            }

            let uiImage = UIImage(cgImage: cgImage)
            completion(uiImage)
        }
    }

    static func swapRGBFilter(inputAmount: Float) -> CIFilter {
        let filter = SwapRGBFilter()
        filter.inputAmout = inputAmount
        return filter
    }

    static func vignetteEffect() -> CIFilter {
        return VignetteFilter()
    }

    static func chromaFilter() -> CIFilter {
        return ChromaFilter()
    }

    static func customToneCurveFilter(fileName: String) -> CIFilter {
        let filter = CustomToneCurveFilter()
        filter.initializeWith(acvFile: fileName)
        return filter
    }

    static let filterStrings = [AllCIFilters.CICategoryColorAdjustment.CIColorClamp.rawValue,
                         AllCIFilters.CICategoryColorAdjustment.CIColorControls.rawValue,
                         AllCIFilters.CICategoryColorAdjustment.CIColorMatrix.rawValue,
                         AllCIFilters.CICategoryColorAdjustment.CIHueAdjust.rawValue,
                         AllCIFilters.CICategoryColorAdjustment.CITemperatureAndTint.rawValue,
                         AllCIFilters.CICategoryColorAdjustment.CIToneCurve.rawValue,
                         AllCIFilters.CICategoryColorAdjustment.CIWhitePointAdjust.rawValue,
                         AllCIFilters.CICategoryColorEffect.CIColorInvert.rawValue,
                         AllCIFilters.CICategoryColorEffect.CIColorCube.rawValue,
                         AllCIFilters.CICategoryColorEffect.CIColorCrossPolynomial.rawValue,
                         AllCIFilters.CICategoryColorEffect.CIFalseColor.rawValue,
                         AllCIFilters.CICategoryColorEffect.CIColorPosterize.rawValue,
                         AllCIFilters.CICategoryDistortionEffect.CIBumpDistortion.rawValue,
                         AllCIFilters.CICategoryDistortionEffect.CICircularWrap.rawValue,
                         AllCIFilters.CICategoryDistortionEffect.CIBumpDistortionLinear.rawValue,
                         AllCIFilters.CICategoryDistortionEffect.CIDisplacementDistortion.rawValue,
                         AllCIFilters.CICategoryDistortionEffect.CIDroste.rawValue,
                         AllCIFilters.CICategoryDistortionEffect.CIGlassDistortion.rawValue]


    static func colorClamp(min: CIVector, max: CIVector) -> CIFilter? {
        let parameters = ["inputMinComponents": min, "inputMaxComponents": max] as [String : Any]
        let filter = CIFilter(name: filterStrings[0], withInputParameters: parameters)
        return filter
    }

    static func colorControls(saturation: Float, brightness: Float, contrast: Float) -> CIFilter? {
        let parameters = ["inputSaturation": saturation, "inputBrightness": brightness, "inputContrast": contrast] as [String : Any]
        let filter = CIFilter(name: filterStrings[1], withInputParameters: parameters)
        return filter
    }

    static func colorMatrix(rVector: CIVector , gVector: CIVector , bVector: CIVector , aVector: CIVector , biasVector: CIVector) -> CIFilter? {
        let parameters = ["inputRVector": rVector, "inputGVector": gVector, "inputBVector": bVector, "inputAVector": aVector, "inputBiasVector": biasVector] as [String : Any]
        let filter = CIFilter(name: filterStrings[2], withInputParameters: parameters)
        return filter
    }

    static func hueAdjust(angleInRadians: Float) -> CIFilter? {
        let parameters = [kCIInputAngleKey: angleInRadians] as [String : Any]
        let filter = CIFilter(name: filterStrings[3], withInputParameters: parameters)
        return filter
    }

    static func bumpDistortion(inputCenter: CIVector, inputRadius: Float, inputScale: Float) -> CIFilter? {
        let parameters = ["inputCenter": inputCenter, "inputRadius": inputRadius, "inputScale": inputScale] as [String : Any]
        let filter = CIFilter(name: AllCIFilters.CICategoryDistortionEffect.CIBumpDistortion.rawValue, withInputParameters: parameters)
        return filter
    }

    static func droste(inputInsetPoint0: CIVector, inputInsetPoint1: CIVector, inputStrands: Float, inputPeriodicity: Float, inputRotation: Float, inputZoom: Float) -> CIFilter? {
        let parameters = ["inputInsetPoint0": inputInsetPoint0, "inputInsetPoint1": inputInsetPoint1, "inputStrands": inputStrands, "inputPeriodicity":inputPeriodicity, "inputRotation": inputRotation, "inputZoom": inputZoom] as [String : Any]
        let filter = CIFilter(name: AllCIFilters.CICategoryDistortionEffect.CIDroste.rawValue, withInputParameters: parameters)
        return filter
    }

    static func lightTunnel(inputCenter: CIVector, inputRotation: Float, inputRadius: Float) -> CIFilter? {
        let parameters = ["inputCenter": inputCenter, "inputRotation": inputRotation, "inputRadius": inputRadius] as [String : Any]
        let filter = CIFilter(name: AllCIFilters.CICategoryDistortionEffect.CILightTunnel.rawValue, withInputParameters: parameters)
        return filter
    }

    static func pixellate(scale: Float) -> CIFilter? {
        let parameters = [kCIInputScaleKey:scale] as [String : Any]
        return CIFilter(name: "CIPixellate", withInputParameters: parameters)
    }

    static func kaleidoscope() -> CIFilter? {
        let parameters = ["inputWidth" : 300, "inputAngle" : 1.066] as [String : Any]
        return CIFilter(name: "CITriangleTile", withInputParameters: parameters)
    }

    static func vibrance(amount: Float) -> CIFilter? {
        let parameters = ["inputAmount": amount] as [String : Any]
        return CIFilter(name: "CIVibrance", withInputParameters: parameters)
    }

    static func compositeSourceOver(overlay: CIImage) -> CIFilter? {
        let parameters = [kCIInputImageKey: overlay]
        let filter = CIFilter(name: "CISourceOverCompositing", withInputParameters: parameters)
        return filter
    }

    static func blendWith(_ filterName: AllCIFilters.CICategoryCompositeOperation, background: CIImage) -> CIFilter? {
        let parameters = [ kCIInputBackgroundImageKey: background]
        let filter = CIFilter(name: filterName.rawValue, withInputParameters: parameters)
        return filter
    }

    static func blur() -> CIFilter? {
        let param = ["inputRadius": 6]
        let filter = CIFilter(name: AllCIFilters.CICategoryBlur.CIGaussianBlur.rawValue, withInputParameters: param)
        return filter
    }

    static func filterWith(name: String, attributeBlock: (_ filter: CIFilter?) -> [String: Any]) -> CIFilter? {
        let filter = CIFilter(name: name)
        let params = attributeBlock(filter)

        for attribute in params {
            filter?.setValue(attribute.value, forKey: attribute.key)
        }

        return filter
    }

    static func filtersWith(_ names: [String]) -> [CIFilter?] {
        var filters: [CIFilter?] = []
        for name in names {
            filters.append(CIFilter(name: name))
        }

        return filters
    }
}
