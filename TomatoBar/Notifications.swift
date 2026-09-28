import UserNotifications

enum TBNotification {
    enum Category: String {
        case breakStarted, breakFinished
    }

    enum Action: String {
        case skipBreak
    }
}

typealias TBNotificationHandler = (TBNotification.Action) -> Void

class TBNotificationCenter: NSObject, UNUserNotificationCenterDelegate {
    private var center = UNUserNotificationCenter.current()
    private var handler: TBNotificationHandler?

    override init() {
        super.init()

        center.requestAuthorization(
            options: [.alert]
        ) { _, error in
            if error != nil {
                print("Error requesting notification authorization: \(error!)")
            }
        }

        center.delegate = self

        let actionSkipBreak = UNNotificationAction(
            identifier: TBNotification.Action.skipBreak.rawValue,
            title: NSLocalizedString("TBTimer.skipBreak.label", comment: "Skip break"),
            options: []
        )
        let breakStartedCategory = UNNotificationCategory(
            identifier: TBNotification.Category.breakStarted.rawValue,
            actions: [actionSkipBreak],
            intentIdentifiers: []
        )
        let breakFinishedCategory = UNNotificationCategory(
            identifier: TBNotification.Category.breakFinished.rawValue,
            actions: [],
            intentIdentifiers: []
        )

        center.setNotificationCategories([
            breakStartedCategory,
            breakFinishedCategory,
        ])
    }

    func setActionHandler(handler: @escaping TBNotificationHandler) {
        self.handler = handler
    }

    func userNotificationCenter(_: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void)
    {
        guard let action = TBNotification.Action(rawValue: response.actionIdentifier),
              let handler = handler else {
            completionHandler()
            return
        }
        DispatchQueue.main.async {
            handler(action)
            completionHandler()
        }
    }

    func send(title: String, body: String, category: TBNotification.Category) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = category.rawValue
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        center.add(request) { error in
            if error != nil {
                print("Error adding notification: \(error!)")
            }
        }
    }
}
