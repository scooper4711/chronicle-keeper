import ChronicleKeeperKit
import SwiftUI

/// How the adventures table orders its rows.
enum AdventureSort: String, CaseIterable, Identifiable {
    /// The site's own order: newest first.
    case date
    /// The order credit was actually banked (`SessionProgress.applyOrder`): a held Chronicle sorts with the
    /// sessions that finally caught the character up to it, not where it was originally played.
    case level

    var id: Self { self }
    var displayName: String { self == .date ? "Date" : "Level" }
}

/// Every session the character has, with the track each one counted on and the XP it gave. Sortable by date
/// (the site's own order, newest first) or by the order credit was actually banked (see `AdventureSort`).
struct AdventuresTable: View {
    let record: CharacterRecord
    let store: CharacterStore
    @State private var sort = AdventureSort.date

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    private var sessions: [SessionProgress] {
        guard sort == .level else { return record.sessions }
        return record.sessions.sorted { $0.applyOrder < $1.applyOrder }
    }

    var body: some View {
        CollapsibleSection(UnreportedText.adventuresTitle(of: record), id: "adventures") {
            AddChronicleMenu(record: record, store: store, isCompact: isCompact)
            Picker("Sort", selection: $sort) {
                ForEach(AdventureSort.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: isCompact ? 120 : 160)
        } content: {
            if sessions.isEmpty {
                Text("No sessions on paizo.com yet.").foregroundStyle(.secondary)
            } else if isCompact {
                compactList
            } else {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                    header
                    ForEach(sessions) { progress in
                        Divider()
                        AdventureRow(cells: AdventureCells(progress: progress, record: record, store: store))
                    }
                }
            }
        }
    }

    /// On an iPhone the five columns don't fit, so each session gets two lines instead.
    private var isCompact: Bool {
        #if os(iOS)
        sizeClass == .compact
        #else
        false
        #endif
    }

    private var compactList: some View {
        LazyVStack(alignment: .leading, spacing: 8) {
            ForEach(sessions) { progress in
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
            Text("Track")
            Text("Progress")
        }
        .font(.caption.bold())
        .foregroundStyle(.secondary)
    }
}

/// One session as a grid row: when and at what level it was played, what it was (its kind, XP and reputation in
/// small gray text under the title, which gets the room), how it counted, and a menu to correct its track.
struct AdventureRow: View {
    let cells: AdventureCells

    var body: some View {
        GridRow {
            cells.date
            cells.level
            VStack(alignment: .leading, spacing: 2) {
                cells.title
                cells.caption
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .chronicleDropTarget(for: cells.sheet)
            cells.trackMenu
            cells.progressCell
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
                HStack(spacing: 2) { cells.xpAwarded; Text("XP") }
            }
            cells.progressCell
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .font(.callout)
        .chronicleDropTarget(for: cells.sheet)
    }
}

/// The pieces of a session's row, shared by the grid and the two-line layout.
@MainActor
struct AdventureCells {
    let progress: SessionProgress
    let record: CharacterRecord
    let store: CharacterStore

    private var session: PlayedSession { progress.session }

    /// The session's chronicle sheet, for its button and for a PDF dropped on the row (R1.13).
    var sheet: SessionSheet { SessionSheet(session: session, record: record, store: store) }

    var date: some View {
        SessionDateCell(date: progress.date, eventName: session.eventName)
    }

    /// The level the credit landed at: "3", or "3*" when it was a held Chronicle (see `progressCell` for how far
    /// into that level it left the character).
    var level: some View {
        Text(progress.isOutOfLevelRange ? "\(progress.creditLevel)*" : "\(progress.creditLevel)")
            .monospacedDigit()
            .help(progress.isOutOfLevelRange ? SessionExplanation.heldChronicle(progress) : "")
            .accessibilityLabel(progress.isOutOfLevelRange
                ? "Credited at level \(progress.creditLevel): played at level \(progress.levelWhenPlayed), "
                    + "outside the adventure's level range"
                : "Level \(progress.creditLevel) when played")
    }

    /// "10/12" with a short progress bar, matching the sidebar's level summary but sized for a table row.
    var progressCell: some View {
        let perLevel = record.level.xpPerLevel
        return VStack(alignment: .leading, spacing: 1) {
            Text("\(XPText.of(progress.creditProgress))/\(XPText.of(perLevel))").font(.caption2).monospacedDigit()
            ProgressView(value: min(progress.creditProgress / perLevel, 1))
                .progressViewStyle(.linear)
                .frame(maxWidth: 70)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(XPText.of(progress.creditProgress)) of \(XPText.of(perLevel)) XP into the level")
    }

    /// The adventure's title, which opens the session's details (`SessionDetailView`), and its chronicle sheet.
    /// A session paizo.com doesn't list yet is in another color, says so under its title and has a badge (R1.14).
    var title: some View {
        HStack(alignment: .top, spacing: 4) {
            NavigationLink(value: SessionRoute(sessionID: progress.id)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.adventure.titleWithLevels)
                        .lineLimit(2).multilineTextAlignment(.leading)
                        .foregroundStyle(session.isReported ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.unreported))
                    if let status {
                        Text(status).font(.caption).foregroundStyle(.secondary)
                            .accessibilityIdentifier("session-status")
                    }
                }
            }
            .buttonStyle(.plain)
            .help("Show everything about this session")
            .accessibilityHint("Shows the session's details")
            .accessibilityIdentifier("session-details")
            if !session.isReported { UnreportedBadge() }
            ChronicleButton(sheet: sheet)
            ClaimSparkle(rewards: claimable)
        }
    }

    /// The small line right under the title: "GM credit", or that paizo.com doesn't list the session yet.
    private var status: String? {
        if !session.isReported { return UnreportedText.caption(added: sheet.reading?.addedAt) }
        return session.isGameMaster ? "GM credit" : nil
    }

    /// The free rewards this session earned that the character hasn't claimed (R3.9).
    var claimable: [ClaimableReward] {
        store.claimableRewards(for: record.id).filter { $0.sessionIDs.contains(progress.id) }
    }

    var reputation: some View {
        Text(session.reputation.map(XPText.of) ?? "—").monospacedDigit()
    }

    /// "Scenario · 4 XP · 2 Rep" (see `SessionCaption`), small and gray under the title in the grid.
    var caption: some View {
        Text(SessionCaption.text(for: progress, showsReputation: record.campaign.showsReputation))
            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            .help(SessionExplanation.xp(progress))
    }

    /// The XP the Chronicle awards, as the Guide's rules give it (slow track already applied). "Progress" (see
    /// `progressCell`) shows what actually counted, which can be less when this was a held Chronicle (R2.7).
    @ViewBuilder
    var xpAwarded: some View {
        HStack(spacing: 2) {
            Text(XPText.of(progress.xp)).monospacedDigit()
            if progress.xpLost > 0 {
                Text("(\(XPText.of(progress.xpLost)) lost)").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .help(SessionExplanation.xp(progress))
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
            get: { record.settings.override(for: session)?.track },
            set: { track in
                store.update(record.id) { settings in
                    var override = settings.override(for: session) ?? SessionOverride()
                    override.track = track
                    settings.setOverride(override, for: session)
                }
            })
    }
}

/// Why a session counts on the track it does.
enum TrackExplanation {
    static func of(_ source: TrackSource) -> String {
        switch source {
        case .override: "You set this track."
        case .chronicle: "From the XP on the Chronicle Sheet."
        case .inferred: "Worked out from the reputation the session gave."
        case .campaignRule: "The campaign had no slow track when this was played."
        case .characterDefault: "The character's default track: the session doesn't show which track it was."
        }
    }
}
