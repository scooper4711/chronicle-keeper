import ChronicleKeeperKit
import SwiftUI

/// The sign that free rewards are waiting on paizo.com (R3.9): a sparkle that says which in its help tag and, since
/// touch has no hover, opens a list of them with the way to paizo.com. It shows nothing when there are none.
struct ClaimSparkle: View {
    let rewards: [ClaimableReward]
    @State private var showsRewards = false

    var body: some View {
        if !rewards.isEmpty {
            Button { showsRewards = true } label: { SparkleSymbol() }
                .buttonStyle(.plain)
                .help(ClaimText.summary(of: rewards))
                .accessibilityLabel(ClaimText.summary(of: rewards))
                .accessibilityHint("Shows what to claim on paizo.com")
                .accessibilityIdentifier("claim-sparkle")
                .popover(isPresented: $showsRewards) {
                    ScrollView {
                        ClaimableRewardsList(rewards: rewards).padding()
                    }
                    .frame(minWidth: 320, idealWidth: 380, maxHeight: 420)
                    .presentationCompactAdaptation(.sheet)
                }
        }
    }
}

/// The sparkle itself, shimmering unless the device reduces motion. `isStill` holds it still where many show at
/// once, as in the sidebar.
struct SparkleSymbol: View {
    var isStill = false
    @Environment(\.accessibilityReduceMotion) private var reducesMotion

    var body: some View {
        Image(systemName: "sparkles")
            .foregroundStyle(Self.gold)
            .symbolEffect(.variableColor.iterative, options: .repeating, isActive: !isStill && !reducesMotion)
    }

    /// Dark enough to read on a light background, which system yellow isn't.
    static let gold = Color(red: 0.85, green: 0.58, blue: 0.0)
}

/// The words for rewards that are waiting.
enum ClaimText {
    /// "There's a Chronicle Boon you're eligible for: …", or how many there are.
    static func summary(of rewards: [ClaimableReward]) -> String {
        guard rewards.count == 1, let reward = rewards.first else {
            return "There are \(rewards.count) free rewards you're eligible for"
        }
        return "There's a \(kind(of: reward)) you're eligible for: \(reward.title)"
    }

    static func kind(of reward: ClaimableReward) -> String {
        reward.offers.first?.kind == .gameReward ? "Game Reward" : "Chronicle Boon"
    }

    static let choiceNote = "Your Chronicle Sheet says which one you earned: claiming one rules out the other."
    static let howToClaim = "They're free. On paizo.com, choose the character, open the list and press Purchase, "
        + "then refresh here."
}

/// Rewards a character may claim, each with what it does and why it is free now, and the way to paizo.com.
struct ClaimableRewardsList: View {
    let rewards: [ClaimableReward]
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(rewards) { reward in
                ClaimableRewardRow(reward: reward)
            }
            Button("Claim on paizo.com") { openURL(OrganizedPlayEndpoints().boonsPage) }
                .help("Opens the Boons tab of My Organized Play in your browser")
                .accessibilityIdentifier("claim-on-paizo")
            Text(ClaimText.howToClaim).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.callout)
    }
}

/// One reward, or an adventure's lettered boons with the note that only one of them was earned.
struct ClaimableRewardRow: View {
    let reward: ClaimableReward

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            SparkleSymbol(isStill: true).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(reward.title)
                ForEach(reward.offers) { offer in
                    Text(description(of: offer)).font(.caption).foregroundStyle(.secondary)
                }
                if reward.isChoice {
                    Text(ClaimText.choiceNote).font(.caption).foregroundStyle(.secondary)
                }
                Text(reward.reason).font(.caption)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    /// What the reward does; a lettered boon's has its letter first.
    private func description(of offer: RewardOffer) -> String {
        guard reward.isChoice, let letter = offer.name.split(separator: " ").last else { return offer.summary }
        return "\(letter): \(offer.summary)"
    }
}
