import Foundation
import CoreGraphics

/// The only layouts supported by v0.1. Raw-value decoding rejects unknown layouts.
public enum LayoutPreset: String, CaseIterable, Codable, Sendable, Identifiable {
    case twoByTwo
    case threeByTwo
    case fourByTwo

    public var id: String { rawValue }
    public var title: String { "\(columns)×\(rows)" }
    public var columns: Int {
        switch self {
        case .twoByTwo: 2
        case .threeByTwo: 3
        case .fourByTwo: 4
        }
    }
    public var rows: Int { 2 }

    /// Normalized coordinates use a top-left origin, like the selection UI.
    public var zones: [Zone] {
        (0..<(columns * rows)).map { index in
            Zone(
                id: index + 1,
                normalizedRect: CGRect(
                    x: CGFloat(index % columns) / CGFloat(columns),
                    y: CGFloat(index / columns) / CGFloat(rows),
                    width: 1 / CGFloat(columns),
                    height: 1 / CGFloat(rows)
                )
            )
        }
    }
}

public struct Zone: Identifiable, Equatable, Sendable {
    public let id: Int
    public let normalizedRect: CGRect

    public init(id: Int, normalizedRect: CGRect) {
        self.id = id
        self.normalizedRect = normalizedRect
    }
}
