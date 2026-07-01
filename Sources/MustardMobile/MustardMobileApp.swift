import SwiftUI
import SwiftData

/// iOS companion entry point (BAK-108 foundation). This is a stub shell — the bottom-tab
/// navigation and the four mobile screens land in BAK-110+. Its job here is to prove the
/// platform-agnostic MustardKit core (Models + Logic) compiles, links, and runs on iOS.
@main
struct MustardMobileApp: App {
    var body: some Scene {
        WindowGroup {
            MobileRootView()
        }
    }
}

struct MobileRootView: View {
    // Reference the core so the shared model/logic is compiled into the iOS target —
    // this is the linkage the foundation exists to prove.
    private let stageCount = TaskStage.allCases.count
    private let trustLevels = TrustLevel.allCases.count

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 44))
                .foregroundStyle(Color(hex: "#7F77DD"))
            Text("Mustard")
                .font(.largeTitle.bold())
            Text("iOS companion")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Core linked — \(stageCount)-stage pipeline, \(trustLevels) trust levels.\nScreens land next (BAK-110+).")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

#Preview {
    MobileRootView()
}
