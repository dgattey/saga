//
//  BookReadingStatusView.swift
//  Saga
//
//  Created by Dylan Gattey on 8/23/25.
//


import SwiftUI

struct BookReadingStatusView: View {
    let book: Book
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Status Header
            HStack {
                statusIcon
                statusText
                Spacer()
            }
            
            // Date Information
            dateInfoSection
            
            // Statistics
            if book.readingStatus != .notStarted {
                statisticsSection
            }
        }
        .padding(16)
        .background(.bar)
        .cornerRadius(8)
        .defaultShadow()
    }
    
    // MARK: - Status Components
    
    private var statusIcon: some View {
        Group {
            switch book.readingStatus {
            case .reading:
                Image(systemName: "book.circle.fill")
            case .read:
                Image(systemName: "checkmark.circle.fill")
            case .notStarted:
                Image(systemName: "clock.circle.fill")
            }
        }
        .foregroundColor(statusColor)
        .font(.title2)
        .imageScale(.large)
    }
    
    private var statusText: some View {
        Text(statusTitle)
            .font(.headline)
            .fontWeight(.semibold)
    }
    
    // MARK: - Date Information Section
    
    private var dateInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
    // Date Information
            if let startDate = book.readDateStarted {
                DateRowView(
                    title: "Started",
                    date: startDate,
                    icon: "bookmark.fill",
                    color: .accent
                )
            }
            
            if let finishDate = book.readDateFinished {
                DateRowView(
                    title: "Finished",
                    date: finishDate,
                    icon: "book.closed.fill",
                    color: .green
                )
            }
            
            if book.readingStatus == .notStarted {
                HStack {
                    Image(systemName: "books.vertical.fill")
                        .foregroundColor(.orange)
                        .frame(width: 20)
                    Text("Ready to start reading")
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    // MARK: - Statistics Section
    
    private var statisticsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reading Stats")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(statisticsData, id: \.title) { stat in
                    StatisticCard(
                        title: stat.title,
                        value: stat.value,
                        icon: stat.icon,
                        color: stat.color
                    )
                }
            }
        }
    }
    
    // MARK: - Helper Properties
    
    private var statusTitle: String {
        switch book.readingStatus {
        case .notStarted:
            return "On the shelf"
        case .reading:
            return "Currently reading"
        case .read:
            return "Completed"
        }
    }
    
    private var statusColor: Color {
        switch book.readingStatus {
        case .notStarted:
            return .orange
        case .reading:
            return .cyan
        case .read:
            return .green
        }
    }
    
    private var statisticsData: [StatisticData] {
        var stats: [StatisticData] = []
        
        if let startDate = book.readDateStarted {
            let referenceDate = book.readDateFinished ?? Date()
            let daysDiff = Calendar.current.dateComponents([.day], from: startDate, to: referenceDate).day ?? 0
            
            let readingSpeed: String
            let readingSpeedColor: Color
            switch daysDiff {
            case 0..<7:
                readingSpeedColor = .green
                readingSpeed = "Fast"
            case 7..<14:
                readingSpeedColor = .orange
                readingSpeed = "Moderate"
            default:
                readingSpeedColor = .red
                readingSpeed = "Slow"
            }
            
            stats.append(StatisticData(
                title: book.readingStatus == .reading ? "Days so far" : "Reading time",
                value: formatDays(daysDiff),
                icon: "calendar",
                color: .accent
            ))
            
            if book.readingStatus == .reading {
                let weeksReading = max(1, daysDiff / 7)
                stats.append(StatisticData(
                    title: "Weeks reading",
                    value: "\(weeksReading)",
                    icon: "calendar.badge.clock",
                    color: .purple
                ))
            } else if book.readingStatus == .read {
                stats.append(StatisticData(
                    title: "Reading speed",
                    value: readingSpeed,
                    icon: "speedometer",
                    color: readingSpeedColor
                ))
            }
        }
        
        return stats
    }
    
    private func formatDays(_ days: Int) -> String {
        if days == 0 {
            return "Today"
        } else if days == 1 {
            return "1 day"
        } else if days < 30 {
            return "\(days) days"
        } else {
            let months = days / 30
            let remainingDays = days % 30
            if remainingDays == 0 {
                return months == 1 ? "1 month" : "\(months) months"
            } else if months < 12 {
                return "\(months)mo \(remainingDays)d"
            } else {
                let years = months / 12
                let remainingMonths = months % 12
                return "\(years)y \(remainingMonths)mo"
            }
        }
    }
}

// MARK: - Supporting Views

struct DateRowView: View {
    let title: String
    let date: Date
    let icon: String
    let color: Color
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(dateFormatter.string(from: date))
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            
            Spacer()
            
            Text(relativeDate(from: date))
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private func relativeDate(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct StatisticCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .imageScale(.medium)
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.headline)
                    .fontWeight(.bold)
                
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(.thickMaterial)
        .cornerRadius(12)
    }
}

struct StatisticData {
    let title: String
    let value: String
    let icon: String
    let color: Color
}
