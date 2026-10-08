import Foundation

// MARK: - Navigation requests from App Intents / Spotlight
//
// AppEntry.handleOpenURL turns `smarttube://search` and `smarttube://section/…` routes into
// these notifications; MainTabView (RootView.swift) switches tab and section.

extension Notification.Name {
    /// userInfo: "query" (String)
    public static let smartTubeOpenSearch = Notification.Name("com.smarttube.intent.openSearch")
    /// userInfo: "section" (BrowseSection.SectionType raw value)
    public static let smartTubeOpenSection = Notification.Name("com.smarttube.intent.openSection")
}
