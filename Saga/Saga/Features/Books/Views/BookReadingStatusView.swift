//
//  BookReadingStatusView.swift
//  Saga
//
//  Created by Dylan Gattey on 8/23/25.
//

import SwiftUI

struct BookReadingStatusView: View {
  let book: Book
  @Namespace private var glassNamespace

  var body: some View {
    GlassEffectContainer(spacing: 12) {
      VStack(alignment: .leading, spacing: 16) {
        HStack(spacing: 10) {
          statusIcon
          statusText
          Spacer()
        }

        dateInfoSection

        if book.readingStatus != .notStarted {
          statisticsSection
        }
      }
      .padding(16)
      .glassEffect(
        .regular.tint(Color.botanicalLeaf.opacity(0.08)),
        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
      )
      .glassEffectID("reading-status-card", in: glassNamespace)
    }
  }

  // MARK: - Status Components

  private var statusIcon: some View {
    Group {
      switch book.readingStatus {
      case .reading:
        Image(systemName: "bookmark.circle.fill")
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
      if let startDate = book.readDateStarted {
        DateRowView(
          title: "Started",
          date: startDate,
          icon: "bookmark.fill",
          color: .botanicalSage
        )
      }

      if let finishDate = book.readDateFinished {
        DateRowView(
          title: "Finished",
          date: finishDate,
          icon: "book.closed.fill",
          color: .botanicalLeaf
        )
      }

      if book.readingStatus == .notStarted {
        HStack {
          Image(systemName: "books.vertical.fill")
            .foregroundColor(.botanicalGold)
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

      LazyVGrid(
        columns: [
          GridItem(.flexible()),
          GridItem(.flexible()),
        ], spacing: 12
      ) {
        ForEach(statisticsData, id: \.title) { stat in
          StatisticCard(
            title: stat.title,
            value: stat.value,
            icon: stat.icon,
            color: stat.color
          )
          .glassEffectID(stat.title, in: glassNamespace)
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
      return .botanicalGold
    case .reading:
      return .botanicalSage
    case .read:
      return .botanicalLeaf
    }
  }

  private var statisticsData: [StatisticData] {
    var stats: [StatisticData] = []

    if let startDate = book.readDateStarted {
      let referenceDate = book.readDateFinished ?? Date()
      let daysDiff =
        Calendar.current.dateComponents([.day], from: startDate, to: referenceDate).day ?? 0

      let readingSpeed: String
      let readingSpeedColor: Color
      switch daysDiff {
      case 0..<7:
        readingSpeedColor = .botanicalLeaf
        readingSpeed = "Fast"
      case 7..<14:
        readingSpeedColor = .botanicalGold
        readingSpeed = "Moderate"
      default:
        readingSpeedColor = .botanicalTerracotta
        readingSpeed = "Slow"
      }

      stats.append(
        StatisticData(
          title: book.readingStatus == .reading ? "Days so far" : "Reading time",
          value: formatDays(daysDiff),
          icon: "calendar",
          color: .botanicalSage
        ))

      if book.readingStatus == .reading {
        let weeksReading = max(1, daysDiff / 7)
        stats.append(
          StatisticData(
            title: "Weeks reading",
            value: "\(weeksReading)",
            icon: "calendar.badge.clock",
            color: .botanicalMoss
          ))
      } else if book.readingStatus == .read {
        stats.append(
          StatisticData(
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
  private static let mediumDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    return formatter
  }()

  private static let relativeDateFormatter: RelativeDateTimeFormatter = {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .short
    return formatter
  }()

  let title: String
  let date: Date
  let icon: String
  let color: Color

  var body: some View {
    HStack {
      Image(systemName: icon)
        .foregroundColor(color)

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.caption)
          .foregroundColor(.secondary)
        Text(Self.mediumDateFormatter.string(from: date))
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
    Self.relativeDateFormatter.localizedString(for: date, relativeTo: Date())
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
    .glassEffect(
      .regular.tint(color.opacity(0.06)),
      in: RoundedRectangle(cornerRadius: 12, style: .continuous)
    )
  }
}

struct StatisticData {
  let title: String
  let value: String
  let icon: String
  let color: Color
}
