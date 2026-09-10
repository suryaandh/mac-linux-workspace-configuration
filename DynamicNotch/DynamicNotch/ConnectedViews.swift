import SwiftUI
import EventKit

struct CalendarPageView: View {
    @Bindable private var store = CalendarStore.shared
    @State private var month = Calendar.current.dateInterval(of: .month, for: Date())!.start
    private var calendar: Calendar { Calendar.current }
    private var days: [Date?] {
        let count = calendar.range(of: .day, in: .month, for: month)?.count ?? 0
        let offset = (calendar.component(.weekday, from: month) - calendar.firstWeekday + 7) % 7
        return Array(repeating: nil, count: offset) + (0..<count).map { calendar.date(byAdding: .day, value: $0, to: month) }
    }
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 8) {
                HStack {
                    Button { move(-1) } label: { Image(systemName: "chevron.left") }.help("Previous month")
                    Spacer()
                    Text(month, format: .dateTime.month(.wide).year()).font(.system(size: 13, weight: .semibold)) 
                    Spacer()
                    Button { move(1) } label: { Image(systemName: "chevron.right") }.help("Next month")
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 3) {
                    ForEach(0..<7, id: \.self) { index in
                        Text(calendar.veryShortStandaloneWeekdaySymbols[(index + calendar.firstWeekday - 1) % 7]).foregroundStyle(.secondary)
                    }
                    ForEach(days.indices, id: \.self) { index in
                        if let date = days[index] {
                            Button { store.selectedDate = date } label: {
                                VStack(spacing: 2) {
                                    Text("\(calendar.component(.day, from: date))")
                                        .frame(maxWidth: .infinity).frame(height: 21)
                                        .background(calendar.isDate(date, inSameDayAs: store.selectedDate) ? Color.white.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 6))
                                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(calendar.isDateInToday(date) ? Color.white.opacity(0.4) : .clear))
                                    Circle()
                                        .fill(store.hasEvents(on: date) ? Color.white.opacity(0.5) : .clear)
                                        .frame(width: 3, height: 3)
                                }
                            }
                        } else { Color.clear.frame(height: 21) }
                    }
                }.font(.system(size: 11))
                Button("Today") { store.selectedDate = Date(); month = calendar.dateInterval(of: .month, for: Date())!.start }
            }.padding(12).frame(width: 264)
                .background(LinearGradient(colors: [.white.opacity(0.07), .white.opacity(0.03)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.08)))
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("YOUR SCHEDULE").font(.system(size: 8, weight: .semibold)).tracking(1.5).foregroundStyle(.secondary)
                        Text(store.selectedDate, format: .dateTime.weekday().month().day()).font(.headline)
                    }
                    Spacer()
                    Button { store.refresh() } label: { Image(systemName: "arrow.clockwise") }.help("Refresh events")
                }
                if !store.authorized {
                    Text(store.status).foregroundStyle(.secondary)
                    Button(store.requesting ? "Requesting access…" : "Allow Calendar access") { Task { await store.connect() } }.buttonStyle(.borderedProminent).disabled(store.requesting)
                    Button("Open Calendar privacy settings") { store.openPrivacy() }
                    Button("Connect Google account…") { store.openAccounts() }
                    Text("Add Google in Internet Accounts and enable Calendars, then allow access here.").font(.caption).foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 9) {
                            if store.events.isEmpty {
                                VStack(spacing: 8) {
                                    Image(systemName: "calendar.badge.checkmark").font(.system(size: 26)).foregroundStyle(.secondary)
                                    Text("A little breathing room").fontWeight(.medium)
                                    Text(store.status).font(.caption).foregroundStyle(.secondary)
                                }.frame(maxWidth: .infinity).padding(.vertical, 25)
                            }
                            ForEach(Array(store.events.enumerated()), id: \.offset) { _, event in
                                HStack(spacing: 0) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color(cgColor: event.calendar.cgColor))
                                        .frame(width: 3)
                                        .padding(.vertical, 10)
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(alignment: .firstTextBaseline) {
                                            Text(event.title ?? "Untitled event")
                                                .fontWeight(.semibold)
                                                .lineLimit(1)
                                            Spacer(minLength: 4)
                                            if event.isAllDay {
                                                Text("All day")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            } else {
                                                Text(event.startDate, style: .time)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        HStack(spacing: 4) {
                                            Text(event.calendar.title)
                                                .font(.caption)
                                                .foregroundStyle(.tertiary)
                                            if let location = event.location, !location.isEmpty {
                                                Text("·").foregroundStyle(.tertiary)
                                                Text(location).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                                            }
                                        }
                                        if !event.isAllDay {
                                            Text("\(event.startDate, style: .time) – \(event.endDate, style: .time)")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.08)))
                            }
                        }
                    }
                    Button("Manage accounts…") { store.openAccounts() }.font(.caption)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.font(.system(size: 12)).onAppear { store.refresh() }
    }
    private func move(_ value: Int) { if let next = calendar.date(byAdding: .month, value: value, to: month) { month = next } }
}

struct WeatherPageView: View {
    @Bindable private var store = WeatherStore.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(store.location, systemImage: "location.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
                if store.loading {
                    ProgressView().controlSize(.small)
                } else {
                    Button {
                        Task { await store.loadFromDeviceLocation() }
                    } label: {
                        Image(systemName: "location.circle")
                    }
                    .help("Use my location")
                    Button {
                        Task { await store.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Refresh weather")
                }
            }
            if let weather = store.current {
                HStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        // Text(store.location).font(.headline).lineLimit(2)
                        Text("\(weather.temperature_2m, specifier: "%.0f")°C").font(.system(size: 32, weight: .light, design: .rounded))
                        Text(WeatherStore.condition(weather.weather_code)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Feels like \(weather.apparent_temperature, specifier: "%.0f")°C", systemImage: "thermometer.medium")
                        Label("Humidity \(weather.relative_humidity_2m, specifier: "%.0f")%", systemImage: "humidity")
                        Label("Wind \(weather.wind_speed_10m, specifier: "%.0f") km/h", systemImage: "wind")
                    }.font(.system(size: 12))
                }
                 if !store.forecast.isEmpty {
                    let now = Date()
                    let nearby = store.nearby6(around: now)

                    Divider()

                    Text("Hourly")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 0) {
                        ForEach(Array(nearby.enumerated()), id: \.element.id) { index, hour in
                            let isNow = Calendar.current.isDate(hour.start, equalTo: now, toGranularity: .hour)

                            HStack(spacing: 0) {
                            
                                VStack(spacing: 6) {
                                    Text(isNow ? "Now" : store.shortHour(hour))
                                        .font(.system(size: 10, weight: isNow ? .semibold : .regular))
                                        .monospacedDigit()
                                        .foregroundStyle(isNow ? .primary : .secondary)

                                    Image(systemName: WeatherStore.symbol(hour.code, isDay: hour.isDay))
                                        .symbolRenderingMode(.multicolor)
                                        .font(.system(size: 20))
                                        .frame(height: 21)
                                        .accessibilityLabel(WeatherStore.condition(hour.code))

                                    Text("\(hour.temperature, specifier: "%.0f")°")
                                        .font(.system(size: 12, weight: .semibold))
                                        .monospacedDigit()
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
            } else {
                Spacer()
                Label(store.status, systemImage: "cloud.sun").foregroundStyle(.secondary)
                Spacer()
            }
        }
    }
}
