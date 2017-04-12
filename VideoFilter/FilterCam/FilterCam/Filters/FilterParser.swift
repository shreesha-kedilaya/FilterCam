//
//  FilterParser.swift
//  FilterCam
//
//  Created by Shreesha on 14/03/17.
//  Copyright © 2017 YML. All rights reserved.
//

import Foundation
import UIKit

class FilterParser {

    var version: UInt16
    var totalCurves: UInt16
    var curves: [Any]
    var rgbComposer: [CGPoint]
    var redPoints: [CGPoint]
    var greenPoints: [CGPoint]
    var bluePoints: [CGPoint]

    init(acvFileUrl: URL) {
        let fileData = try? Data(contentsOf: acvFileUrl)

        let nsData = fileData! as NSData
        var bytes = nsData.bytes
        version = int16(bytes: bytes)
        bytes += 2
        totalCurves = int16(bytes: bytes)
        bytes += 2

        let pointRate: CGFloat = 1/255.0

        curves = []

        for _ in 0..<totalCurves {
            let pointCount = int16(bytes: bytes)
            bytes += 2
            var points = [Any]()

            for _ in 0..<pointCount {

                let y = int16(bytes: bytes)
                bytes += 2
                let x = int16(bytes: bytes)
                bytes += 2
                let point = CGPoint(x: CGFloat(x) * pointRate, y: CGFloat(y) * pointRate)
                points.append(point)
            }

            curves.append(points)
        }

        rgbComposer = curves[0] as! [CGPoint]
        redPoints = curves[1] as! [CGPoint]
        greenPoints = curves[2] as! [CGPoint]
        bluePoints = curves[3] as! [CGPoint]
    }
    
    convenience init?(acvFileName: String) {
        if let url = Bundle.main.url(forResource: acvFileName, withExtension: ".acv") {
            self.init(acvFileUrl: url)
        } else {
            return nil
        }
    }

    static func secondDerivative(_ points: [Any]) -> [Double]? {
        let n: Int = points.count
        if (n <= 0) || (n == 1) {
            return nil
        }
        var matrix: [[Double]] = [[Double]](repeating: [Double](repeating: 0, count: 3), count:n)
        var result = [Double](repeating: 0, count: n)
        matrix[0][0] = 0
        matrix[0][1] = 1
        // What about matrix[0][1] and matrix[0][0]?
        matrix[0][2] = 0
        for i in 1..<n - 1 {
            let P1: CGPoint = points[(i - 1)] as! CGPoint
            let P2: CGPoint = points[i] as! CGPoint
            let P3: CGPoint = points[(i + 1)] as! CGPoint
            matrix[i][0] = Double(P2.x - P1.x) / 6
            matrix[i][1] = Double(P3.x - P1.x) / 3
            matrix[i][2] = Double(P3.x - P2.x) / 6
            let param1 = Double((P3.y - P2.y) / (P3.x - P2.x))
            let param2 = Double((P2.y - P1.y) / (P2.x - P1.x))
            result[i] =  param1 - param2
        }

        result[0] = 0
        result[n - 1] = 0
        matrix[n - 1][1] = 1
        // What about matrix[n-1][0] and matrix[n-1][2]? For now
        matrix[n - 1][0] = 0
        matrix[n - 1][2] = 0
        // solving pass1 (up->down)
        for i in 1..<n {
            let k: Double = matrix[i][0] / matrix[i - 1][1]
            matrix[i][1] -= k * matrix[i - 1][2]
            matrix[i][0] = 0
            result[i] -= k * result[i - 1]
        }
        // solving pass2 (down->up)
        var i = n - 2
        while i >= 0 {
            let k: Double = matrix[i][2] / matrix[i + 1][1]
            matrix[i][1] -= k * matrix[i + 1][0]
            matrix[i][2] = 0
            result[i] -= k * result[i + 1]
            i -= 1
        }
        var y2 = [Double](repeating: 0, count: n)
        for i in 0..<n {
            y2[i] = result[i] / matrix[i][1]
        }

        var output = [Double]() /* capacity: n */
        for i in 0..<n {
            output.append(y2[i])
        }

        return output
    }

    static  func splineCurve(_ points: [Any]) -> [Any]? {
        var sdA: [Double] = self.secondDerivative(points)!
        // [points count] is equal to [sdA count]
        let n: Int = sdA.count
        if n < 1 {
            return nil
        }

        var sd = [Double](repeating: 0, count: n)
        // From NSMutableArray to sd[n];
        for i in 0..<n {
            let item = sdA[i]
            sd[i] = Double(item)
        }

        var output = [Any](repeating: CGPoint(x: 0, y: 0), count: n) /* capacity: (n + 1) */
        for i in 0..<n - 1 {
            print(i)
            let cur: CGPoint = points[i] as! CGPoint
            let next: CGPoint = points[(i + 1)] as! CGPoint
            for x in Int(cur.x)..<Int(next.x) {
                let t = Double(x - cur.x.i) / (next.x - cur.x).d
                let a: Double = 1 - t
                let b: Double = t
                let h: Double = next.x.d - cur.x.d
                let part1 = a * cur.y.d + b * next.y.d
                let part2 =  (h * h / 6) * ((a * a * a - a) * sd[i])
                let part3 = (b * b * b - b) * sd[i + 1]
                var y: Double = part1 + part2 + part3

                if y > 255.0 {
                    y = 255.0
                }
                else if y < 0.0 {
                    y = 0.0
                }

                output.append(CGPoint(x: CGFloat(x), y: CGFloat(y)))
            }
        }

        output.append(points.last!)
        return output
    }


    static func getPreparedSplineCurve(_ points: [Any]?) -> [Float]? {

        if let points = points as? [CGPoint],  points.count > 0 {
            // Sort the array.
            var sortedPoints = points.sorted { $0.x < $1.x }

            // Convert from (0, 1) to (0, 255).
            var convertedPoints = [Any]() /* capacity: sortedPoints?.count */
            for i in 0..<points.count {
                var point: CGPoint = sortedPoints[i]
                point.x = point.x * 255
                point.y = point.y * 255
                convertedPoints.append(point)
            }
            var splinePoints: [CGPoint] = self.splineCurve(convertedPoints) as! [CGPoint]
            // If we have a first point like (0.3, 0) we'll be missing some points at the beginning
            let firstSplinePoint: CGPoint = splinePoints[0]
            if firstSplinePoint.x > 0 {
                var i = firstSplinePoint.x
                while i >= 0 {
                    let newCGPoint = CGPoint(x: CGFloat(i), y: CGFloat(0))
                    splinePoints.insert(newCGPoint, at: 0)
                    i -= 1
                }
            }
            // Insert points similarly at the end, if necessary.
            let lastSplinePoint: CGPoint = splinePoints.last!
            if lastSplinePoint.x < 255 {
                for i in (lastSplinePoint.x.i + 1)...255 {
                    let newCGPoint = CGPoint(x: CGFloat(i), y: CGFloat(255))
                    splinePoints.append(newCGPoint)
                }
            }
            // Prepare the spline points.
            var preparedSplinePoints = [Float]() /* capacity: splinePoints.count */
            for i in 0..<splinePoints.count {
                let newPoint: CGPoint = splinePoints[i]

                let origPoint = CGPoint(x: CGFloat(newPoint.x), y: CGFloat(newPoint.x))
                var distance = sqrt(pow((origPoint.x - newPoint.x), 2.0) + pow((origPoint.y - newPoint.y), 2.0))
                if origPoint.y > newPoint.y {
                    distance = -distance
                }
                preparedSplinePoints.append(distance.f)
                
            }
            
            return preparedSplinePoints
        }
        
        return nil
    }

}

func int16(bytes: UnsafeRawPointer) -> UInt16 {
    var result: UInt16 = UInt16()
    memcpy(&result, bytes, 2)
    return CFSwapInt16BigToHost(result)
}
