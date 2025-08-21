//
//  StarRatingView.swift
//  Saga
//
//  Created by Dylan Gattey on 8/20/25.
//

import SwiftUI

private struct Defaults {
    static let maxRating: Int = 5
    static let size: CGFloat = 24
    static let fillColor: Color = .yellow
    static let emptyColor: Color = .secondary
}

/// Allows editing or viewing a star rating with configurable settings but smart defaults. Two
/// versions, one with a binding and one without, for the display and edit views.
struct StarRatingView: View {
    @Binding var rating: Int
    let maxRating: Int
    let size: CGFloat
    let fillColor: Color
    let emptyColor: Color
    let isInteractive: Bool
    
    // Interactive version
    init(rating: Binding<Int>,
         maxRating: Int = Defaults.maxRating,
         size: CGFloat = Defaults.size,
         fillColor: Color = Defaults.fillColor,
         emptyColor: Color = Defaults.emptyColor) {
        self._rating = rating
        self.maxRating = maxRating
        self.size = size
        self.fillColor = fillColor
        self.emptyColor = emptyColor
        self.isInteractive = true
    }
    
    // Display-only version
    init(rating: Int,
         maxRating: Int = Defaults.maxRating,
         size: CGFloat = Defaults.size,
         fillColor: Color = Defaults.fillColor,
         emptyColor: Color = Defaults.emptyColor) {
        self._rating = .constant(rating)
        self.maxRating = maxRating
        self.size = size
        self.fillColor = fillColor
        self.emptyColor = emptyColor
        self.isInteractive = false
    }
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...maxRating, id: \.self) { star in
                let starView = Image(systemName: star <= rating ? "star.fill" : "star")
                    .foregroundColor(star <= rating ? fillColor : emptyColor)
                    .font(.system(size: size))
                
                if isInteractive {
                    Button(action: {
                        rating = star
                    }) {
                        starView
                    }
                    .buttonStyle(PlainButtonStyle())
                } else {
                    starView
                }
            }
        }
    }
}
