#!/usr/bin/env swift
//
//  generate-test-assets.swift
//  AnyUpright
//

import CoreGraphics
import Foundation
import ImageIO

struct Point {
    var x: CGFloat
    var y: CGFloat
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".agent-work/test-assets")
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

func makeContext(width: Int, height: Int) -> CGContext {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        fatalError("Unable to create CGContext")
    }

    context.translateBy(x: 0, y: CGFloat(height))
    context.scaleBy(x: 1, y: -1)
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)
    return context
}

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1.0) -> CGColor {
    CGColor(red: red, green: green, blue: blue, alpha: alpha)
}

func savePNG(_ context: CGContext, width: Int, height: Int, name: String) {
    guard let image = context.makeImage() else {
        fatalError("Unable to create CGImage for \(name)")
    }

    let url = outputDirectory.appendingPathComponent(name)
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        fatalError("Unable to create PNG destination for \(name)")
    }

    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        fatalError("Unable to write \(url.path)")
    }
}

func fillRect(_ context: CGContext, _ rect: CGRect, _ fill: CGColor) {
    context.setFillColor(fill)
    context.fill(rect)
}

func strokeLine(_ context: CGContext, from start: Point, to end: Point, width: CGFloat, stroke: CGColor) {
    context.setStrokeColor(stroke)
    context.setLineWidth(width)
    context.setLineCap(.round)
    context.move(to: CGPoint(x: start.x, y: start.y))
    context.addLine(to: CGPoint(x: end.x, y: end.y))
    context.strokePath()
}

func fillPolygon(_ context: CGContext, _ points: [Point], fill: CGColor) {
    guard let first = points.first else {
        return
    }

    context.setFillColor(fill)
    context.move(to: CGPoint(x: first.x, y: first.y))
    for point in points.dropFirst() {
        context.addLine(to: CGPoint(x: point.x, y: point.y))
    }
    context.closePath()
    context.fillPath()
}

func strokePolygon(_ context: CGContext, _ points: [Point], width: CGFloat, stroke: CGColor) {
    guard let first = points.first else {
        return
    }

    context.setStrokeColor(stroke)
    context.setLineWidth(width)
    context.setLineJoin(.round)
    context.move(to: CGPoint(x: first.x, y: first.y))
    for point in points.dropFirst() {
        context.addLine(to: CGPoint(x: point.x, y: point.y))
    }
    context.closePath()
    context.strokePath()
}

func interpolateQuad(topLeft: Point, topRight: Point, bottomRight: Point, bottomLeft: Point, u: CGFloat, v: CGFloat) -> Point {
    let top = Point(
        x: topLeft.x + (topRight.x - topLeft.x) * u,
        y: topLeft.y + (topRight.y - topLeft.y) * u
    )
    let bottom = Point(
        x: bottomLeft.x + (bottomRight.x - bottomLeft.x) * u,
        y: bottomLeft.y + (bottomRight.y - bottomLeft.y) * u
    )
    return Point(
        x: top.x + (bottom.x - top.x) * v,
        y: top.y + (bottom.y - top.y) * v
    )
}

func generateHorizon() {
    let width = 1920
    let height = 1080
    let context = makeContext(width: width, height: height)
    fillRect(context, CGRect(x: 0, y: 0, width: width, height: height), color(0.08, 0.13, 0.18))

    let angle = CGFloat(8.0 * .pi / 180.0)
    let slope = tan(angle)
    let centerY = CGFloat(height) * 0.47
    let leftY = centerY + slope * (0 - CGFloat(width) / 2.0)
    let rightY = centerY + slope * (CGFloat(width) - CGFloat(width) / 2.0)
    let horizonLeft = Point(x: 0, y: leftY)
    let horizonRight = Point(x: CGFloat(width), y: rightY)

    fillPolygon(context, [
        Point(x: 0, y: 0),
        Point(x: CGFloat(width), y: 0),
        horizonRight,
        horizonLeft
    ], fill: color(0.13, 0.28, 0.42))

    fillPolygon(context, [
        horizonLeft,
        horizonRight,
        Point(x: CGFloat(width), y: CGFloat(height)),
        Point(x: 0, y: CGFloat(height))
    ], fill: color(0.08, 0.24, 0.18))

    for offset in stride(from: -220, through: 260, by: 60) {
        let dy = CGFloat(offset)
        strokeLine(
            context,
            from: Point(x: -100, y: leftY + dy),
            to: Point(x: CGFloat(width) + 100, y: rightY + dy),
            width: offset == 0 ? 8 : 3,
            stroke: offset == 0 ? color(1, 1, 1) : color(0.58, 0.78, 0.86, 0.65)
        )
    }

    savePNG(context, width: width, height: height, name: "horizon-tilted-8deg.png")
}

func generateQuadPhone() {
    let width = 1920
    let height = 1080
    let context = makeContext(width: width, height: height)
    fillRect(context, CGRect(x: 0, y: 0, width: width, height: height), color(0.04, 0.045, 0.055))

    let topLeft = Point(x: 520, y: 210)
    let topRight = Point(x: 1390, y: 305)
    let bottomRight = Point(x: 1285, y: 890)
    let bottomLeft = Point(x: 430, y: 790)
    let quad = [topLeft, topRight, bottomRight, bottomLeft]

    strokeLine(context, from: Point(x: 160, y: 185), to: Point(x: 1760, y: 965), width: 3, stroke: color(0.35, 0.35, 0.38, 0.4))
    fillPolygon(context, quad, fill: color(0.03, 0.08, 0.09))

    for index in 0...10 {
        let value = CGFloat(index) / 10.0
        let start = interpolateQuad(topLeft: topLeft, topRight: topRight, bottomRight: bottomRight, bottomLeft: bottomLeft, u: value, v: 0)
        let end = interpolateQuad(topLeft: topLeft, topRight: topRight, bottomRight: bottomRight, bottomLeft: bottomLeft, u: value, v: 1)
        strokeLine(context, from: start, to: end, width: index == 0 || index == 10 ? 5 : 2, stroke: color(0.95, 0.97, 1.0))
    }

    for index in 0...14 {
        let value = CGFloat(index) / 14.0
        let start = interpolateQuad(topLeft: topLeft, topRight: topRight, bottomRight: bottomRight, bottomLeft: bottomLeft, u: 0, v: value)
        let end = interpolateQuad(topLeft: topLeft, topRight: topRight, bottomRight: bottomRight, bottomLeft: bottomLeft, u: 1, v: value)
        strokeLine(context, from: start, to: end, width: index == 0 || index == 14 ? 5 : 2, stroke: color(0.95, 0.97, 1.0))
    }

    strokePolygon(context, quad, width: 12, stroke: color(0.0, 0.0, 0.0))
    strokePolygon(context, quad, width: 5, stroke: color(1.0, 0.72, 0.2))
    savePNG(context, width: width, height: height, name: "quad-phone-screen.png")
}

func generateUprightFacade() {
    let width = 1920
    let height = 1080
    let context = makeContext(width: width, height: height)
    fillRect(context, CGRect(x: 0, y: 0, width: width, height: height), color(0.1, 0.1, 0.11))

    let topLeft = Point(x: 640, y: 110)
    let topRight = Point(x: 1280, y: 135)
    let bottomRight = Point(x: 1460, y: 980)
    let bottomLeft = Point(x: 460, y: 940)
    let facade = [topLeft, topRight, bottomRight, bottomLeft]
    fillPolygon(context, facade, fill: color(0.16, 0.18, 0.2))

    for index in 0...16 {
        let value = CGFloat(index) / 16.0
        let start = interpolateQuad(topLeft: topLeft, topRight: topRight, bottomRight: bottomRight, bottomLeft: bottomLeft, u: value, v: 0)
        let end = interpolateQuad(topLeft: topLeft, topRight: topRight, bottomRight: bottomRight, bottomLeft: bottomLeft, u: value, v: 1)
        strokeLine(context, from: start, to: end, width: index == 0 || index == 16 ? 5 : 3, stroke: color(0.9, 0.92, 0.92))
    }

    for index in 0...12 {
        let value = CGFloat(index) / 12.0
        let start = interpolateQuad(topLeft: topLeft, topRight: topRight, bottomRight: bottomRight, bottomLeft: bottomLeft, u: 0, v: value)
        let end = interpolateQuad(topLeft: topLeft, topRight: topRight, bottomRight: bottomRight, bottomLeft: bottomLeft, u: 1, v: value)
        strokeLine(context, from: start, to: end, width: index == 0 || index == 12 ? 5 : 3, stroke: color(0.86, 0.88, 0.88))
    }

    for row in 0..<5 {
        for column in 0..<7 {
            let u0 = CGFloat(column) / 7.0 + 0.035
            let u1 = CGFloat(column + 1) / 7.0 - 0.035
            let v0 = CGFloat(row) / 5.0 + 0.04
            let v1 = CGFloat(row + 1) / 5.0 - 0.04
            let a = interpolateQuad(topLeft: topLeft, topRight: topRight, bottomRight: bottomRight, bottomLeft: bottomLeft, u: u0, v: v0)
            let b = interpolateQuad(topLeft: topLeft, topRight: topRight, bottomRight: bottomRight, bottomLeft: bottomLeft, u: u1, v: v0)
            let c = interpolateQuad(topLeft: topLeft, topRight: topRight, bottomRight: bottomRight, bottomLeft: bottomLeft, u: u1, v: v1)
            let d = interpolateQuad(topLeft: topLeft, topRight: topRight, bottomRight: bottomRight, bottomLeft: bottomLeft, u: u0, v: v1)
            fillPolygon(context, [a, b, c, d], fill: color(0.05, 0.09, 0.13))
            strokePolygon(context, [a, b, c, d], width: 1.5, stroke: color(0.55, 0.66, 0.72))
        }
    }

    strokePolygon(context, facade, width: 7, stroke: color(1.0, 0.72, 0.2))
    savePNG(context, width: width, height: height, name: "upright-facade-perspective.png")
}

generateHorizon()
generateQuadPhone()
generateUprightFacade()

print("Generated test assets in \(outputDirectory.path)")
