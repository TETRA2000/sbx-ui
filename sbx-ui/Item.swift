//
//  Item.swift
//  sbx-ui
//
//  Created by Takahiko Inayama on 2026/4/4.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
