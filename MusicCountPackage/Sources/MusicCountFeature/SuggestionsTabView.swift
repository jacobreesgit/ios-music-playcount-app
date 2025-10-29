import SwiftUI

@MainActor
struct SuggestionsTabView: View {
    @Environment(SuggestionsService.self) private var suggestionsService
    @State private var selectedSuggestion: Suggestion?
    @State private var sortOption: SuggestionSortOption = .playCountDifference
    @State private var searchText = ""
    @Binding var selectedTab: Int

    private var filteredAndSortedSuggestions: [Suggestion] {
        let filtered: [Suggestion]
        if searchText.isEmpty {
            filtered = suggestionsService.activeSuggestions
        } else {
            filtered = suggestionsService.activeSuggestions.filter { suggestion in
                suggestion.sharedTitle.localizedStandardContains(searchText) ||
                suggestion.songs.contains { song in
                    song.artist.localizedStandardContains(searchText) ||
                    song.album.localizedStandardContains(searchText)
                }
            }
        }
        return sortOption.sorted(filtered)
    }

    var body: some View {
        NavigationStack {
            Group {
                if suggestionsService.activeSuggestions.isEmpty {
                    emptyStateView
                } else {
                    suggestionsList
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Picker("Sort", selection: $sortOption) {
                            ForEach(SuggestionSortOption.allCases) { option in
                                Label(option.displayName, systemImage: option.icon(isSelected: option == sortOption)).tag(option)
                            }
                        }
                    } label: {
                        Label("Sort", systemImage: "arrow.up.arrow.down")
                    }
                }
            }
        }
        .sheet(item: $selectedSuggestion) { suggestion in
            NavigationStack {
                ComparisonView(
                    song1: suggestion.lowestPlayCount,
                    song2: suggestion.highestPlayCount,
                    showingComparison: Binding(
                        get: { selectedSuggestion != nil },
                        set: { if !$0 { selectedSuggestion = nil } }
                    ),
                    selectedTab: $selectedTab
                )
            }
            .presentationDetents([.medium, .large])
        }
    }

    private var suggestionsList: some View {
        List {
            ForEach(filteredAndSortedSuggestions) { suggestion in
                Section {
                    if suggestion.canDismissIndividualSongs {
                        // 3+ songs: Individual rows with individual swipes
                        ForEach(suggestion.songs) { song in
                            Button {
                                selectedSuggestion = suggestion
                            } label: {
                                SongRowView(song: song, selectionSlot: nil)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    withAnimation(.easeOut) {
                                        suggestionsService.dismissSong(
                                            title: suggestion.sharedTitle,
                                            artist: suggestion.sharedArtist,
                                            songId: song.id
                                        )
                                    }
                                } label: {
                                    Label("Dismiss", systemImage: "xmark.circle")
                                }
                            }
                        }
                    } else {
                        // 2 songs: Single container with all songs, entire thing is swipeable
                        SuggestionGroupContainer(
                            suggestion: suggestion,
                            onTap: {
                                selectedSuggestion = suggestion
                            }
                        )
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                withAnimation(.easeOut) {
                                    suggestionsService.dismissEntireGroup(
                                        title: suggestion.sharedTitle,
                                        artist: suggestion.sharedArtist
                                    )
                                }
                            } label: {
                                Label("Dismiss All", systemImage: "xmark.circle.fill")
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text(suggestion.sharedTitle)
                            .font(.headline)
                            .textCase(nil)
                        Spacer()
                        Text(suggestion.versionCount)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
        .contentMargins(.top, 0, for: .scrollContent)
        .searchable(text: $searchText, placement: .automatic, prompt: "Search suggestions")
    }

    private var emptyStateView: some View {
        ContentUnavailableView(
            "No Suggestions",
            systemImage: "lightbulb.slash",
            description: Text(suggestionsService.allSuggestions.isEmpty
                ? "No duplicate songs found"
                : "All suggestions reviewed")
        )
    }
}

// MARK: - Suggestion Group Container

/// Container view that wraps multiple song rows into a single swipeable unit for 2-song groups
private struct SuggestionGroupContainer: View {
    let suggestion: Suggestion
    let onTap: () -> Void

    var body: some View {
        Button {
            onTap()
        } label: {
            VStack(spacing: 0) {
                ForEach(suggestion.songs) { song in
                    SongRowView(song: song, selectionSlot: nil)

                    // Add divider between songs (but not after last one)
                    if song.id != suggestion.songs.last?.id {
                        Divider()
                            .padding(.leading, 62) // Align with text, not artwork
                    }
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Suggestion Sort Options

enum SuggestionSortOption: String, CaseIterable, Identifiable, Sendable {
    case playCountDifference = "playCountDifference"
    case titleAscending = "titleAscending"
    case titleDescending = "titleDescending"
    case artistAscending = "artistAscending"
    case artistDescending = "artistDescending"
    case versionCountDescending = "versionCountDescending"
    case versionCountAscending = "versionCountAscending"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .playCountDifference:
            return "Play Count Difference"
        case .titleAscending, .titleDescending:
            return "Title"
        case .artistAscending, .artistDescending:
            return "Artist"
        case .versionCountDescending, .versionCountAscending:
            return "Version Count"
        }
    }

    func sorted(_ suggestions: [Suggestion]) -> [Suggestion] {
        switch self {
        case .playCountDifference:
            return suggestions.sorted { $0.playCountDifference > $1.playCountDifference }
        case .titleAscending:
            return suggestions.sorted { $0.sharedTitle.localizedStandardCompare($1.sharedTitle) == .orderedAscending }
        case .titleDescending:
            return suggestions.sorted { $0.sharedTitle.localizedStandardCompare($1.sharedTitle) == .orderedDescending }
        case .artistAscending:
            return suggestions.sorted { $0.sharedArtist.localizedStandardCompare($1.sharedArtist) == .orderedAscending }
        case .artistDescending:
            return suggestions.sorted { $0.sharedArtist.localizedStandardCompare($1.sharedArtist) == .orderedDescending }
        case .versionCountDescending:
            return suggestions.sorted { $0.songs.count > $1.songs.count }
        case .versionCountAscending:
            return suggestions.sorted { $0.songs.count < $1.songs.count }
        }
    }

    func icon(isSelected: Bool) -> String {
        let suffix = isSelected ? ".fill" : ""
        switch self {
        case .playCountDifference, .versionCountDescending, .titleDescending, .artistDescending:
            return "arrow.down.circle\(suffix)"
        case .titleAscending, .artistAscending, .versionCountAscending:
            return "arrow.up.circle\(suffix)"
        }
    }
}
