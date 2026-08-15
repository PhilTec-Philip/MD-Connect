//
//  FiveNet_MobileApp.swift
//  FiveNet Mobile
//
//  Created by Philip Müller on 06.08.26.
//

import SwiftUI
import UIKit

@main
struct FiveNet_MobileApp: App {
    @State private var appState = AppState()

    init() {
        configureGlobalAppearance()
    }

    /// Global einheitliche, moderne Darstellung von Navigationsleiste und
    /// Tab-Bar: gerundete, halbtransparente Bars mit konsistentem Font-Stil.
    private func configureGlobalAppearance() {
        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithDefaultBackground()
        navAppearance.backgroundColor = UIColor.systemGroupedBackground
        navAppearance.titleTextAttributes = [
            .foregroundColor: UIColor.label,
            .font: UIFont.systemFont(ofSize: 17, weight: .semibold),
        ]
        navAppearance.largeTitleTextAttributes = [
            .foregroundColor: UIColor.label,
            .font: UIFont.systemFont(ofSize: 34, weight: .bold),
        ]
        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
        UINavigationBar.appearance().compactAppearance = navAppearance

        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithDefaultBackground()
        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .tint(Theme.Palette.accent)
        }
    }
}
