import SwiftUI

@main
struct TTLockNativeApp: App {
    @StateObject private var store = LockStore()
    @StateObject private var bleManager = TTLockBLEManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(bleManager)
        }
    }
}
