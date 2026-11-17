import Foundation

/// `~/Library/Application Support/Murmur`, holding the dictionary and the dictation history.
enum AppSupport {
    static let directory: URL = {
        let fileManager = FileManager.default
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent("Murmur", isDirectory: true)

        // The app used to be called Murmur YouTube. Move its folder across once, rather than
        // starting the user over with an empty dictionary and history.
        let legacy = base.appendingPathComponent("MurmurYouTube", isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path), fileManager.fileExists(atPath: legacy.path) {
            do {
                try fileManager.moveItem(at: legacy, to: directory)
                Log.app.info("moved data from Application Support/MurmurYouTube to Murmur")
            } catch {
                // Keep using the old folder. Creating an empty new one here would make every
                // later launch skip the move and hide the user's dictionary for good.
                Log.app.error("couldn't move legacy data folder: \(error.localizedDescription, privacy: .public)")
                return legacy
            }
        }

        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }()
}
