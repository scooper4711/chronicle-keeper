import ChronicleKeeperKit
import SwiftUI

/// An adventure's cover, title, campaign and levels.
struct AdventureEntryRow: View {
    let entry: AdventureEntry
    var coverWidth: CGFloat = 34

    var body: some View {
        HStack(spacing: 10) {
            CoverArt(url: entry.coverArt, width: coverWidth)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                Text(AdventureEntryText.details(of: entry)).font(.caption).foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }
}

/// "PFS2 · Scenario · Levels 3–6 · Repeatable".
enum AdventureEntryText {
    static func details(of entry: AdventureEntry) -> String {
        var parts = [entry.campaign.shortName]
        if entry.kind != .other { parts.append(entry.kind.displayName) }
        parts.append(entry.levelRange?.displayText ?? "Levels unknown")
        if entry.isRepeatable { parts.append("Repeatable") }
        return parts.joined(separator: " · ")
    }
}

/// An adventure's cover in a book's proportions, or a plain book while it loads and for one without a cover.
struct CoverArt: View {
    let url: URL?
    let width: CGFloat

    var body: some View {
        AsyncImage(url: url) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            ZStack {
                Rectangle().fill(.quaternary)
                Image(systemName: "book.closed").font(.system(size: width * 0.4)).foregroundStyle(.tertiary)
            }
        }
        .frame(width: width, height: width * 1.3)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .accessibilityHidden(true)
    }
}

/// The adventure, then the characters who can play it, then the rest, dimmed, with the reason they can't.
struct CandidateList: View {
    let adventure: AdventureEntry
    let roster: CharacterRoster
    let open: (CharacterRecord.ID) -> Void

    var body: some View {
        let candidates = AdventureFinder.candidates(for: adventure, in: roster)
        List {
            Section {
                AdventureEntryRow(entry: adventure, coverWidth: 64)
            }
            Section("Can Play") {
                rows(candidates.filter(\.eligibility.isEligible))
            }
            Section("Can't Play") {
                rows(candidates.filter { !$0.eligibility.isEligible })
            }
        }
    }

    private func rows(_ candidates: [Candidate]) -> some View {
        ForEach(candidates) { candidate in
            Button { open(candidate.id) } label: {
                HStack {
                    CharacterRow(record: candidate.character)
                    Spacer()
                    Text(EligibilityText.of(candidate.eligibility)).font(.caption).foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(candidate.eligibility.isEligible ? 1 : 0.55)
        }
    }
}

/// Why a character can or can't play: "played Apr 25, 2025", "level 9, range 1–4".
enum EligibilityText {
    static func of(_ eligibility: Eligibility) -> String {
        switch eligibility {
        case .eligible: ""
        case .alreadyPlayed(let date): played(date)
        case .outsideLevels(let level, let range): "level \(level), range \(range.displayText)"
        }
    }

    /// "played about Sep 26, 2024" when paizo.com gave no date and it's the last day of the session's convention.
    private static func played(_ date: SessionDate) -> String {
        guard date.day != nil else { return "already played" }
        return (date.isInferred ? "played about " : "played ") + SessionDateText.day(date)
    }
}
