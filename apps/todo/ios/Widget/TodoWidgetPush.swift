import Foundation
import WidgetKit

// WidgetKit push のトークンを API に登録する。
// API はタスクが（Mac や shelf などで）書き換わるとこのトークンへ push を送り、ウィジェットを読み直させる
enum WidgetPushRegistration {
    private static let registeredTokenKey = "registeredWidgetPushToken"
    private static let registeredAtKey = "registeredWidgetPushTokenAt"

    static func hex(_ token: Data) -> String {
        token.map { String(format: "%02x", $0) }.joined()
    }

    // 1日以内に同じトークンを登録済みなら何もしない（API 側で消えていても1日で戻るように、毎日は送り直す）。
    // 失敗したら覚えないので、次の読み直しでやり直す
    static func register(_ token: String) async {
        let defaults = UserDefaults.standard
        if defaults.string(forKey: registeredTokenKey) == token,
           let at = defaults.object(forKey: registeredAtKey) as? Date,
           Date.now.timeIntervalSince(at) < 24 * 60 * 60 {
            return
        }
        do {
            try await WidgetAPIClient.shared.registerPushToken(token)
            defaults.set(token, forKey: registeredTokenKey)
            defaults.set(Date.now, forKey: registeredAtKey)
        } catch {
            // 登録できなくても表示は続ける（push が来ないだけで、定期の読み直しは残る）
        }
    }

    static func unregister(_ token: String) async {
        try? await WidgetAPIClient.shared.unregisterPushToken(token)
        UserDefaults.standard.removeObject(forKey: registeredTokenKey)
    }

    // pushTokenDidChange を取りこぼしても登録されるよう、読み直しのたびに今のトークンを確かめる
    static func registerCurrentToken() async {
        guard let info = await WidgetCenter.shared.currentPushInfo else { return }
        await register(hex(info.token))
    }
}

struct TodoWidgetPushHandler: WidgetPushHandler {
    func pushTokenDidChange(_ pushInfo: WidgetPushInfo, widgets: [WidgetInfo]) {
        let token = WidgetPushRegistration.hex(pushInfo.token)
        Task {
            // ホーム画面からウィジェットを外したら、送り先からも外す
            if widgets.isEmpty {
                await WidgetPushRegistration.unregister(token)
            } else {
                await WidgetPushRegistration.register(token)
            }
        }
    }
}
