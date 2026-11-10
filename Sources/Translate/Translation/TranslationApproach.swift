import Foundation

/// Which of the system's translation models a job uses.
enum TranslationApproach: String, Sendable {
    /// The classic on-device models: the fastest, a little less fluent.
    case fast
    /// The Apple Intelligence models: more fluent, much slower on long text.
    case accurate
}
