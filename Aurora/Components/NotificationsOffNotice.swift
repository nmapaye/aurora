import SwiftUI
import UIKit

/// Where notification permission is off: the fact with its warning symbol,
/// then the way to change it in iOS Settings. Used wherever a reminder
/// depends on that permission.
struct NotificationsOffNotice: View {
    /// What still works without notifications, when that's worth saying.
    var detail: String?
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.xxs) {
            Label {
                Text(["Notifications are off for Aurora in iOS Settings.", detail].compactMap { $0 }.joined(separator: " "))
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: StatusTone.warning.symbol).accessibilityHidden(true)
            }
            .font(.footnote)
            .foregroundStyle(StatusTone.warning.foreground)
            Button {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
            } label: {
                Text("Open Settings")
                    .font(.subheadline.weight(.medium))
                    .frame(minHeight: Metrics.minimumTouchTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.auroraPress)
            .foregroundStyle(Palette.tint)
            .accessibilityHint("Opens Aurora’s notification settings.")
            .accessibilityIdentifier("notifications-open-settings")
        }
    }
}
