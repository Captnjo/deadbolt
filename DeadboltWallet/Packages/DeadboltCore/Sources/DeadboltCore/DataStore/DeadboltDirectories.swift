import Foundation

/// Cross-platform directory resolution for Deadbolt data files.
///
/// On macOS: uses `~/.deadbolt/` (consistent with CLI tooling).
/// On iOS: uses the app's Application Support directory.
public enum DeadboltDirectories {
    /// The base directory for Deadbolt data files (config, address book, etc.).
    public static var dataDirectory: String {
        #if os(macOS)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.deadbolt"
        #else
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupport = paths.first ?? FileManager.default.temporaryDirectory
        return appSupport.appendingPathComponent("Deadbolt").path
        #endif
    }
}
