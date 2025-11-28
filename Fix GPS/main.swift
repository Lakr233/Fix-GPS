//
//  main.swift
//  Fix GPS
//
//  Created by QAQ on 2023/11/1.
//

import SwiftUI
import WindowAnimation

struct FixerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commandsReplaced {
            CommandGroup(replacing: .newItem) {}
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
    }
}

FixerApp.main()
