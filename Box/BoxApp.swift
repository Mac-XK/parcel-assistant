//
//  BoxApp.swift
//  Box
//
//  Created by MacXK on 2026/11/20.
//

import SwiftUI

@main
struct BoxApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    Notifier.shared.configure()
                    #if DEBUG
                    SelfTest.runIfRequested()
                    #endif
                }
        }
    }
}
