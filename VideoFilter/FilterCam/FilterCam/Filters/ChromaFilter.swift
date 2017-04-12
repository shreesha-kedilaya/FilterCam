//
//  ChromaFilter.swift
//  FilterCam
//
//  Created by Shreesha on 13/03/17.
//  Copyright © 2017 YML. All rights reserved.
//

import Foundation
import CoreImage

class ChromaFilter: CIFilter {
    var inputImage: CIImage?

    func sampleKernel() -> CIColorKernel {
        let kernelString =
            "kernel vec4 chromaKey( __sample s) { \n" +
                "  vec4 newPixel = s.rgba;" +
                "  newPixel[0] = 0.0;" +
                "  newPixel[2] = newPixel[2] / 2.0;" +
                "  return newPixel;\n" +
        "}"

        let kernel = CIColorKernel(string: kernelString)

        return kernel!
    }


    override var outputImage: CIImage? {
        let dod = inputImage?.extent
        return sampleKernel().apply(withExtent: dod!, arguments: [inputImage!])
    }
}
