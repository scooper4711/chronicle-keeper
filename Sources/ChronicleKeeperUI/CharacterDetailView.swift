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
                    ReputationGrid(summary: record.summary)
                }
                AdventuresTable(record: record, store: store)
                BoonsSection(boons: store.roster.boons(for: record.id), store: store)
                CharacterSettingsForm(record: record, store: store)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(record.name)
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

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            PortraitButton(record: record, choose: choosePortrait, drop: dropPortrait)
                .contextMenu { portraitMenu }
            VStack(alignment: .leading, spacing: 6) {
                Text(record.name).font(.title.bold())
                Text("\(record.campaign.displayName) · \(record.id)")
                    .foregroundStyle(.secondary).monospacedDigit()
                LevelSummary(level: record.level)
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
    }

    /// Photos on the iPhone and iPad, where most pictures are; a file on the Mac.
    private func choosePortrait() {
        #if os(iOS)
        choosesPhoto = true
        #else
        choosesPortrait = true
        #endif
    }

    @ViewBuilder private var portraitMenu: some View {
        #if os(iOS)
        Button("Choose from Photos…") { choosesPhoto = true }
        Button("Choose from Files…") { choosesPortrait = true }
        #else
        Button("Choose Portrait…") { choosesPortrait = true }
        #endif
        if !record.settings.portraitFileName.isEmpty {
            Button("Remove Portrait", role: .destructive, action: removePortrait)
        }
    }

    private func dropPortrait(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadDataRepresentation(for: .image) { data, _ in
            guard let data else { return }
            Task { @MainActor in savePortrait(data) }
        }
        return true
    }

    private func savePortrait(from item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self) else { return }
        photo = nil
        savePortrait(data)
    }

    private func savePortrait(from url: URL) {
        let isScoped = url.startAccessingSecurityScopedResource()
        defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return }
        savePortrait(data)
    }

    private func savePortrait(_ data: Data) {
        let previous = record.settings.portraitFileName
        guard let name = store.attempt({ try portraits.save(imageData: data, forCharacter: record.id) }) else {
            return
        }
        store.update(record.id) { $0.portraitFileName = name }
        if previous != name { _ = store.attempt { try portraits.remove(fileName: previous) } }
    }

    private func removePortrait() {
        let previous = record.settings.portraitFileName
        store.update(record.id) { $0.portraitFileName = "" }
        _ = store.attempt { try portraits.remove(fileName: previous) }
    }
}

/// The portrait in the header, which says what clicking it does: on hover, or while a picture is dragged over it.
struct PortraitButton: View {
    let record: CharacterRecord
    let choose: () -> Void
    let drop: ([NSItemProvider]) -> Bool
    @State private var isHovered = false
    @State private var isDropTarget = false

    var body: some View {
        Button(action: choose) {
            PortraitView(record: record, side: 96)
                .overlay { if isHovered || isDropTarget { hint } }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .onDrop(of: [.image, .fileURL], isTargeted: $isDropTarget, perform: drop)
        .animation(.easeOut(duration: 0.15), value: isHovered || isDropTarget)
        .help("Choose a portrait, or drop a picture here")
        .accessibilityLabel(record.settings.portraitFileName.isEmpty ? "Choose Portrait" : "Change Portrait")
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Reputation").font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)], spacing: 12) {
                ForEach(summary.factions + summary.standing, id: \.name) { value in
                    ReputationTile(value: value)
                }
            }
            if summary.factions.isEmpty && summary.standing.isEmpty {
                Text("paizo.com shows no reputation for this character yet.").foregroundStyle(.secondary)
            }
        }
    }
}

/// A narrow tile: the faction's symbol, faded, fills its middle, and the number and name sit centered over it.
struct ReputationTile: View {
    let value: NamedValue

    var body: some View {
        VStack {
            Text("\(value.value)").font(.largeTitle.bold()).monospacedDigit()
            Text(value.name).font(.callout).multilineTextAlignment(.center)
        }
        .padding(.horizontal, 6)
        .frame(width: 140, height: 120)
        .background { FactionSymbol(faction: value.name, size: 100).opacity(0.3) }
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

extension Campaign {
    /// Starfinder Society (2nd Edition) has no factions.
    var showsReputation: Bool { self != .starfinder2 }
}
