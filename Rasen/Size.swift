// Copyright 2025 Cii
//
// This file is part of Rasen.
//
// Rasen is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Rasen is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with Rasen.  If not, see <http://www.gnu.org/licenses/>.

struct Size: Hashable {
    var width = 0.0, height = 0.0
}
extension Size: Protobuf {
    init(_ pb: PBSize) throws {
        width = try pb.width.notNaN()
        height = try pb.height.notNaN()
    }
    var pb: PBSize {
        .with {
            $0.width = width
            $0.height = height
        }
    }
}
extension Size: Codable {
    init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        width = try container.decode(Double.self)
        height = try container.decode(Double.self)
    }
    func encode(to encoder: any Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(width)
        try container.encode(height)
    }
}
extension Size {
    init(width: Int, height: Int) {
        self.width = Double(width)
        self.height = Double(height)
    }
    init(square: Int) {
        self.init(width: square, height: square)
    }
    init(square: Double) {
        self.init(width: square, height: square)
    }
    init(_ p: Point) {
        self.init(width: p.x, height: p.y)
    }
    
    prefix static func - (x: Size) -> Size {
        Size(width: -x.width, height: -x.height)
    }
    
    func reversed() -> Size {
        Size(width: height, height: width)
    }
    
    var isEmpty: Bool {
        width == 0 && height == 0
    }
    var area: Double {
        width * height
    }
    var minElement: Double {
        min(width, height)
    }
    var maxElement: Double {
        max(width, height)
    }
    var diagonal: Double {
        .hypot(width, height)
    }
    func contains(_ other: Size) -> Bool {
        width >= other.width && height >= other.height
    }
    func intersects(_ other: Size) -> Bool {
        width >= other.width || height >= other.height
    }
    
    func snapped(max maxSize: Size) -> Size {
        if width <= 0 || height <= 0 || self == maxSize {
            return self
        } else {
            let h = height * maxSize.width / width
            if h < maxSize.height {
                return Size(width: maxSize.width, height: h)
            } else {
                let w = width * maxSize.height / height
                return Size(width: w, height: maxSize.height)
            }
        }
    }
    func snapped(min minSize: Size) -> Size {
        if width <= 0 || height <= 0 || self == minSize {
            return self
        } else {
            let h = height * minSize.width / width
            if h > minSize.height {
                return Size(width: minSize.width, height: h)
            } else {
                let w = width * minSize.height / height
                return Size(width: w, height: minSize.height)
            }
        }
    }
    func snapped(width: Double) -> Size {
        if self.width <= 0 || height <= 0 || width == self.width {
            self
        } else {
            .init(width: width, height: height * width / self.width)
        }
    }
    func snapped(height: Double) -> Size {
        if width <= 0 || self.height <= 0 || height == self.height {
            self
        } else {
            .init(width: width * height / self.height, height: height)
        }
    }
    
    static func + (lhs: Size, rhs: Double) -> Size {
        Size(width: lhs.width + rhs, height: lhs.height + rhs)
    }
    static func + (lhs: Size, rhs: Size) -> Size {
        Size(width: lhs.width + rhs.width,
             height: lhs.height + rhs.height)
    }
    static func * (lhs: Size, rhs: Double) -> Size {
        Size(width: lhs.width * rhs, height: lhs.height * rhs)
    }
    static func *= (lhs: inout Size, rhs: Double) {
        lhs.width *= rhs
        lhs.height *= rhs
    }
    static func / (lhs: Size, rhs: Double) -> Size {
        Size(width: lhs.width / rhs, height: lhs.height / rhs)
    }
    static func /= (lhs: inout Size, rhs: Double) {
        lhs.width /= rhs
        lhs.height /= rhs
    }
    
    func rounded(_ rule: FloatingPointRoundingRule = .toNearestOrAwayFromZero) -> Size {
        Size(width: width.rounded(rule), height: height.rounded(rule))
    }
    mutating func round(decimalPlaces: Int) {
        self = Size(width: width.rounded(decimalPlaces: decimalPlaces),
                    height: height.rounded(decimalPlaces: decimalPlaces))
    }
    func rounded(decimalPlaces: Int) -> Size {
        Size(width: width.rounded(decimalPlaces: decimalPlaces),
             height: height.rounded(decimalPlaces: decimalPlaces))
    }
    
    func notInfiniteAndNAN() throws -> Size {
        if width.isNaN || width.isInfinite
            || height.isNaN || height.isInfinite {
            
            throw ProtobufError()
        } else {
            return self
        }
    }
    func notInfinite() throws -> Size {
        if width.isInfinite || height.isInfinite {
            throw ProtobufError()
        } else {
            return self
        }
    }
}
extension Size: AppliableTransform {
    static func * (lhs: Size, rhs: Transform) -> Size {
        Size(width: rhs[0][0] * lhs.width + rhs[1][0] * lhs.height,
             height: rhs[0][1] * lhs.width + rhs[1][1] * lhs.height)
    }
}
extension Size: Interpolatable {
    static func linear(_ f0: Size, _ f1: Size, t: Double) -> Size {
        Size(width: Double.linear(f0.width, f1.width, t: t),
             height: Double.linear(f0.height, f1.height, t: t))
    }
    static func firstSpline(_ f1: Size,
                            _ f2: Size, _ f3: Size, t: Double) -> Size {
        Size(width: Double.firstSpline(f1.width,
                                       f2.width, f3.width, t: t),
             height: Double.firstSpline(f1.height,
                                        f2.height, f3.height, t: t))
    }
    static func spline(_ f0: Size, _ f1: Size,
                       _ f2: Size, _ f3: Size, t: Double) -> Size {
        Size(width: Double.spline(f0.width, f1.width,
                                  f2.width, f3.width, t: t),
             height: Double.spline(f0.height, f1.height,
                                   f2.height, f3.height, t: t))
    }
    static func lastSpline(_ f0: Size, _ f1: Size,
                           _ f2: Size, t: Double) -> Size {
        Size(width: Double.lastSpline(f0.width, f1.width,
                                      f2.width, t: t),
             height: Double.lastSpline(f0.height, f1.height,
                                       f2.height, t: t))
    }
}
extension Size {
    static func < (lhs: Size, rhs: Size) -> Bool {
        lhs.area < rhs.area
    }
    static func > (lhs: Size, rhs: Size) -> Bool {
        lhs.area > rhs.area
    }
}
