import Foundation

/// The free reward lists, and what each character may claim from them (R1.9, R3.9).
extension CharacterStore {
    /// Reads the reward lists from this source after a refresh, when the saved copy is missing or has grown old.
    public func useRewardSource(_ source: RewardCatalogSource) {
        rewardSource = source
    }

    /// The rewards a character may claim on paizo.com and hasn't, in the lists' order.
    public func claimableRewards(for number: String) -> [ClaimableReward] {
        claimableRewards[number] ?? []
    }

    /// Shows the lists saved last time. A copy that can't be read counts as none, and is read again.
    func loadRewardCatalog() {
        rewardCatalog = try? repository.loadRewardCatalog()
        rewardEligibility = rewardCatalog.map(RewardEligibility.init)
        findClaimableRewards()
    }

    /// Reads the lists again when they are due, without holding up whoever asked. One reading runs at a time, and
    /// only for an account that has been read. A reading that fails leaves the saved lists and says nothing: the
    /// lists are an extra, and the next refresh tries again.
    func startRewardFetch() {
        guard let source = rewardSource, rewardFetch == nil, lastRefresh != nil,
              rewardCatalog?.isStale(at: Date()) ?? true else { return }
        rewardFetch = Task {
            let fresh = try? await source.rewardCatalog()
            guard !Task.isCancelled else { return }
            rewardFetch = nil
            if let fresh { keep(fresh) }
        }
    }

    /// Waits for the reading under way, if there is one.
    func waitForRewards() async {
        await rewardFetch?.value
    }

    /// Stops a reading under way, as when signing out.
    func stopRewardFetch() {
        rewardFetch?.cancel()
        rewardFetch = nil
    }

    /// Saves the lists just read. A reading that found none never replaces lists that are there: the page may have
    /// changed, and the next refresh looks again.
    private func keep(_ fresh: RewardCatalog) {
        guard !fresh.offers.isEmpty || rewardCatalog?.offers.isEmpty ?? true else { return }
        attempt { try repository.saveRewardCatalog(fresh) }
        rewardCatalog = fresh
        rewardEligibility = RewardEligibility(catalog: fresh)
        findClaimableRewards()
    }

    /// Works out each character's claimable rewards from the roster as it is. They depend on the account and the
    /// lists, not on the user's settings, so this runs when one of those changes and not on every edit. A character
    /// whose name another shares gets none: the Boons tab names only the character, so its boons can't be told
    /// (`CharacterRoster.attach`).
    func findClaimableRewards() {
        guard let eligibility = rewardEligibility else {
            claimableRewards = [:]
            return
        }
        let namesakes = Dictionary(grouping: roster.characters) { $0.name.lowercased() }
        var found: [String: [ClaimableReward]] = [:]
        for record in roster.characters where namesakes[record.name.lowercased()]?.count == 1 {
            let claims = eligibility.claimable(for: record, owned: roster.boons(for: record.id))
            if !claims.isEmpty { found[record.id] = claims }
        }
        claimableRewards = found
    }
}
