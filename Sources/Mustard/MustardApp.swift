import SwiftUI
import SwiftData
import MustardKit

@main
struct MustardApp: App {
    private let container = MustardContainer.make()

    var body: some Scene {
        WindowGroup {
            TodayView()
                .frame(minWidth: 520, minHeight: 480)
        }
        .modelContainer(container)
    }
}
