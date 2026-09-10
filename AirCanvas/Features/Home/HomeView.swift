import SwiftUI

struct HomeView: View {
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "scribble.variable")
                        .font(.system(size: 40))
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)

                    Text("AirCanvas")
                        .font(.largeTitle.bold())

                    Text("Create drawings in the space around you.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 12)
                .accessibilityElement(children: .combine)
            }

            Section("Create") {
                NavigationLink(value: AppRoute.canvas(.new)) {
                    Label("New Canvas", systemImage: "plus.rectangle.on.rectangle")
                }
                .accessibilityHint("Opens a new spatial canvas")
                .accessibilityIdentifier("home.newCanvas")
            }

            Section("Library") {
                NavigationLink(value: AppRoute.myCanvases) {
                    Label("My Canvases", systemImage: "square.stack.3d.up")
                }
                .accessibilityHint("Shows your saved canvases")
                .accessibilityIdentifier("home.myCanvases")
            }

            Section {
                NavigationLink(value: AppRoute.settings) {
                    Label("Settings", systemImage: "gearshape")
                }
                .accessibilityHint("Opens AirCanvas settings")
            }
        }
        .navigationTitle("AirCanvas")
    }
}

#Preview {
    NavigationStack {
        HomeView()
    }
}
