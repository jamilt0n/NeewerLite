//
//  ColorWheel.swift
//  NeewerLite
//
//  Created by Xu Lian on 1/16/21.
//

import Foundation
import AppKit

protocol ColorWheelDelegate: AnyObject {
    func hueAndSaturationSelected(_ hue: CGFloat, saturation: CGFloat)
}

class ColorWheel: NSView {
    var color: NSColor!

    // Layer for the Hue and Saturation wheel
    var wheelLayer: CALayer!

    var offset: CGFloat = 15.0
    // Layer for the indicator
    var indicatorLayer: CAShapeLayer!
    var indicatorCircleRadius: CGFloat = 8.0
    var indicatorColor: CGColor = NSColor.gray.cgColor
    var indicatorBorderWidth: CGFloat = 1.0
    var lastHueValue: CGFloat = 0.0
    var point: CGPoint!
    var mTag = -1

    // Retina scaling factor
    lazy var scale: CGFloat = {
        if let win = self.window {
            if let screen = win.screen {
                return screen.backingScaleFactor
            }
        }
        return 2.0
    }()

    weak var delegate: ColorWheelDelegate?
    var callback: ((_ hue: CGFloat, _ saturation: CGFloat) -> Void)?

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setupView(NSColor(calibratedHue: 0.0, saturation: 0.0, brightness: 1.0, alpha: 1.0))
    }

    init(frame: CGRect, color: NSColor!) {
        super.init(frame: frame)
        setupView(color)
    }

    override var tag: Int {
        get {
            return mTag
        }
        set {
            mTag = newValue
        }
    }

    private func setupView(_ color: NSColor!) {
        self.wantsLayer = true
        self.layer = CALayer()

        self.color = color

        // Layer for the Hue/Saturation wheel
        wheelLayer = CALayer()
        wheelLayer.frame = CGRect(x: offset, y: offset, width: self.frame.width-offset-offset, height: self.frame.height-offset-offset)
        // wheelLayer.contents = createColorWheel(wheelLayer.frame.size)
        wheelLayer.contents = NSImage(named: "colorWheel")
        wheelLayer.transform = CATransform3DMakeScale(1, -1, 1)
        self.layer!.addSublayer(wheelLayer)

        // Layer for the indicator
        indicatorLayer = CAShapeLayer()
        indicatorLayer.strokeColor = indicatorColor
        indicatorLayer.lineWidth = indicatorBorderWidth
        indicatorLayer.fillColor = nil
        self.layer!.addSublayer(indicatorLayer)

        setViewColor(color)
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        indicatorCircleRadius = 10.0
        drawIndicator()
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        indicatorCircleRadius = 8.0
        drawIndicator()
    }

    override func mouseDragged(with event: NSEvent) {
        super.mouseDragged(with: event)

        point = self.convert(event.locationInWindow, from: nil)
        let indicator = getIndicatorCoordinate(point)
        point = indicator.point

        var color = (hue: CGFloat(0), saturation: CGFloat(0))
        if !indicator.isCenter {
            color = hueSaturationAtPoint(CGPoint(x: (point.x-offset)*scale, y: (point.y-offset)*scale))
        }

        self.color = NSColor(hue: color.hue, saturation: color.saturation, brightness: 1.0, alpha: 1.0)

        if let safeDelegate = delegate {
            // Notify delegate of the new Hue and Saturation
            safeDelegate.hueAndSaturationSelected(color.hue, saturation: color.saturation)
        }

        if let safeCallback = callback {
            safeCallback(color.hue, color.saturation)
        }

        // Draw the indicator
        drawIndicator()
    }

    private func drawIndicator() {
        // Draw the indicator
        if point != nil {
            indicatorLayer.path = NSBezierPath(roundedRect: NSRect(x: point.x-indicatorCircleRadius,
                                                                   y: point.y-indicatorCircleRadius,
                                                                   width: indicatorCircleRadius*2.0,
                                                                   height: indicatorCircleRadius*2.0),
                                               xRadius: indicatorCircleRadius,
                                               yRadius: indicatorCircleRadius).cgPath
            indicatorLayer.fillColor = self.color.cgColor
        }
    }

    private func getIndicatorCoordinate(_ coord: CGPoint) -> (point: CGPoint, isCenter: Bool) {
        // Making sure that the indicator can't get outside the Hue and Saturation wheel

        let dimension: CGFloat = min(wheelLayer.frame.width, wheelLayer.frame.height)
        let radius: CGFloat = dimension/2
        let wheelLayerCenter: CGPoint = CGPoint(x: wheelLayer.frame.origin.x + radius, y: wheelLayer.frame.origin.y + radius)

        let deltaX: CGFloat = coord.x - wheelLayerCenter.x
        let deltaY: CGFloat = coord.y - wheelLayerCenter.y
        let distance: CGFloat = sqrt(deltaX*deltaX + deltaY*deltaY)
        var outputCoord: CGPoint = coord

        // If the touch coordinate is outside the radius of the wheel, transform it to the edge of the wheel with polar coordinates
        if distance > radius {
            let theta: CGFloat = atan2(deltaY, deltaX)
            outputCoord.x = radius * cos(theta) + wheelLayerCenter.x
            outputCoord.y = radius * sin(theta) + wheelLayerCenter.y
        }

        // If the touch coordinate is close to center, focus it to the very center at set the color to white
        let whiteThreshold: CGFloat = 5
        var isCenter = false
        if distance < whiteThreshold {
            outputCoord.x = wheelLayerCenter.x
            outputCoord.y = wheelLayerCenter.y
            isCenter = true
        }
        return (outputCoord, isCenter)
    }

    private func createColorWheel(_ size: CGSize) -> CGImage {
        // Creates a bitmap of the Hue Saturation wheel
        let originalWidth: CGFloat = size.width
        let originalHeight: CGFloat = size.height
        let dimension: CGFloat = min(originalWidth*scale, originalHeight*scale)
        let bufferLength: Int = Int(dimension * dimension * 4)

        let bitmapData: CFMutableData = CFDataCreateMutable(nil, 0)
        CFDataSetLength(bitmapData, CFIndex(bufferLength))
        let bitmap = CFDataGetMutableBytePtr(bitmapData)

        for offY in stride(from: CGFloat(0), to: dimension, by: CGFloat(1)) {
            for offX in stride(from: CGFloat(0), to: dimension, by: CGFloat(1)) {
                var hsv: HSB = HSB(hue: 0, saturation: 0, brightness: 0, alpha: 0)
                var rgb: RGB = RGB(red: 0, green: 0, blue: 0, alpha: 0)

                let color = hueSaturationAtPoint(CGPoint(x: offX, y: offY))
                let hue = color.hue
                let saturation = color.saturation
                var alpha: CGFloat = 0.0
                if saturation < 1.0 {
                    // Antialias the edge of the circle.
                    if saturation > 0.99 {
                        alpha = (1.0 - saturation) * 100
                    } else {
                        alpha = 1.0
                    }

                    hsv.hue = hue
                    hsv.saturation = saturation
                    hsv.brightness = 1.0
                    hsv.alpha = alpha
                    rgb = hsv2rgb(hsv)
                }
                let offset = Int(4 * (offX + offY * dimension))
                bitmap?[offset] = UInt8(rgb.red*255)
                bitmap?[offset + 1] = UInt8(rgb.green*255)
                bitmap?[offset + 2] = UInt8(rgb.blue*255)
                bitmap?[offset + 3] = UInt8(rgb.alpha*255)
            }
        }

        // Convert the bitmap to a CGImage
        let colorSpace: CGColorSpace? = CGColorSpaceCreateDeviceRGB()
        let dataProvider: CGDataProvider? = CGDataProvider(data: bitmapData)
        let bitmapInfo = CGBitmapInfo(rawValue: CGBitmapInfo().rawValue | CGImageAlphaInfo.last.rawValue)
        let imageRef: CGImage? = CGImage(width: Int(dimension),
                                         height: Int(dimension),
                                         bitsPerComponent: 8,
                                         bitsPerPixel: 32,
                                         bytesPerRow: Int(dimension) * 4,
                                         space: colorSpace!,
                                         bitmapInfo: bitmapInfo,
                                         provider: dataProvider!,
                                         decode: nil,
                                         shouldInterpolate: false,
                                         intent: CGColorRenderingIntent.defaultIntent)

        return imageRef!
    }

    private func hueSaturationAtPoint(_ position: CGPoint) -> (hue: CGFloat, saturation: CGFloat) {
        // Get hue and saturation for a given point (x,y) in the wheel

        let ratio = wheelLayer.frame.width * scale / 2.0
        let deltaX = CGFloat(position.x - ratio) / ratio
        let deltaY = CGFloat(position.y - ratio) / ratio
        let delta = sqrt(CGFloat(deltaX * deltaX + deltaY * deltaY))

        var saturation: CGFloat = delta

        if saturation > 0.98 {
            saturation = 1.0
        }

        var hue: CGFloat
        if delta == 0 {
            hue = 0
        } else {
            hue = acos(deltaX/delta) / CGFloat.pi / 2.0
            if deltaY < 0 {
                hue = 1.0 - hue
            }
        }
        return (hue, saturation)
    }

    func setSaturation(_ sat: CGFloat) {
        var hue: CGFloat = 0.0, saturation: CGFloat = 0.0, brightness: CGFloat = 0.0, alpha: CGFloat = 0.0
        color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        if sat == 0 {
            if  hue > 0 {
                lastHueValue = hue
            }
        } else {
            if hue == 0 && lastHueValue > 0 {
                hue = lastHueValue
                lastHueValue = 0
            }
        }

        self.color = NSColor(hue: hue, saturation: sat, brightness: brightness, alpha: alpha)

        point = pointAtHueSaturation(hue, saturation: sat)
        drawIndicator()
    }

    private func pointAtHueSaturation(_ hue: CGFloat, saturation: CGFloat) -> CGPoint {
        // Get a point (x,y) in the wheel for a given hue and saturation

        let dimension: CGFloat = min(wheelLayer.frame.width, wheelLayer.frame.height)
        let radius: CGFloat = saturation * dimension / 2
        let offsetX = dimension / 2 + radius * cos(hue * CGFloat.pi * 2) + 20
        let offsetY = dimension / 2 + radius * sin(hue * CGFloat.pi * 2) + 20
        return CGPoint(x: offsetX, y: offsetY)
    }

    func setViewColor(_ color: NSColor!) {
        // Update the entire view with a given color

        var hue: CGFloat = 0.0, saturation: CGFloat = 0.0, brightness: CGFloat = 0.0, alpha: CGFloat = 0.0
        color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        if color.saturationComponent == 0 {
            if  hue > 0 {
                lastHueValue = hue
            }
        } else {
            if hue == 0 && lastHueValue > 0 {
                hue = lastHueValue
                lastHueValue = 0
            }
        }

        self.color = color

        point = pointAtHueSaturation(hue, saturation: saturation)
        drawIndicator()
    }
}
