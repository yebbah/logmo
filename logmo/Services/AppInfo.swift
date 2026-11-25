import Foundation

/// Version and contact details shown in Settings → About.
enum AppInfo {
    static let developerEmail = "connectwithsvetlanamae@gmail.com"

    static var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?" }
    static var build: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?" }
    /// For example "1.0.0 (1)".
    static var versionString: String { "\(version) (\(build))" }

    /// A prepared email to the developer. It carries only the app and iOS versions, nothing from the user's logs.
    static func contactURL(versionString: String = AppInfo.versionString, osVersion: String) -> URL {
        var c = URLComponents()
        c.scheme = "mailto"
        c.path = developerEmail
        c.queryItems = [
            URLQueryItem(name: "subject", value: "logmo \(versionString) feedback"),
            URLQueryItem(name: "body", value: "\n\n--\nlogmo \(versionString), iOS \(osVersion)"),
        ]
        return c.url!
    }
}
