import Foundation

@MainActor
extension UpdateService {
    func menuTitle(language: AppLanguage? = nil) -> String {
        if case .available = state {
            return L10n.text("Update Available…", language: language)
        }
        return L10n.text("Check for Updates…", language: language)
    }

    func statusText(language: AppLanguage? = nil) -> String {
        switch state {
        case .idle: return L10n.text("Check for a newer version of Tessera.", language: language)
        case .checking: return L10n.text("Checking for updates…", language: language)
        case .available(let version):
            return L10n.format("Version %@ is available.", version, language: language)
        case .upToDate: return L10n.text("You're up to date.", language: language)
        case .failed: return L10n.text("Could not check for updates. Try again later.", language: language)
        }
    }
}
