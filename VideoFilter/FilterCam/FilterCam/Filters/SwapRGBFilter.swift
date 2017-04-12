//
//  CustomFilters.swift
//  FilterCam
//
//  Created by Shreesha on 03/03/17.
//  Copyright © 2017 YML. All rights reserved.
//

import Foundation
import CoreImage

class SwapRGBFilter: CIFilter {
    var inputImage: CIImage?
    var inputAmout: Float!

    func sampleKernel() -> CIColorKernel {
        let kernel = CIColorKernel(string: "kernel vec4 swapRedGreenAmount ( __sample s, float amount ){ return mix(s.rgba, s.grba, amount);}")
        return kernel!
    }

    override var outputImage: CIImage? {
        let dod = inputImage?.extent
        return sampleKernel().apply(withExtent: dod!, arguments: [inputImage!, inputAmout])
    }
}
