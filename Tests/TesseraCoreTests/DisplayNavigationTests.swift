import CoreGraphics
import Testing
import TesseraCore

@Suite("Directional display neighbors")
struct DisplayNavigationTests {
    private func display(_ id: UInt32, _ x: CGFloat, _ y: CGFloat,
                         _ width: CGFloat = 1200, _ height: CGFloat = 800) -> DisplayGeometry {
        let frame = CGRect(x: x, y: y, width: width, height: height)
        return DisplayGeometry(id: id, frame: frame, visibleFrame: frame, scale: 1)
    }

    @Test func followsPhysicalDirectionRegardlessOfEnumeration() {
        let center = display(10, 0, 0)
        let neighbors: [(GridDirection, DisplayGeometry)] = [
            (.left, display(30, -1600, -100, 1600, 1000)),
            (.right, display(20, 1200, 50)),
            (.up, display(40, -200, 800, 1600, 900)),
            (.down, display(50, 0, -900, 1400, 900)),
        ]
        let screens = neighbors.map(\.1) + [center]
        for (direction, expected) in neighbors {
            #expect(DisplaySelection.neighbor(of: center, toward: direction, in: screens) == expected)
            #expect(DisplaySelection.neighbor(of: center, toward: direction, in: screens.reversed()) == expected)
        }
    }

    @Test func prefersAlignedThenNearestAndUsesStableTies() {
        let source = display(1, 0, 0)
        let diagonal = display(2, 1200, 1800)
        let far = display(3, 3000, 0)
        let near = display(4, 1300, 0)
        let tied = display(5, 1300, 0)
        #expect(DisplaySelection.neighbor(of: source, toward: .right, in: [diagonal, far]) == far)
        #expect(DisplaySelection.neighbor(of: source, toward: .right, in: [far, tied, near, diagonal]) == near)
        #expect(DisplaySelection.neighbor(of: source, toward: .right, in: [diagonal]) == diagonal)
        let offset = display(6, 1300, 100)
        #expect(DisplaySelection.neighbor(of: source, toward: .right, in: [offset, near]) == near)
    }

    @Test func missingMirroredAndInvalidScreensAreNotNeighbors() {
        let source = display(1, 0, 0)
        let mirrored = display(2, 0, 0)
        let invalidFrame = display(3, 1200, 0, 0)
        let invalidScale = DisplayGeometry(id: 4, frame: CGRect(x: 1200, y: 0, width: 1200, height: 800),
            visibleFrame: CGRect(x: 1200, y: 0, width: 1200, height: 800), scale: .nan)
        for direction in GridDirection.allCases {
            #expect(DisplaySelection.neighbor(of: source, toward: direction,
                in: [source, mirrored, invalidFrame, invalidScale]) == nil)
        }
        #expect(DisplaySelection.neighbor(of: display(7, 0, 0, 0), toward: .right, in: [source]) == nil)
    }

    @Test func horizontalWrapUsesTheOppositeOuterEdge() {
        let left = display(1, -1600, -100, 1600, 1000)
        let center = display(2, 0, 0)
        let right = display(3, 1200, 50, 1920, 1080)
        for screens in [[left, center, right], [right, center, left], [center, left, right]] {
            #expect(DisplaySelection.navigationDestination(of: left, toward: .left, in: screens) == right)
            #expect(DisplaySelection.navigationDestination(of: right, toward: .right, in: screens) == left)
            #expect(DisplaySelection.navigationDestination(of: left, toward: .right, in: screens) == center)
            #expect(DisplaySelection.navigationDestination(of: right, toward: .left, in: screens) == center)
        }
        let diagonal = display(4, 4000, 2000)
        #expect(DisplaySelection.navigationDestination(of: left, toward: .left,
            in: [left, right, diagonal]) == diagonal)
        let tied = display(5, 1200, 50, 1920, 1080)
        #expect(DisplaySelection.navigationDestination(of: left, toward: .left,
            in: [tied, left, right]) == right)
    }

    @Test func wrapDoesNotInventHorizontalOrVerticalNeighbors() {
        let source = display(1, 0, 0)
        let mirrored = display(2, 0, 0)
        let above = display(3, 0, 800)
        let invalid = DisplayGeometry(id: 4, frame: CGRect(x: 1200, y: 0, width: 1200, height: 800),
            visibleFrame: CGRect(x: 1200, y: 0, width: 1200, height: 800), scale: .nan)
        for direction in [GridDirection.left, .right] {
            #expect(DisplaySelection.navigationDestination(of: source, toward: direction,
                in: [source, mirrored, above, invalid]) == nil)
        }
        #expect(DisplaySelection.navigationDestination(of: source, toward: .up, in: [source, above]) == above)
        #expect(DisplaySelection.navigationDestination(of: above, toward: .up, in: [source, above]) == nil)
        #expect(DisplaySelection.navigationDestination(of: source, toward: .down, in: [source, above]) == nil)
        #expect(DisplaySelection.navigationDestination(of: display(7, 0, 0, 0), toward: .left, in: [above]) == nil)
    }

    @Test func firstStepUsesOriginalCenterBeforeCrossing() {
        let bounds = CGRect(x: 0, y: 0, width: 1200, height: 800)
        for (center, leftEdge, rightEdge) in [(CGFloat(20), true, false), (CGFloat(1180), false, true), (CGFloat(600), false, false)] {
            let navigation = GridNavigation(layouts: LayoutPreset.allCases,
                windowFrame: CGRect(x: center - 10, y: 30, width: 20, height: 40), visibleFrame: bounds)
            #expect(navigation.isAtEdge(toward: .left) == leftEdge)
            #expect(navigation.isAtEdge(toward: .right) == rightEdge)
        }
        var maximized = GridNavigation(layout: .threeByTwo, windowFrame: bounds, visibleFrame: bounds)
        #expect(!maximized.isAtEdge(toward: .left))
        #expect(!maximized.isAtEdge(toward: .right))
        maximized.move(.up)
        #expect(maximized.isAtEdge(toward: .up))
    }
}
