import Foundation

@MainActor
protocol FeedProviding: ObservableObject {
    var videoItems: [VideoItem] { get }
    var isLoading: Bool { get }
    var errorMessage: String? { get }
}

extension RecommendationViewModel: FeedProviding {}
extension FollowFeedViewModel: FeedProviding {}
