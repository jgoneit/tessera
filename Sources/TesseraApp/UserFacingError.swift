import Foundation
import TesseraCore

/// Core geometry stays independent of UI localization.
enum UserFacingError {
    static func message(_ error: Error) -> String {
        if let geometry = error as? GridGeometryError {
            if geometry == .insufficientSpace {
                return L10n.text("The selected grid cannot fit this display. Try a smaller gap.")
            }
            return L10n.text("The display or selected zone is invalid. Try arranging the window again.")
        }
        return error.localizedDescription
    }
}
