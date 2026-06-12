import Foundation

/// Art des haptischen Feedbacks. Vom ViewModel ausgelöst, von der View
/// in echtes Haptik-Feedback umgesetzt – so bleibt das ViewModel testbar.
enum HapticFeedback: Sendable, Equatable {
    case success
    case warning
    case error
}
