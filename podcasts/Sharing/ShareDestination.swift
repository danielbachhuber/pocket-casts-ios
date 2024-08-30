import SwiftUI

enum ShareDestination: Hashable {
    case instagram
    case copyLink
    case systemSheet(vc: UIViewController)

    var name: String {
        switch self {
        case .instagram:
            L10n.shareInstagramStories
        case .copyLink:
            L10n.shareCopyLink
        case .systemSheet:
            L10n.shareMoreActions
        }
    }

    var icon: Image {
        switch self {
        case .instagram:
            Image("instagram")
        case .copyLink:
            Image("pocketcasts")
        case .systemSheet:
            Image(systemName: "ellipsis")
        }
    }

    enum ShareError: Error {
        case noMatchingItemIdentifier
        case loadFailed(Error?)
    }

    @MainActor
    func share(_ option: SharingModal.Option, style: ShareImageStyle, clipUUID: String, source: AnalyticsSource) async throws {
        switch self {
        case .instagram:
            let item = option.shareData(style: style, destination: self).mapFirst { shareItem -> (Data, UTType)? in
                if let data = shareItem as? Data {
                    return (data, style == .audio ? UTType.m4a : .mpeg4Movie)
                } else if let image = shareItem as? UIImage, let data = image.pngData() {
                    return (data, .png)
                } else {
                    return nil
                }
            }

            guard let item else {
                throw ShareError.noMatchingItemIdentifier
            }

            instagramShare(data: item.0, type: item.1, url: option.shareURL)
            ShareDestination.logClipShared(option: option, style: style, clipUUID: clipUUID, source: source)
            ShareDestination.logPodcastShared(style: style, option: option, destination: self, source: source)
        case .copyLink:
            UIPasteboard.general.string = option.shareURL
            Toast.show(L10n.shareCopiedToClipboard)
            ShareDestination.logClipShared(option: option, style: style, clipUUID: clipUUID, source: source)
            ShareDestination.logPodcastShared(style: style, option: option, destination: self, source: source)
        case .systemSheet(let vc):
            let data = option.shareData(style: style)
            let activityViewController = UIActivityViewController(activityItems: data, applicationActivities: nil)
            vc.presentedViewController?.present(activityViewController, animated: true, completion: {
                ShareDestination.logClipShared(option: option, style: style, clipUUID: clipUUID, source: source)
                ShareDestination.logPodcastShared(style: style, option: option, destination: self, source: source)
            })
        }
    }

    @MainActor
    static fileprivate func shareImage(_ option: SharingModal.Option, style: ShareImageStyle) -> UIImage {
        let imageView = ShareImageView(info: option.imageInfo, style: style, angle: .constant(0))
        return imageView.snapshot()
    }

    @MainActor
    private func instagramShare(data: Data, type: UTType, url: String) {
        let attributionURL = url
        let appID = ApiCredentials.instagramAppID

        guard let urlScheme = URL(string: "instagram-stories://share?source_application=\(appID)"),
            UIApplication.shared.canOpenURL(urlScheme) else {
            return
        }

        let backgroundTopColor = UIColor.black
        let backgroundBottomColor = UIColor.white

        let dataKey = type == .mpeg4Movie ? "com.instagram.sharedSticker.backgroundVideo" : "com.instagram.sharedSticker.backgroundImage"
        let pasteboardItems = [[dataKey: data,
                                "com.instagram.sharedSticker.backgroundTopColor": backgroundTopColor.hexString(),
                                "com.instagram.sharedSticker.backgroundBottomColor": backgroundBottomColor.hexString(),
                                "com.instagram.sharedSticker.contentURL": attributionURL]]
        let pasteboardOptions: [UIPasteboard.OptionsKey: Any] = [.expirationDate: Date().addingTimeInterval(5.minutes)]

        UIPasteboard.general.setItems(pasteboardItems, options: pasteboardOptions)

        UIApplication.shared.open(urlScheme)
    }

    var isIncluded: Bool {
        switch self {
        case .instagram:
            if let url = URL(string: "instagram-stories://share"), UIApplication.shared.canOpenURL(url) {
                true
            } else {
                false
            }
        default:
            true
        }
    }

    var analyticsDescription: String {
        switch self {
        case .instagram:
            "ig_story"
        case .copyLink:
            "url"
        case .systemSheet:
            "system_sheet"
        }
    }

    enum Constants {
        static let displayedAppsCount = 3
    }

    static func ==(lhs: ShareDestination, rhs: ShareDestination) -> Bool {
        lhs.name == rhs.name && lhs.icon == rhs.icon
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }

    static var displayedApps: Array<ShareDestination>.SubSequence {
        apps.prefix(Constants.displayedAppsCount)
    }

    private static var apps: [Self] {
        let thirdPartyApps: [Self] = [.instagram]
        return thirdPartyApps.compactMap({ destination -> Self? in
            guard destination.isIncluded else { return nil }
            return destination
        })
    }
}

// MARK: Analytics

extension ShareDestination {
    private static func logClipShared(option: SharingModal.Option, style: ShareImageStyle, clipUUID: String, source: AnalyticsSource) {
        // This event is specifically for clip shares and not other shares. These are handled by `podcastShared`
        guard case let .clipShare(episode, clipTime, _, _) = option else {
            return
        }

        var properties: Dictionary<String, Any> = [:]

        properties["episode_uuid"] = episode.uuid
        properties["podcast_uuid"] = episode.parentPodcast()?.uuid ?? "unknown"
        properties["start"] = Int(clipTime.start)
        properties["end"] = Int(clipTime.end)
        properties["start_modified"] = clipTime.startChanged
        properties["end_modified"] = clipTime.endChanged
        properties["clip_uuid"] = clipUUID
        properties["type"] = shareType(style: style, option: option)
        properties["card_type"] = cardType(style: style)

        Analytics.track(.shareScreenClipShared, source: source, properties: properties)
    }

    private static func cardType(style: ShareImageStyle) -> String {
        switch style {
        case .large:
            "vertical"
        case .medium:
            "square"
        case .small:
            "horizontal"
        case .audio:
            "audio"
        }
    }

    private static func shareType(style: ShareImageStyle, option: SharingModal.Option) -> String {
        switch (style, option) {
        case (.audio, _):
            "audio"
        case (_, .clip), (_, .clipShare):
            "video"
        default:
            "link"
        }
    }

    private static func type(style: ShareImageStyle, option: SharingModal.Option, destination: Self) -> String {
        switch (style, option) {
        case (_, .podcast):
            return "podcast"
        case (_, .episode):
            return "episode"
        case (_, .currentPosition):
            return "current_time"
        case (.audio, _):
            return "clip_audio"
        case (_, .clip), (_, .clipShare):
            if case .copyLink = destination {
                return "clip_link"
            } else {
                return "clip_video"
            }
        default:
            return "unknown"
        }
    }

    private static func logPodcastShared(style: ShareImageStyle, option: SharingModal.Option, destination: Self, source: AnalyticsSource) {
        let properties: [String: Any] = [
            "type": type(style: style, option: option, destination: destination),
            "action": destination.analyticsDescription,
            "card_type": cardType(style: style)
        ]

        Analytics.track(.podcastShared, source: source, properties: properties)
    }
}
