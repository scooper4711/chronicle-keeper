import ChronicleKeeperKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// One character: level and XP, reputation, the user's own notes and settings, and every adventure played.
struct CharacterDetailView: View {
    let record: CharacterRecord
    let store: CharacterStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                CharacterHeader(record: record, store: store)
                if record.campaign.showsReputation {
                    ReputationGrid(summary: record.summary, claimable: store.claimableRewards(for: record.id))
                }
                AdventuresTable(record: record, store: store)
                if CampaignRules(campaign: record.campaign).hasLedger {
                    WealthSection(record: record, store: store)
                }
                BoonsSection(
                    boons: store.roster.boons(for: record.id), claimable: store.claimableRewards(for: record.id),
                    store: store)
                CharacterSettingsForm(record: record, store: store)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(record.name)
        .navigationDestination(for: SessionRoute.self) { route in
            SessionDetailView(characterID: record.id, route: route, store: store)
        }
        #if os(iOS)
        // The header already shows the name large.
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

/// Portrait, name, number, campaign and level, with a badge when the character has enough XP to level up.
struct CharacterHeader: View {
    let record: CharacterRecord
    let store: CharacterStore
    @Environment(\.portraits) private var portraits
    @Environment(\.openURL) private var openURL
    @State private var choosesPortrait = false
    @State private var choosesPhoto = false
    @State private var photo: PhotosPickerItem?
    @State private var hasClipboardImage = false

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            PortraitButton(
                record: record,
                choose: { choosesPortrait = true },
                drop: dropPortrait,
                choices: { portraitMenu }
            )
            .contextMenu { portraitMenu }
            VStack(alignment: .leading, spacing: 6) {
                Text(record.name).font(.title.bold())
                Text("\(record.campaign.displayName) · \(record.id)")
                    .foregroundStyle(.secondary).monospacedDigit()
                LevelSummary(level: record.level)
                if record.unreportedCount > 0 {
                    Label(UnreportedText.totalsNote(count: record.unreportedCount), systemImage: "clock")
                        .font(.caption).foregroundStyle(Color.unreported)
                        .accessibilityIdentifier("unreported-totals")
                }
                if let sheet = record.settings.characterSheetURL {
                    Button("Open Character Sheet") { openURL(sheet) }
                }
            }
        }
        .fileImporter(isPresented: $choosesPortrait, allowedContentTypes: [.image]) { result in
            if case .success(let url) = result { savePortrait(from: url) }
        }
        .photosPicker(isPresented: $choosesPhoto, selection: $photo, matching: .images)
        .onChange(of: photo) { _, item in Task { await savePortrait(from: item) } }
        .task { await watchClipboard() }
    }

    private var editor: PortraitEditor {
        PortraitEditor(number: record.id, store: store, portraits: portraits)
    }

    /// The clipboard and Demiplane when they have a picture, then Photos or Files on the iPhone and iPad, or a file
    /// on the Mac.
    @ViewBuilder private var portraitMenu: some View {
        if hasClipboardImage {
            Button("Paste Image") { editor.paste(from: SystemPasteboard.general) }
        }
        if let sheet = DemiplanePortraitSource.sheetURL(from: record.settings.characterSheetURL) {
            Button("Use Demiplane Portrait") {
                Task { await editor.usePortrait(fromSheet: sheet, source: .forApp) }
            }
        }
        #if os(iOS)
        Button("Choose from Photos…") { choosesPhoto = true }
        Button("Choose from Files…") { choosesPortrait = true }
        #else
        Button("Choose Portrait…") { choosesPortrait = true }
        #endif
        if !record.settings.portraitFileName.isEmpty {
            Button("Remove Portrait", role: .destructive, action: editor.remove)
        }
    }

    /// Follows the clipboard while the header is on screen, since another app can copy a picture beside this one
    /// on an iPad. The change count is cheap to read and never asks the user for permission to paste.
    private func watchClipboard() async {
        let pasteboard = SystemPasteboard.general
        var seen: Int?
        while !Task.isCancelled {
            if seen != pasteboard.changeCount {
                seen = pasteboard.changeCount
                hasClipboardImage = pasteboard.hasImage
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }

    private func dropPortrait(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadDataRepresentation(for: .image) { data, _ in
            guard let data else { return }
            Task { @MainActor in editor.save(data) }
        }
        return true
    }

    private func savePortrait(from item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self) else { return }
        photo = nil
        editor.save(data)
    }

    private func savePortrait(from url: URL) {
        let isScoped = url.startAccessingSecurityScopedResource()
        defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return }
        editor.save(data)
    }
}

extension DemiplanePortraitSource {
    static let forApp = DemiplanePortraitSource(http: URLSessionHTTPClient())
}

/// The portrait in the header, which says what clicking it does: on hover, or while a picture is dragged over it.
struct PortraitButton<Choices: View>: View {
    let record: CharacterRecord
    let choose: () -> Void
    let drop: ([NSItemProvider]) -> Bool
    @ViewBuilder let choices: () -> Choices
    @State private var isHovered = false
    @State private var isDropTarget = false

    var body: some View {
        control
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .onDrop(of: [.image, .fileURL], isTargeted: $isDropTarget, perform: drop)
            .animation(.easeOut(duration: 0.15), value: isHovered || isDropTarget)
            .help("Choose a portrait, drop a picture here, or right-click to paste one")
            .accessibilityLabel(record.settings.portraitFileName.isEmpty ? "Choose Portrait" : "Change Portrait")
    }

    /// A tap offers Photos or Files on the iPhone and iPad; a click opens a file on the Mac.
    @ViewBuilder private var control: some View {
        #if os(iOS)
        Menu(content: choices) { face }.menuStyle(.button)
        #else
        Button(action: choose) { face }
        #endif
    }

    private var face: some View {
        PortraitView(record: record, side: 96)
            .overlay { if isHovered || isDropTarget { hint } }
    }

    private var hint: some View {
        VStack(spacing: 4) {
            Image(systemName: isDropTarget ? "square.and.arrow.down" : "camera.fill").font(.title2)
            Text(isDropTarget ? "Drop Picture" : (record.settings.portraitFileName.isEmpty ? "Choose…" : "Change…"))
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 96 / 5))
        .transition(.opacity)
    }
}

/// Paizo's own reputation and Fame totals, as the Summary tab shows them.
struct ReputationGrid: View {
    let summary: CharacterSummary
    /// The free rewards the character may claim; a faction's tile sparkles for the ones its reputation earned.
    var claimable: [ClaimableReward] = []

    /// The statuses reputation earns in the character's campaign (R2.10); Fame and Total Reputation earn none.
    private var ladder: ReputationLadder { CampaignRules(campaign: summary.campaign).reputationLadder }
    /// Room for the status line where the campaign has statuses, on every tile so the grid stays even.
    private var tileHeight: CGFloat { ladder.isEmpty ? 120 : 136 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Reputation").font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)], spacing: 12) {
                ForEach(summary.factions, id: \.name) { value in
                    ReputationTile(value: value, height: tileHeight, status: ladder.status(for: value.value))
                        .help(ladder.distanceToNextStatus(from: value.value))
                        .accessibilityHint(ladder.distanceToNextStatus(from: value.value))
                        .overlay(alignment: .topTrailing) {
                            ClaimSparkle(rewards: claimable.filter { $0.faction == value.name }).padding(8)
                        }
                }
                ForEach(summary.standing, id: \.name) { value in
                    ReputationTile(value: value, height: tileHeight)
                }
            }
            if summary.factions.isEmpty && summary.standing.isEmpty {
                Text("paizo.com shows no reputation for this character yet.").foregroundStyle(.secondary)
            }
        }
    }
}

/// A narrow tile: the faction's symbol, faded, fills its middle, and the number, the name and the status the
/// reputation has earned ("Liked"; empty where there is none) sit centered over it.
struct ReputationTile: View {
    let value: NamedValue
    let height: CGFloat
    var status = ""

    var body: some View {
        VStack(spacing: 2) {
            Text("\(value.value)").font(.largeTitle.bold()).monospacedDigit()
            Text(value.name).font(.callout).multilineTextAlignment(.center)
            if !status.isEmpty {
                // Bold and in the text color: gray is lost over the symbol.
                Text(status).font(.footnote.bold())
            }
        }
        .padding(.horizontal, 6)
        .frame(width: 140, height: height)
        .accessibilityElement(children: .combine)
        .background { FactionSymbol(faction: value.name, size: 100).opacity(0.3) }
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

extension Campaign {
    /// Starfinder Society (2nd Edition) has no factions.
    var showsReputation: Bool { self != .starfinder2 }
}
