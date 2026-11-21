import Foundation

public enum ContentLoader {
    public enum LoadError: Error, LocalizedError {
        case missing(String)
        public var errorDescription: String? {
            switch self { case .missing(let name): return "Couldn't find \(name).json in the app bundle." }
        }
    }

    /// Loads `<name>.json` from the app bundle.
    public static func load(_ name: String, bundle: Bundle = .main) throws -> Curriculum {
        guard let url = bundle.url(forResource: name, withExtension: "json") else { throw LoadError.missing(name) }
        return try decode(Data(contentsOf: url))
    }

    public static func decode(_ data: Data) throws -> Curriculum {
        try JSONDecoder().decode(Curriculum.self, from: data)
    }
}
