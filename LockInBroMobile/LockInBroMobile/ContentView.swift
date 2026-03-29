//
//  ContentView.swift
//  LockInBroMobile
//
//  Created by Aditya Pulipaka on 3/28/26.
//

import SwiftUI

/// Root view that gates between auth and the main app based on login state.
struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if appState.isAuthenticated {
            MainTabView()
        } else {
            AuthView()
        }
    }
}

#Preview {
    ContentView()
        .environment(AppState())
}
