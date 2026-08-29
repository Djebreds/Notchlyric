public enum Position: String, CaseIterable, Sendable, Codable {
    case notch, earLeft, earRight, bottomRight

    public var displayName: String {
        switch self {
        case .notch: "Below the Notch"
        case .earLeft: "Menu Bar (Left)"
        case .earRight: "Menu Bar (Right)"
        case .bottomRight: "Bottom Right"
        }
    }
}
