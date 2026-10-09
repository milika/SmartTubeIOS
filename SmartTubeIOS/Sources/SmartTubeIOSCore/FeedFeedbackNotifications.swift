import Foundation

// MARK: - Feed feedback notification names
//
// Posted by VideoCardView when the user selects a feed feedback action
// (Not Interested, Don't Like, Don't Recommend Channel).
// Defined here in SmartTubeIOSCore so ViewModels can observe without
// importing the SmartTubeIOS UI module.

public extension Notification.Name {
    /// Posted when a specific video should be removed from the current feed.
    /// userInfo key: "videoId" (String)
    static let hideVideoFromFeed = Notification.Name("com.smarttube.hideVideoFromFeed")
    /// Posted when all videos from a channel should be removed from the current feed.
    /// userInfo key: "channelId" (String)
    static let hideChannelFromFeed = Notification.Name("com.smarttube.hideChannelFromFeed")
    /// Posted by WatchLaterMembershipStore when this app adds or removes a Watch Later video,
    /// so an open Watch Later list updates without a refresh (#157).
    /// userInfo keys: "videoId" (String), "added" (Bool)
    static let watchLaterDidChange = Notification.Name("com.smarttube.watchLaterDidChange")
}
