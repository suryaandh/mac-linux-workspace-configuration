//
//  DynamicNotchApp.swift
//  DynamicNotch
//
//  Created by Gde Swiyasa on 09/09/26.
//

import SwiftUI
import AppKit

@main
struct DynamicNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No visible main window — notch overlay is managed by AppDelegate
        Settings { EmptyView() }
    }
}
