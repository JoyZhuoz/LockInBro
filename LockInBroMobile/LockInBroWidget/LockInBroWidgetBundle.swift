//
//  LockInBroWidgetBundle.swift
//  LockInBroWidget
//
//  Created by Aditya Pulipaka on 3/28/26.
//

import WidgetKit
import SwiftUI

@main
struct LockInBroWidgetBundle: WidgetBundle {
    var body: some Widget {
        LockInBroWidget()
        LockInBroWidgetControl()
        LockInBroWidgetLiveActivity()
    }
}
