import AppKit
import AppConfiguration

// Run the real SettingsStore inside a bundle, where Bundle.main has the same
// identifier as the settings domain. An ordinary SwiftPM test misses this case.
@main
struct SettingsStartupCheck {
    @MainActor
    static func main() {
        let arguments = CommandLine.arguments
        let bundleID = arguments[1]
        let fixture = try! Data(contentsOf: URL(fileURLWithPath: arguments[2]))
        let values = try! PropertyListSerialization.propertyList(from: fixture, format: nil) as! [String: Any]
        let expectedEnabled = arguments[3] == "true"
        let expectedDuration = Double(arguments[4])!
        let expectedDisplay = arguments[5]
        let isolatedHome = URL(fileURLWithPath: arguments[6]).resolvingSymlinksInPath()
        precondition(FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath() == isolatedHome)
        precondition(Bundle.main.bundleIdentifier == bundleID)
        precondition(AppIdentity.current.bundleIdentifier == bundleID)

        // The argument domain is process-local. Never write persistent settings:
        // cfprefsd may access the user's real preferences even with a fixed home.
        UserDefaults.standard.setVolatileDomain(values, forName: UserDefaults.argumentDomain)
        let settings = SettingsStore()
        precondition(settings.enabled == expectedEnabled, "Saved enabled setting was lost")
        precondition(settings.duration == expectedDuration, "Saved duration setting was lost")
        precondition(settings.displayID == expectedDisplay, "Saved display setting was lost")

        print("Settings startup passed: \(bundleID)")
    }
}
