import UIKit

struct TouchSample {
    var time: TimeInterval?
    var position: CGPoint
    var majorRadius: Double
}

extension TouchSample: Equatable {
    static func ==(left: TouchSample, right: TouchSample) -> Bool {
        return left.time == right.time &&
            left.position == right.position &&
            left.majorRadius == right.majorRadius
    }
}

extension TouchSample {
    var touchesSample: Touches_Sample {
        var position = Touches_Vector()
        position.x = Double(self.position.x)
        position.y = Double(self.position.y)
        
        var sample = Touches_Sample()
        sample.time = time ?? -1
        sample.position = position
        sample.majorRadius = majorRadius
        return sample
    }
    
    init(touchesSample: Touches_Sample) {
        time = (touchesSample.time != -1) ? touchesSample.time : nil
        position = CGPoint(
            x: CGFloat(touchesSample.position.x),
            y: CGFloat(touchesSample.position.y)
        )
        majorRadius = touchesSample.majorRadius
    }
}

struct Stroke {
    var samples = [TouchSample]()
}

extension Stroke: Equatable {
    static func ==(left: Stroke, right: Stroke) -> Bool {
        return left.samples == right.samples
    }
}

extension Stroke {
    var touchesStroke: Touches_Stroke {
        var stroke = Touches_Stroke()
        stroke.samples = samples.map { $0.touchesSample }
        return stroke
    }
    
    init(touchesStroke: Touches_Stroke) {
        samples = touchesStroke.samples.map { TouchSample(touchesSample: $0) }
    }
}

struct Drawing {
    var strokes = [Stroke]()
}

extension Drawing: Equatable {
    static func ==(left: Drawing, right: Drawing) -> Bool {
        return left.strokes == right.strokes
    }
}

extension Drawing {
    var touchesDrawing: Touches_Drawing {
        var drawing = Touches_Drawing()
        drawing.strokes = strokes.map { $0.touchesStroke }
        return drawing
    }
    
    init(touchesDrawing: Touches_Drawing) {
        strokes = touchesDrawing.strokes.map { Stroke(touchesStroke: $0) }
    }
}

protocol RectangleBounded {
    var boundingRect: CGRect { get }
}

extension Stroke: RectangleBounded {
    var boundingRect: CGRect {
        guard let first = samples.first else {
            return CGRect.zero
        }
        
        var left = first.position.x
        var right = first.position.x
        var top = first.position.y
        var bottom = first.position.y
        
        for sample in samples {
            let position = sample.position
            
            if position.x < left {
                left = position.x
            }
            
            if right < position.x {
                right = position.x
            }
            
            if position.y < top {
                top = position.y
            }
            
            if bottom < position.y {
                bottom = position.y
            }
        }
        
        return CGRect(origin: CGPoint(x: left, y: top), size: CGSize(width: right - left, height: bottom - top))
    }
}

extension Drawing: RectangleBounded {
    var boundingRect: CGRect {
        guard let first = strokes.first?.boundingRect else {
            return CGRect.zero
        }
        
        return strokes.reduce(first, { (superRect, nextStroke) in
            superRect.union(nextStroke.boundingRect)
        })
    }
}

extension Drawing {
    func fitIn(rect: CGRect) -> (Drawing, CGFloat) {
        let containerAspectRatio = rect.width / rect.height
        let boundingRect = self.boundingRect
        let boundingAspectRatio = boundingRect.width / boundingRect.height
        
        var scaleFactor: CGFloat = 1
        
        if boundingAspectRatio > containerAspectRatio {
            scaleFactor = rect.width / boundingRect.width
        } else {
            scaleFactor = rect.height / boundingRect.height
        }
        
        let newSize = CGSize(width: boundingRect.width * scaleFactor, height: boundingRect.height * scaleFactor)
        let newOrigin = CGPoint(
            x: rect.origin.x + rect.width / 2.0 - newSize.width / 2.0,
            y: rect.origin.y + rect.height / 2.0 - newSize.height / 2.0
        )
        
        var newDrawing = Drawing()
        
        for stroke in strokes {
            var newStroke = Stroke()
            
            for sample in stroke.samples {
                var sample = sample
                
                let position = sample.position
                let newPosition = CGPoint(
                    x: (position.x - boundingRect.origin.x) * scaleFactor + newOrigin.x,
                    y: (position.y - boundingRect.origin.y) * scaleFactor + newOrigin.y
                )
                
                sample.position = newPosition
                
                newStroke.samples.append(sample)
            }
            
            newDrawing.strokes.append(newStroke)
        }
        
        return (newDrawing, scaleFactor)
    }
    
    func rasterized() -> UIImage? {
        let fitInBoxOfSize: Int = 35
        let finalSize: Int = 45
        let margin: CGFloat = CGFloat(finalSize - fitInBoxOfSize) / 2.0
        let imageSize = CGSize(width: finalSize, height: finalSize)
        
        let (fitDrawing, scaleFactor) = fitIn(
            rect: CGRect(
                origin: CGPoint(x: margin, y: margin),
                size: CGSize(width: fitInBoxOfSize, height: fitInBoxOfSize)
            )
        )
        
        let strokeWidth: CGFloat = 8.0 * scaleFactor //8 is original stroke line width
        
        UIGraphicsBeginImageContextWithOptions(imageSize, true, 1)
        
        guard let context = UIGraphicsGetCurrentContext() else {
            UIGraphicsEndImageContext()
            return nil
        }
        
        // Black background
        context.setFillColor(UIColor.black.cgColor)
        context.fill(CGRect(origin: .zero, size: imageSize))
        
        // White touch strokes
        context.setStrokeColor(UIColor.white.cgColor)
        context.setLineWidth(strokeWidth)
        
        context.setLineCap(.round)
        context.setLineJoin(.round)
        
        for stroke in fitDrawing.strokes {
            var isFirst = true

            for sample in stroke.samples {
                if isFirst {
                    context.move(to: sample.position)
                } else {
                    context.addLine(to: sample.position)
                }

                isFirst = false
            }
        }
        
        context.strokePath()
        
        let image = UIGraphicsGetImageFromCurrentImageContext()
        
        UIGraphicsEndImageContext()
        
        return image
    }
    
    var touchesImage: Touches_Image? {
        guard let image = rasterized(), let grays = imageToGrayscaleValues(image: image) else {
            return nil
        }
        
        var touchesImage = Touches_Image()
        touchesImage.height = Int32(image.size.height)
        touchesImage.width = Int32(image.size.width)
        touchesImage.values = Data(grays)
        
        return touchesImage
    }
}

func imageToGrayscaleValues(image: UIImage) -> [UInt8]? {
    guard let cgImage = image.cgImage else {
        return nil
    }
    
    let width = cgImage.width
    let height = cgImage.height
    let bitsPerComponent = cgImage.bitsPerComponent
    let bytesPerRow = width
    let totalBytes = bytesPerRow * height
    
    let colorSpace = CGColorSpaceCreateDeviceGray()
    var intensities = [UInt8](repeating: 0, count: totalBytes)
    
    guard let context = CGContext(data: &intensities, width: width, height: height, bitsPerComponent: bitsPerComponent, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: 0) else {
        return nil
    }
    
    context.draw(cgImage, in: CGRect(x: 0.0, y: 0.0, width: CGFloat(width), height: CGFloat(height)))
    
    return intensities
}
