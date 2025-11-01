import SwiftUI

@main
struct RunCApp: App {
    init() {
        Log.info("App launching", category: .general)
        if let firstLog = Log.logFileURLs().first {
            Log.info("Active log file: \(firstLog.lastPathComponent)", category: .general)
        }
    }
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
