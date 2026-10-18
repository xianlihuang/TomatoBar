import UserNotifications

enum TBNotification {
    enum Category: String {
        case restStarted, restFinished
    }

    enum Action: String {
        case skipRest
    }
}

typealias TBNotificationHandler = (TBNotification.Action) -> Void

final class TBNotificationCenter: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    private var handler: TBNotificationHandler?

    override init() {
        super.init()

        center.delegate = self
        registerCategories()
        requestAuthorizationIfNeeded()
    }

    func setActionHandler(handler: @escaping TBNotificationHandler) {
        self.handler = handler
    }

    func send(title: String, body: String, category: TBNotification.Category) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = category.rawValue
        content.sound = nil

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        center.add(request) { error in
            if let error {
                print("Error adding notification: \(error)")
            }
        }
    }

    // MARK: - Setup

    private func registerCategories() {
        let skipRest = UNNotificationAction(
            identifier: TBNotification.Action.skipRest.rawValue,
            title: NSLocalizedString("TBTimer.onRestStart.skip.title", comment: "Skip"),
            options: []
        )

        let restStarted = UNNotificationCategory(
            identifier: TBNotification.Category.restStarted.rawValue,
            actions: [skipRest],
            intentIdentifiers: [],
            options: []
        )
        let restFinished = UNNotificationCategory(
            identifier: TBNotification.Category.restFinished.rawValue,
            actions: [],
            intentIdentifiers: [],
            options: []
        )

        center.setNotificationCategories([restStarted, restFinished])
    }

    private func requestAuthorizationIfNeeded() {
        center.getNotificationSettings { [center] settings in
            guard settings.authorizationStatus == .notDetermined else {
                return
            }
            center.requestAuthorization(options: [.alert]) { _, error in
                if let error {
                    print("Error requesting notification authorization: \(error)")
                }
            }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(_: UNUserNotificationCenter,
                                willPresent _: UNNotification,
                                withCompletionHandler completionHandler:
                                @escaping (UNNotificationPresentationOptions) -> Void)
    {
        // Show banners even while the popover is open. The app has no Dock
        // icon, so notifications are the primary way to surface a finished
        // interval when the menu bar title is hidden.
        completionHandler([.banner, .list])
    }

    func userNotificationCenter(_: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void)
    {
        if let action = TBNotification.Action(rawValue: response.actionIdentifier) {
            DispatchQueue.main.async { [weak self] in
                self?.handler?(action)
            }
        }
        completionHandler()
    }
}
