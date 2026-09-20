import SwiftUI

struct AppColors {
    let panelBackground: Color
    let listBackground: Color
    let textPrimary: Color
    let textSecondary: Color
    let checkboxFill: Color
    let checkboxBackground: Color
    let checkboxBorder: Color
    let checkmarkColor: Color
    let shadowColor: Color
    let closeButtonBackground: Color
}

enum Theme {
    static let light = AppColors(
        panelBackground: Color(red: 0.96, green: 0.95, blue: 0.91),
        listBackground: Color(red: 1.0, green: 0.97, blue: 0.88),
        textPrimary: Color(.darkGray),
        textSecondary: Color(.systemGray),
        checkboxFill: Color(red: 0.93, green: 0.78, blue: 0.30),
        checkboxBackground: .white,
        checkboxBorder: Color.gray.opacity(0.25),
        checkmarkColor: Color(white: 0.3),
        shadowColor: .black.opacity(0.12),
        closeButtonBackground: Color(.systemGray).opacity(0.15)
    )

    static let night = AppColors(
        panelBackground: Color(red: 0.11, green: 0.11, blue: 0.12),
        listBackground: Color(red: 0.15, green: 0.15, blue: 0.16),
        textPrimary: Color(red: 0.88, green: 0.86, blue: 0.82),
        textSecondary: Color(red: 0.50, green: 0.48, blue: 0.45),
        checkboxFill: Color(red: 0.85, green: 0.72, blue: 0.28),
        checkboxBackground: Color(red: 0.22, green: 0.22, blue: 0.23),
        checkboxBorder: Color.gray.opacity(0.3),
        checkmarkColor: Color(red: 0.35, green: 0.33, blue: 0.30),
        shadowColor: .black.opacity(0.3),
        closeButtonBackground: Color.white.opacity(0.08)
    )

    // ThemeClock（@Observable）経由で読むことで、読んだ View が切り替わりに個別に依存する。
    // 時刻を直接見ると SwiftUI は変化を検知できず、たまたま再評価された部分だけ色が変わる
    @MainActor
    static var current: AppColors {
        ThemeClock.shared.isNight ? night : light
    }

    #if DEBUG
    // 検証用: TODOMAC_DEBUG_NIGHT_AFTER=<秒> で、最初の N 秒間は昼・以降は夜として扱う。
    // 基準はプロセス起動でなく isNightTime の初回参照（static let の遅延初期化。実際は起動直後の初回描画）
    // （昼→夜の切り替わり直後の描画を、22 時を待たずに再現するため。手順は VERIFY.md）
    private static let launchedAt = Date()
    private static let debugNightAfter = ProcessInfo.processInfo
        .environment["TODOMAC_DEBUG_NIGHT_AFTER"].flatMap(TimeInterval.init)
    #endif

    static var isNightTime: Bool {
        #if DEBUG
        if let debugNightAfter {
            return Date().timeIntervalSince(launchedAt) >= debugNightAfter
        }
        #endif
        let jst = TimeZone(identifier: "Asia/Tokyo")!
        let hour = Calendar.current.dateComponents(in: jst, from: Date()).hour ?? 0
        return hour >= 22 || hour < 6
    }
}

/// 昼/夜の切り替わりを SwiftUI に伝えるための状態。
@MainActor
@Observable
final class ThemeClock {
    static let shared = ThemeClock()

    private(set) var isNight = Theme.isNightTime

    private init() {
        let timer = Timer(timeInterval: 30, repeats: true) { _ in
            MainActor.assumeIsolated { ThemeClock.shared.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    /// 値が変わったときだけ書く（毎回書くと 30 秒ごとに全 View が無駄に再評価される）
    func refresh() {
        let now = Theme.isNightTime
        if now != isNight { isNight = now }
    }
}
