//
//  View.swift
//  Saga
//
//  Created by Dylan Gattey on 8/20/25.
//

import SwiftUI

extension View {
    
    /// Our default shadow across the whole app
    func defaultShadow() -> some View {
        self.shadow(color: .black.opacity(0.1), radius: 8)
    }
}
