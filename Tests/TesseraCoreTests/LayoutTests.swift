import Foundation
import CoreGraphics
import Testing
@testable import TesseraCore

@Test func layoutPresetsContainOnlySupportedGrids() {
    #expect(LayoutPreset.allCases == [.twoByTwo, .threeByTwo, .fourByTwo])
    #expect(LayoutPreset.twoByTwo.title == "2×2")
    #expect(LayoutPreset.twoByTwo.columns == 2)
    #expect(LayoutPreset.twoByTwo.id == "twoByTwo")
    #expect(LayoutPreset.threeByTwo.title == "3×2")
    #expect(LayoutPreset.fourByTwo.title == "4×2")
    #expect(LayoutPreset.threeByTwo.id == "threeByTwo")
    #expect(LayoutPreset.fourByTwo.columns == 4)
    #expect(LayoutPreset.allCases.allSatisfy { $0.rows == 2 })
}

@Test(arguments: LayoutPreset.allCases)
func zonesUseTopLeftRowMajorNormalizedCoordinates(_ layout: LayoutPreset) {
    let zones = layout.zones
    #expect(zones.map(\.id) == Array(1...(layout.columns * layout.rows)))
    for (index, zone) in zones.enumerated() {
        #expect(zone.normalizedRect.origin.x == CGFloat(index % layout.columns) / CGFloat(layout.columns))
        #expect(zone.normalizedRect.origin.y == CGFloat(index / layout.columns) / CGFloat(layout.rows))
        #expect(zone.normalizedRect.width == 1 / CGFloat(layout.columns))
        #expect(zone.normalizedRect.height == 1 / CGFloat(layout.rows))
        #expect(CGRect(x: 0, y: 0, width: 1, height: 1).contains(zone.normalizedRect))
    }
    #expect(zones.first?.normalizedRect.origin == .zero)
    #expect(zones.last?.normalizedRect.maxX == 1)
    #expect(zones.last?.normalizedRect.maxY == 1)
}

@Test func presetDecodingRejectsUnknownLayouts() throws {
    #expect(LayoutPreset(rawValue: "fiveByTwo") == nil)
    #expect(LayoutPreset(rawValue: "") == nil)
    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(LayoutPreset.self, from: Data("\"custom\"".utf8))
    }
    for layout in LayoutPreset.allCases {
        let data = try JSONEncoder().encode(layout)
        #expect(try JSONDecoder().decode(LayoutPreset.self, from: data) == layout)
    }
}
