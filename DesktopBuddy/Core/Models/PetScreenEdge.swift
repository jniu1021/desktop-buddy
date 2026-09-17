enum PetScreenEdge: String, CaseIterable {
    case top
    case right
    case bottom
    case left

    var displayName: String {
        rawValue.capitalized
    }
}
