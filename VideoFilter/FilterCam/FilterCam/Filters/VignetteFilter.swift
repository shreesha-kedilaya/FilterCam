//
//  VignetteFilter.swift
//  FilterCam
//
//  Created by Shreesha on 13/03/17.
//  Copyright © 2017 YML. All rights reserved.
//

import Foundation
import CoreImage

class VignetteFilter: CIFilter {
    var inputImage: CIImage?

    func sampleKernel() -> CIColorKernel {
        let kernel = CIColorKernel(string: "kernel vec4 vignette ( __sample s, vec2 centerOffset, float radius ){vec2 vecFromCenter = destCoord() - centerOffset;float distance = length (vecFromCenter);float darken = 1.0 - (distance/radius);return vec4(s.rgb * darken, s.a);\n}")
        return kernel!
    }


    override var outputImage: CIImage? {
        let dod = inputImage?.extent

        let radius = 0.5 * hypot(dod!.size.width, dod!.size.height)
        let centerOffset = CIVector(x: dod!.size.width / 2 + dod!.origin.x,
                                    y: dod!.size.height / 2 + dod!.origin.y)

        return sampleKernel().apply(withExtent: dod!, arguments: [inputImage!, centerOffset, radius])
    }
}
