import Foundation

struct ForegroundActivitySnapshot: Equatable {
    let bundleIdentifier: String?
    let secondsSinceLastInput: TimeInterval?
}
