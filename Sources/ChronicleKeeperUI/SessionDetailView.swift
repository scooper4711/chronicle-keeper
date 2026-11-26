import ChronicleKeeperKit
import SwiftUI

/// Where an adventure's title in the adventures table leads: that session's details.
struct SessionRoute: Hashable {
    let sessionID: SessionProgress.ID
}

/// One session, laid out like a message: the adventure as its subject, the Game Master as its sender, everything
/// the table's row abbreviates spelled out as its text, and the chronicle sheet below as its attachment.
struct SessionDetailView: View {
    let characterID: CharacterRecord.ID
    let route: SessionRoute
    let store: CharacterStore

    /// Looked up on every update, so a changed track or a refresh shows here too.
    private var record: CharacterRecord? { store.roster.characters.first { $0.id == characterID } }

    var body: some View {
        if let record, let progress = record.sessions.first(where: { $0.id == route.sessionID }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    SessionHeader(
                        progress: progress, characterName: record.name, cover: store.cover(of: progress.session))
                    Divider()
                    SessionFacts(cells: AdventureCells(progress: progress, record: record, store: store))
                    Divider()
                    ChronicleSheetSection(session: progress.session, characterNumber: record.id, store: store)
                }
                .padding(20)
                .frame(maxWidth: 700, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(progress.session.adventure.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        } else {
            ContentUnavailableView(
                "Session Not Found", systemImage: "envelope.open",
                description: Text("paizo.com no longer lists this session for this character."))
        }
    }
}

/// The top of the message: the adventure, who ran it and for which character, and when.
struct SessionHeader: View {
    let progress: SessionProgress
    let characterName: String
    /// The adventure's cover, once it has been looked up; the header does without one until then.
    let cover: URL?

    private var session: PlayedSession { progress.session }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                if let cover { CoverArt(url: cover, width: 72) }
                Text(session.adventure.titleWithLevels)
                    .font(.title2.bold())
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .top, spacing: 12) {
                InitialsBadge(name: session.gameMaster, color: session.campaign.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.gameMaster.isEmpty ? "No Game Master listed" : session.gameMaster).font(.headline)
                    Text(session.isGameMaster ? "Game Master · GM credit" : "Game Master")
                    Text("To: \(characterName)")
                }
                Spacer(minLength: 8)
                SessionDateCell(date: progress.date, eventName: session.eventName)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }
}

/// A sender's initials in a circle, as a mail app shows someone without a picture.
struct InitialsBadge: View {
    let name: String
    let color: Color

    private var initials: String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
    }

    var body: some View {
        Text(initials.isEmpty ? "?" : initials)
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 40, height: 40)
            .background(color.gradient, in: Circle())
            .accessibilityHidden(true)
    }
}

/// The text of the message: what the adventure was and how the session counted, one fact at a time.
struct SessionFacts: View {
    let cells: AdventureCells

    private var progress: SessionProgress { cells.progress }
    private var session: PlayedSession { progress.session }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !session.adventure.summary.isEmpty {
                Text(session.adventure.summary).fixedSize(horizontal: false, vertical: true)
            }
            SessionFact("Adventure", text: SessionFactText.adventure(progress))
            SessionFact(
                "Level", text: SessionFactText.level(progress),
                note: progress.isOutOfLevelRange ? SessionExplanation.heldChronicle(progress) : "")
            SessionFact("Track", note: TrackExplanation.of(progress.trackSource)) { cells.trackMenu }
            SessionFact("XP", text: SessionFactText.xp(progress), note: SessionExplanation.xp(progress))
            SessionFact("Progress") { progressBar }
            if !SessionFactText.reputation(session).isEmpty {
                SessionFact("Reputation", text: SessionFactText.reputation(session))
            }
            SessionFact("Points", text: SessionFactText.points(session.points))
            SessionFact("Event", text: SessionFactText.event(session))
            if !session.notes.isEmpty {
                SessionFact("Notes on paizo.com", text: session.notes)
            }
            if !cells.claimable.isEmpty {
                SessionFact("Ready to Claim") { ClaimableRewardsList(rewards: cells.claimable) }
            }
        }
    }

    private var progressBar: some View {
        let perLevel = cells.record.level.xpPerLevel
        return VStack(alignment: .leading, spacing: 4) {
            Text(SessionFactText.progress(progress, perLevel: perLevel)).monospacedDigit()
            ProgressView(value: min(progress.creditProgress / perLevel, 1))
                .progressViewStyle(.linear)
                .frame(maxWidth: 260)
                .accessibilityHidden(true)
        }
    }
}

/// One fact of a session: what it is, its value, and a sentence of explanation where the value needs one.
struct SessionFact<Value: View>: View {
    private let label: String
    private let note: String
    private let value: Value

    init(_ label: String, note: String = "", @ViewBuilder value: () -> Value) {
        self.label = label
        self.note = note
        self.value = value()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
            value
            if !note.isEmpty {
                Text(note).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

extension SessionFact where Value == Text {
    init(_ label: String, text: String, note: String = "") {
        self.init(label, note: note) { Text(text) }
    }
}
