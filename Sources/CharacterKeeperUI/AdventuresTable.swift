import CharacterKeeperKit
import SwiftUI

/// Every session the character has, newest first, with the track each one counted on and the XP it gave.
struct AdventuresTable: View {
    let record: CharacterRecord
    let store: CharacterStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Adventures (\(record.sessions.count))").font(.headline)
            if record.sessions.isEmpty {
                Text("No sessions on paizo.com yet.").foregroundStyle(.secondary)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                    header
                    ForEach(record.sessions) { progress in
                        Divider()
                        AdventureRow(progress: progress, record: record, store: store)
                    }
                }
            }
        }
    }

    private var header: some View {
        GridRow {
            Text("Date")
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

/// One session: what was played, how it counted, and a menu to correct its track.
struct AdventureRow: View {
    let progress: SessionProgress
    let record: CharacterRecord
    let store: CharacterStore

    private var session: PlayedSession { progress.session }

    var body: some View {
        GridRow {
            Text(session.date.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "—")
                .monospacedDigit()
            VStack(alignment: .leading, spacing: 2) {
                Text(session.adventure.title).lineLimit(2)
                if session.isGameMaster {
                    Text("GM credit").font(.caption).foregroundStyle(.secondary)
                }
            }
            Text(progress.kind.displayName)
            Text(session.reputation.map(XPText.of) ?? "—").monospacedDigit()
            trackMenu
            Text(XPText.of(progress.xp)).monospacedDigit()
                .help(progress.xpSource == .estimated ? "Estimated from the Achievement Points" : "")
        }
        .font(.callout)
    }

    private var trackMenu: some View {
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
