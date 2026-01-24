//
//  HomeSection.swift
//  Saga
//
//  Created by Dylan Gattey on 1/24/26.
//

import SwiftUI

struct HomeSection: Identifiable {
    let id = UUID()
    let title: String
    let content: AnyView
}
