import SwiftUI
import TutorCore

@main
struct MathLadderApp: App {
    @StateObject private var store = ProfileStore(fileName: "math-ladder-profiles.json")

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var store: ProfileStore
    @State private var selected: UUID?
    @State private var loaded: Result<Curriculum, Error> = Result { try ContentLoader.load("curriculum") }

    var body: some View {
        NavigationStack {
            switch loaded {
            case .failure(let error):
                ContentUnavailableView("Math map didn't load", systemImage: "exclamationmark.triangle",
                                       description: Text(error.localizedDescription))
            case .success(let curriculum):
                if let id = selected, store.profile(id) != nil {
                    LadderHomeView(curriculum: curriculum, profileId: id) { selected = nil }
                } else {
                    ProfilePickerView(store: store) { selected = $0.id }
                        .navigationTitle("Math Ladder")
                }
            }
        }
    }
}
