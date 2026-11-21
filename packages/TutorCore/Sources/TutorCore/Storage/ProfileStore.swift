import Foundation
import Combine

/// Saves learner profiles on the device as JSON.
/// Use `exportURL()` with a share sheet to save a copy to Google Drive or Files.
@MainActor
public final class ProfileStore: ObservableObject {
    @Published public private(set) var profiles: [Profile] = []
    private let fileURL: URL

    public init(fileName: String = "profiles.json") {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        fileURL = docs.appendingPathComponent(fileName)
        load()
    }

    public func profile(_ id: UUID) -> Profile? { profiles.first { $0.id == id } }

    @discardableResult
    public func add(name: String) -> Profile {
        let p = Profile(name: name)
        profiles.append(p)
        save()
        return p
    }

    public func update(_ profile: Profile) {
        if let i = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[i] = profile
        } else {
            profiles.append(profile)
        }
        save()
    }

    public func delete(_ id: UUID) {
        profiles.removeAll { $0.id == id }
        save()
    }

    /// A dated copy of all progress for backup/sharing.
    public func exportURL() -> URL? {
        let stamp = ISO8601DateFormatter().string(from: Date()).prefix(10)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tutor-progress-\(stamp).json")
        do {
            try encoder.encode(profiles).write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    private var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        profiles = (try? d.decode([Profile].self, from: data)) ?? []
    }

    private func save() {
        try? encoder.encode(profiles).write(to: fileURL, options: .atomic)
    }
}
