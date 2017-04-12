//
//  CustomCIFilters.swift
//  FilterCam
//
//  Created by Shreesha on 30/11/16.
//  Copyright © 2016 YML. All rights reserved.
//

import Foundation
import CoreImage

typealias CustomFilter = (CIImage) -> (CIFilter)

struct CustomCIFilter {

    var count = 1

    static func blur(radius: Double) -> CustomFilter {

        return { image in
            let parameters = [
                kCIInputRadiusKey: radius,
                kCIInputImageKey: image
                ] as [String : Any]
            let filter = CIFilter(name: "CIGaussianBlur",
                                  withInputParameters: parameters)
            return filter!
        }
    }

    static func hueAdjust(angleInRadians: Float) -> CustomFilter {
        return { image in
            let parameters = [
                kCIInputAngleKey: angleInRadians,
                kCIInputImageKey: image
                ] as [String : Any]
            let filter = CIFilter(name: "CIHueAdjust",
                                  withInputParameters: parameters)
            return filter!
        }
    }

    static func pixellate(scale: Float) -> CustomFilter {
        return { image in
            let parameters = [
                kCIInputImageKey:image,
                kCIInputScaleKey:scale
                ] as [String : Any]
            return CIFilter(name: "CIPixellate", withInputParameters: parameters)!
        }
    }

    static func kaleidoscope() -> CustomFilter {
        return { image in
            let parameters = [
                kCIInputImageKey:image,
                ]
            return CIFilter(name: "CITriangleKaleidoscope", withInputParameters: parameters)!
        }
    }


    static func vibrance(amount: Float) -> CustomFilter {
        return { image in
            let parameters = [
                kCIInputImageKey: image,
                "inputAmount": amount
                ] as [String : Any]
            return CIFilter(name: "CIVibrance", withInputParameters: parameters)!
        }
    }

    static func compositeSourceOver(overlay: CIImage) -> CustomFilter {
        return { image in
            let parameters = [
                kCIInputBackgroundImageKey: image,
                kCIInputImageKey: overlay
            ]
            let filter = CIFilter(name: "CISourceOverCompositing",
                                  withInputParameters: parameters)
            return filter!
        }
    }


    static func radialGradient(center: CGPoint, radius: CGFloat) -> CustomFilter {
        return { image in

            let params: [String: Any] = [
                "inputColor0": CIColor(red: 1, green: 1, blue: 1),
                "inputColor1": CIColor(red: 0, green: 0, blue: 0),
                "inputCenter": CIVector(cgPoint: center),
                "inputRadius0": radius,
                "inputRadius1": (radius + 1)
            ]
            return CIFilter(name: "CIRadialGradient", withInputParameters: params)!
        }
    }

    static func blendWithMask(background: CIImage, mask: CIImage) -> CustomFilter {
        return { image in
            let parameters = [
                kCIInputBackgroundImageKey: background,
                kCIInputMaskImageKey: mask,
                kCIInputImageKey: image
            ]
            let filter = CIFilter(name: "CIBlendWithMask",
                                  withInputParameters: parameters)

            return filter!
        }
    }
}

enum CustomCIFilters {
    case hueAdjust(angleInRadians: Float)
    case pixellate(scale: Float)
    case blur(radius: Double)
    case kaleidoscope
    case vibrance(amount: Float)
    case compositeSourceOver(overlay: CIImage)
    case radialGradient(center: CGPoint, radius: CGFloat)
    case blendWithMask(background: CIImage, mask: CIImage)

    func filter() -> CustomFilter {

        var filter: CustomFilter
        switch self {
        case let .hueAdjust(angleInRadians):
            filter = CustomCIFilter.hueAdjust(angleInRadians: angleInRadians)
        case let .pixellate(scale):
            filter = CustomCIFilter.pixellate(scale: scale)
        case let .blur(radius):
            filter = CustomCIFilter.blur(radius: radius)
        case .kaleidoscope:
            filter = CustomCIFilter.kaleidoscope()
        case let .vibrance(amount):
            filter = CustomCIFilter.vibrance(amount: amount)
        case let .compositeSourceOver(overlay):
            filter = CustomCIFilter.compositeSourceOver(overlay: overlay)
        case let .radialGradient(center, radius):
            filter = CustomCIFilter.radialGradient(center: center, radius: radius)
        case let .blendWithMask(background, mask):
            filter = CustomCIFilter.blendWithMask(background: background, mask: mask)

        }
        return filter
    }
}
