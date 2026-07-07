import SwiftUI
import SwiftData

/// Shared horizontal area-filter chip row (All · <areas> · Personal), used by both the
/// mobile Board and Week screens so the two stay in sync. Binds the shared
/// `MobileFilters.area`; owns its own `Area` query.
struct MobileAreaChips: View {
    @Query private var areas: [Area]
    @Bindable var filters: MobileFilters

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", active: filters.area == .all) { filters.area = .all }
                ForEach(areas) { a in
                    chip(a.name, active: filters.area == .area(a.name)) { filters.area = .area(a.name) }
                }
                chip("Personal", active: filters.area == .personal) { filters.area = .personal }
            }
        }
    }

    private func chip(_ label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.caption.weight(.medium))
                .foregroundStyle(active ? .white : .secondary)
                .padding(.horizontal, 11).padding(.vertical, 5)
                .background(active ? AnyShapeStyle(Theme.Palette.textPrimary) : AnyShapeStyle(Theme.Palette.surface), in: Capsule())
        }.buttonStyle(.plain)
    }
}
