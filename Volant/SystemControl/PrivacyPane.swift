import Foundation

/// The Privacy & Security panes a launcher command may need the owner to visit after macOS
/// refused it: Camera for Open Camera, Automation for the System Events toggles.
enum PrivacyPane: String, Hashable {
    case camera, automation

    /// The anchor System Settings opens to, under its Privacy & Security pane.
    private static let paneURL = "x-apple.systempreferences:com.apple.preference.security?"

    var url: URL {
        URL(string: Self.paneURL + (self == .camera ? "Privacy_Camera" : "Privacy_Automation"))!
    }

    var title: String {
        switch self {
        case .camera: return String(localized: "Open Camera Privacy Settings", comment: "Launcher row title: opens Privacy & Security › Camera")
        case .automation: return String(localized: "Open Automation Privacy Settings", comment: "Launcher row title: opens Privacy & Security › Automation")
        }
    }

    var detail: String {
        switch self {
        case .camera: return String(localized: "Privacy & Security › Camera", comment: "Launcher row subtitle for the Camera privacy settings row: where to turn on Volant")
        case .automation: return String(localized: "Privacy & Security › Automation", comment: "Launcher row subtitle for the Automation privacy settings row: where to turn on System Events for Volant")
        }
    }

    var sectionTitle: String {
        switch self {
        case .camera: return String(localized: "Camera", comment: "Launcher section title when camera access needs attention")
        case .automation: return String(localized: "Automation", comment: "Launcher section title when Automation access needs attention")
        }
    }

    var symbol: String { self == .camera ? "camera" : "gearshape.2" }
}
