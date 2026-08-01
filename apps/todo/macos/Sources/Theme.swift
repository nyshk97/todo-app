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

    static var current: AppColors {
        isNightTime ? night : light
    }

    private static var isNightTime: Bool {
        let jst = TimeZone(identifier: "Asia/Tokyo")!
        let hour = Calendar.current.dateComponents(in: jst, from: Date()).hour ?? 0
        return hour >= 22 || hour < 6
    }
}
