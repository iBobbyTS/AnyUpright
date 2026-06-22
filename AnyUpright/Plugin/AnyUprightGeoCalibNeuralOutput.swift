//
//  AnyUprightGeoCalibNeuralOutput.swift
//  AnyUpright
//

import Foundation

struct AUGeoCalibNeuralOutput {
    var upField: [Float]
    var upConfidence: [Float]
    var latitudeField: [Float]
    var latitudeConfidence: [Float]
    var fieldShape: [Int]
    var confidenceShape: [Int]
}
