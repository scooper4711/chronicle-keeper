import CharacterKeeperKit
import SwiftUI

/// Every session the character has, newest first, with the track each one counted on and the XP it gave.
struct AdventuresTable: View {
    let record: CharacterRecord
    let store: CharacterStore

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Adventures (\(record.sessions.count))").font(.headline)
            if record.sessions.isEmpty {
                Text("No sessions on paizo.com yet.").foregroundStyle(.secondary)
            } else if isCompact {
                compactList
            } else {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                    header
                    ForEach(record.sessions) { progress in
                        Divider()
                        AdventureRow(cells: AdventureCells(progress: progress, record: record, store: store))
                    }
                }
            }
        }
    }

    /// On an iPhone the six columns don't fit, so each session gets two lines instead.
    private var isCompact: Bool {
        #if os(iOS)
        sizeClass == .compact
        #else
        false
        #endif
    }

    private var compactList: some View {
        LazyVStack(alignment: .leading, spacing: 8) {
            ForEach(record.sessions) { progress in
                Divider()
                CompactAdventureRow(cells: AdventureCells(progress: progress, record: record, store: store))
            }
        }
    }

    private var header: some View {
        GridRow {
            Text("Date")
            Text("Lv").help("The character's level when they played it")
            Text("Adventure")
            Text("Kind")
            Text("Rep")
            Text("Track")
            Text("XP").gridColumnAlignment(.trailing)
        }
        .font(.caption.bold())
        .foregroundStyle(.secondary)
    }
}

/// One session as a grid row: when and at what level it was played, what it was, how it counted, and a menu to
/// correct its track.
struct AdventureRow: View {
    let cells: AdventureCells

    var body: some View {
        GridRow {
            cells.date
            cells.level
            cells.title
            Text(cells.progress.kind.displayName)
            cells.reputation
            cells.trackMenu
            cells.xp
        }
        .font(.callout)
    }
}

/// One session on two lines, for narrow screens: the adventure, then its date, level, kind, reputation, track and XP.
struct CompactAdventureRow: View {
    let cells: AdventureCells

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            cells.title
            HStack(spacing: 8) {
                cells.date
                HStack(spacing: 2) { Text("Lv"); cells.level }
                Text(cells.progress.kind.displayName)
                HStack(spacing: 2) { Text("Rep"); cells.reputation }
                Spacer()
                cells.trackMenu
                HStack(spacing: 2) { cells.xp; Text("XP") }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .font(.callout)
    }
}

/// The pieces of a session's row, shared by the grid and the two-line layout.
@MainActor
struct AdventureCells {
    let progress: SessionProgress
    let record: CharacterRecord
    let store: CharacterStore

    private var session: PlayedSession { progress.session }

    var date: some View {
        Text(session.date.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "—")
            .monospacedDigit()
    }

    var level: some View {
        Text("\(progress.levelWhenPlayed)").monospacedDigit()
            .accessibilityLabel("Level \(progress.levelWhenPlayed) when played")
    }

    var title: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(session.adventure.titleWithLevels).lineLimit(2)
            if session.isGameMaster {
                Text("GM credit").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    var reputation: some View {
        Text(session.reputation.map(XPText.of) ?? "—").monospacedDigit()
    }

    var xp: some View {
        Text(XPText.of(progress.xp)).monospacedDigit()
            .help(progress.xpSource == .estimated ? "Estimated from the Achievement Points" : "")
    }

    var trackMenu: some View {
        Menu {
            Picker("Track", selection: overrideBinding) {
                Text("Work It Out").tag(Track?.none)
                ForEach(Track.allCases, id: \.self) { Text($0.displayName).tag(Track?.some($0)) }
            }
            .pickerStyle(.inline)
        } label: {
            Text(progress.track.displayName + (progress.trackSource == .override ? " •" : ""))
        }
        .fixedSize()
        .help(TrackExplanation.of(progress.trackSource))
    }

    private var overrideBinding: Binding<Track?> {
        Binding(
            get: { record.settings.overrides[session.id]?.track },
            set: { track in
                store.update(record.id) { settings in
                    var override = settings.overrides[session.id] ?? SessionOverride()
                    override.track = track
                    settings.overrides[session.id] = override
                }
            })
    }
}

/// Why a session counts on the track it does.
enum TrackExplanation {
    static func of(_ source: TrackSource) -> String {
        switch source {
        case .override: "You set this track."
        case .inferred: "Worked out from the reputation the session gave."
        case .campaignRule: "The campaign had no slow track when this was played."
        case .characterDefault: "The character's default track: the session doesn't show which track it was."
        }
    }
}
