import Foundation
import CoreGraphics
import Testing
@testable import TesseraCore

private let geometryFrames = [
    CGRect(x: 0, y: 24, width: 1440, height: 876),
    CGRect(x: -2560, y: 0, width: 2560, height: 1417),
    CGRect(x: 0, y: 900, width: 1728, height: 1080),
    CGRect(x: 1920, y: -1440, width: 2560, height: 1440),
    CGRect(x: -100.2, y: -47.7, width: 1000.9, height: 700.4),
]

@Test func defaultFramesReserveEqualInnerAndOuterGaps() throws {
    let screen = CGRect(x: 0, y: 24, width: 1440, height: 876)
    let first = try GridGeometry.frame(in: screen, layout: .threeByTwo, zoneID: 1, gap: 8, scale: 2)
    let last = try GridGeometry.frame(in: screen, layout: .threeByTwo, zoneID: 6, gap: 8, scale: 2)
    #expect(first == CGRect(x: 8, y: 466, width: 469.5, height: 426))
    #expect(last == CGRect(x: 963, y: 32, width: 469, height: 426))
}

@Test(arguments: LayoutPreset.allCases)
func everyZoneFitsAndPreservesPixelGapsAcrossDisplays(_ layout: LayoutPreset) throws {
    for screen in geometryFrames {
        for scale: CGFloat in [1, 2] {
            for gap: CGFloat in [0, 4, 8, 12] {
                let frames = try layout.zones.map {
                    try GridGeometry.frame(in: screen, layout: layout, zoneID: $0.id, gap: gap, scale: scale)
                }
                let minX = (screen.minX * scale).rounded(.up) / scale
                let minY = (screen.minY * scale).rounded(.up) / scale
                let maxX = (screen.maxX * scale).rounded(.down) / scale
                let maxY = (screen.maxY * scale).rounded(.down) / scale
                for (index, frame) in frames.enumerated() {
                    #expect(screen.contains(frame))
                    #expect(frame.width > 0 && frame.height > 0)
                    for value in [frame.minX, frame.minY, frame.maxX, frame.maxY] {
                        #expect(value * scale == (value * scale).rounded())
                    }
                    let column = index % layout.columns
                    let row = index / layout.columns
                    if column == 0 { #expect(frame.minX - minX == gap) }
                    if column == layout.columns - 1 { #expect(maxX - frame.maxX == gap) }
                    if row == 0 { #expect(maxY - frame.maxY == gap) }
                    if row == layout.rows - 1 { #expect(frame.minY - minY == gap) }
                    if column + 1 < layout.columns {
                        let neighbor = frames[index + 1]
                        #expect(neighbor.minX - frame.maxX == gap)
                        #expect(abs(neighbor.width - frame.width) <= 1 / scale)
                    }
                    if row + 1 < layout.rows {
                        let neighbor = frames[index + layout.columns]
                        #expect(frame.minY - neighbor.maxY == gap)
                        #expect(abs(neighbor.height - frame.height) <= 1 / scale)
                    }
                }
            }
        }
    }
}

@Test func zeroGapUsesSharedBoundariesWhenPixelsDoNotDivideEvenly() throws {
    let screen = CGRect(x: -27, y: -31, width: 1001, height: 701)
    for layout in LayoutPreset.allCases {
        let frames = try layout.zones.map {
            try GridGeometry.frame(in: screen, layout: layout, zoneID: $0.id, gap: 0, scale: 1)
        }
        #expect(frames.map { $0.width * $0.height }.reduce(0, +) == screen.width * screen.height)
        #expect(frames.first?.minX == screen.minX)
        #expect(frames.first?.maxY == screen.maxY)
        #expect(frames.last?.maxX == screen.maxX)
        #expect(frames.last?.minY == screen.minY)
        for index in frames.indices {
            if index % layout.columns != layout.columns - 1 {
                #expect(frames[index].maxX == frames[index + 1].minX)
            }
            if index < layout.columns {
                #expect(frames[index].minY == frames[index + layout.columns].maxY)
            }
        }
    }
}

@Test func fractionalGapRoundsOnceToBackingPixel() throws {
    let screen = CGRect(x: 0, y: 0, width: 1000, height: 700)
    let first = try GridGeometry.frame(in: screen, layout: .threeByTwo, zoneID: 1, gap: 0.3, scale: 2)
    let next = try GridGeometry.frame(in: screen, layout: .threeByTwo, zoneID: 2, gap: 0.3, scale: 2)
    #expect(first.minX == 0.5)
    #expect(screen.maxY - first.maxY == 0.5)
    #expect(next.minX - first.maxX == 0.5)
}

@Test func invalidGeometryInputsProduceExplicitErrors() {
    let valid = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let invalidFrames = [
        CGRect.zero,
        CGRect(x: 0, y: 0, width: -100, height: 100),
        CGRect(x: 0, y: 0, width: 100, height: -100),
        CGRect(x: CGFloat.nan, y: 0, width: 100, height: 100),
        CGRect(x: 0, y: CGFloat.infinity, width: 100, height: 100),
        CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 100),
        CGRect(x: CGFloat.greatestFiniteMagnitude, y: 0, width: CGFloat.greatestFiniteMagnitude, height: 100),
    ]
    for frame in invalidFrames {
        #expect(throws: GridGeometryError.invalidVisibleFrame) {
            try GridGeometry.frame(in: frame, layout: .threeByTwo, zoneID: 1, gap: 8, scale: 2)
        }
    }
    for gap: CGFloat in [-1, .nan, .infinity] {
        #expect(throws: GridGeometryError.invalidGap) {
            try GridGeometry.frame(in: valid, layout: .threeByTwo, zoneID: 1, gap: gap, scale: 2)
        }
    }
    for scale: CGFloat in [0, -1, .nan, .infinity] {
        #expect(throws: GridGeometryError.invalidScale) {
            try GridGeometry.frame(in: valid, layout: .threeByTwo, zoneID: 1, gap: 8, scale: scale)
        }
    }
    for layout in LayoutPreset.allCases {
        for zone in [-1, 0, layout.columns * layout.rows + 1, Int.max] {
            #expect(throws: GridGeometryError.invalidZoneID(zone)) {
                try GridGeometry.frame(in: valid, layout: layout, zoneID: zone, gap: 8, scale: 2)
            }
        }
    }
}

@Test func geometryRejectsInsufficientPixelsAndArithmeticOverflow() {
    for (frame, gap) in [
        (CGRect(x: 0, y: 0, width: 3, height: 2), CGFloat(1)),
        (CGRect(x: 0, y: 0, width: 0.2, height: 0.2), CGFloat(0)),
        (CGRect(x: 0, y: 0, width: 100, height: 100), CGFloat(100)),
    ] {
        #expect(throws: GridGeometryError.insufficientSpace) {
            try GridGeometry.frame(in: frame, layout: .threeByTwo, zoneID: 1, gap: gap, scale: 1)
        }
    }
    #expect(throws: GridGeometryError.unsupportedCoordinateRange) {
        try GridGeometry.frame(
            in: CGRect(x: 1e100, y: 0, width: 1e100, height: 100),
            layout: .threeByTwo, zoneID: 1, gap: 0, scale: 2
        )
    }
    #expect(throws: GridGeometryError.unsupportedCoordinateRange) {
        try GridGeometry.frame(
            in: CGRect(x: 0, y: 0, width: 1000, height: 700),
            layout: .threeByTwo, zoneID: 1, gap: 8, scale: CGFloat.greatestFiniteMagnitude
        )
    }
}

@Test func exactlyOnePixelPerZoneIsValid() throws {
    let frame = try GridGeometry.frame(
        in: CGRect(x: 0, y: 0, width: 3, height: 2), layout: .threeByTwo, zoneID: 6, gap: 0, scale: 1
    )
    #expect(frame == CGRect(x: 2, y: 0, width: 1, height: 1))
}

@Test(arguments: LayoutPreset.allCases)
func placementTargetsPreserveExistingZoneFrames(_ layout: LayoutPreset) throws {
    for screen in geometryFrames {
        for zone in layout.zones {
            let original = try GridGeometry.frame(in: screen, layout: layout, zoneID: zone.id, gap: 8, scale: 2)
            let target = try GridGeometry.frame(in: screen, layout: layout, target: .zone(zone.id), gap: 8, scale: 2)
            #expect(target == original)
        }
    }
}

@Test(arguments: LayoutPreset.allCases)
func fullColumnFramesIncludeMiddleGapAndPreserveOuterPixelBounds(_ layout: LayoutPreset) throws {
    for screen in geometryFrames {
        for scale: CGFloat in [1, 2] {
            for gap: CGFloat in [0, 4, 8, 12] {
                let minY = (screen.minY * scale).rounded(.up) / scale
                let maxY = (screen.maxY * scale).rounded(.down) / scale
                for column in 1...layout.columns {
                    let full = try GridGeometry.frame(in: screen, layout: layout, target: .column(column), gap: gap, scale: scale)
                    let top = try GridGeometry.frame(in: screen, layout: layout, zoneID: column, gap: gap, scale: scale)
                    let bottom = try GridGeometry.frame(in: screen, layout: layout, zoneID: layout.columns + column, gap: gap, scale: scale)
                    #expect(screen.contains(full))
                    #expect(full.contains(top) && full.contains(bottom))
                    #expect(full.minX == top.minX && full.maxX == top.maxX)
                    #expect(full.width == bottom.width)
                    #expect(full.minY - minY == gap)
                    #expect(maxY - full.maxY == gap)
                    #expect(full.height == top.height + bottom.height + gap)
                    for boundary in [full.minX, full.minY, full.maxX, full.maxY] {
                        #expect(boundary * scale == (boundary * scale).rounded())
                    }
                    if column < layout.columns {
                        let next = try GridGeometry.frame(in: screen, layout: layout, target: .column(column + 1), gap: gap, scale: scale)
                        #expect(next.minX - full.maxX == gap)
                    }
                }
            }
        }
    }
}

@Test func placementTargetsRejectInvalidColumnsAndPropagateGeometryErrors() {
    let valid = CGRect(x: 0, y: 0, width: 1200, height: 800)
    for layout in LayoutPreset.allCases {
        for column in [Int.min, -1, 0, layout.columns + 1, Int.max] {
            #expect(throws: GridGeometryError.invalidColumn(column)) {
                try GridGeometry.frame(in: valid, layout: layout, target: .column(column), gap: 8, scale: 2)
            }
        }
        #expect(throws: GridGeometryError.invalidZoneID(0)) {
            try GridGeometry.frame(in: valid, layout: layout, target: .zone(0), gap: 8, scale: 2)
        }
        #expect(throws: GridGeometryError.invalidVisibleFrame) {
            try GridGeometry.frame(in: .zero, layout: layout, target: .column(1), gap: 8, scale: 2)
        }
        #expect(throws: GridGeometryError.invalidGap) {
            try GridGeometry.frame(in: valid, layout: layout, target: .column(1), gap: -1, scale: 2)
        }
        #expect(throws: GridGeometryError.invalidScale) {
            try GridGeometry.frame(in: valid, layout: layout, target: .column(1), gap: 8, scale: 0)
        }
    }
}
