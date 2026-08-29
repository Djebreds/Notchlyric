/// Which writing system a document uses, so the view can pick a renderer
/// without inspecting the text.
public enum Script: String, Sendable, Codable {
    case latin
    case arabic
}
