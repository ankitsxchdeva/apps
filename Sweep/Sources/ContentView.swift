import SwiftUI
import UIKit
import DesignSystem

struct ContentView: View {
    @State private var model = DeckModel()
    @State private var showingAlbums = false
    @State private var showingQueue = false
    @State private var showingSettings = false

    var body: some View {
        Group {
            switch model.access {
            case .unknown:
                Color.clear
            case .denied:
                deniedView
            case .granted:
                deckScreen
            }
        }
        .dsScreen()
        .task { await model.start() }
        .sheet(isPresented: $showingAlbums) {
            AlbumPickerView(model: model)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingQueue) {
            QueueReviewView(model: model)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(model: model)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .overlay {
            ZStack { freedOverlay }
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: model.freedMoment)
        }
        .onAppear(perform: applyScreenOverride)
    }

    // MARK: - Main screen

    private var deckScreen: some View {
        VStack(spacing: DSSpace.m) {
            topBar
            ZStack {
                if model.isLoading {
                    ProgressView()
                        .tint(Color.dsInkSecondary)
                } else if model.deck.isEmpty {
                    emptyDeck
                } else {
                    SwipeDeckView(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if !model.deck.isEmpty || model.canUndo {
                progressRow
            }
            if !model.queued.isEmpty {
                queueChip
            }
        }
        .padding(DSSpace.l)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: model.queued.isEmpty)
    }

    private var topBar: some View {
        HStack {
            Button {
                Haptics.tap()
                showingAlbums = true
            } label: {
                HStack(spacing: DSSpace.xs + 2) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 13, weight: .semibold))
                    Text(model.selectionLabel)
                        .font(.dsCaption)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.dsInkSecondary)
                }
                .foregroundStyle(Color.dsInk)
                .padding(.horizontal, DSSpace.m)
                .padding(.vertical, DSSpace.s + 2)
                .background(Color.dsSurface, in: Capsule())
                .overlay { Capsule().strokeBorder(Color.dsSeparator, lineWidth: 1) }
            }
            .frame(minHeight: 44)

            Spacer()

            Button {
                Haptics.tap()
                showingSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.dsInk)
                    .frame(width: 40, height: 40)
                    .background(Color.dsSurface, in: Circle())
                    .overlay { Circle().strokeBorder(Color.dsSeparator, lineWidth: 1) }
            }
            .frame(minWidth: 44, minHeight: 44)
        }
    }

    private var progressRow: some View {
        VStack(spacing: DSSpace.s) {
            ProgressLine(fraction: model.progressFraction)
            HStack {
                Button {
                    Haptics.tap()
                    model.undo()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.dsInk)
                        .frame(width: 40, height: 40)
                        .background(Color.dsSurface, in: Circle())
                        .overlay { Circle().strokeBorder(Color.dsSeparator, lineWidth: 1) }
                }
                .frame(minWidth: 44, minHeight: 44)
                .disabled(!model.canUndo)
                .opacity(model.canUndo ? 1 : 0.35)

                Spacer()
                Text(model.progressLabel)
                    .font(.dsCaption)
                    .foregroundStyle(Color.dsInkSecondary)
                    .monospacedDigit()
                Spacer()
                Color.clear
                    .frame(width: 44, height: 44)
            }
        }
    }

    private var queueChip: some View {
        Button {
            Haptics.tap()
            if model.reviewBeforeDelete {
                showingQueue = true
            } else {
                Task { await model.deleteQueued() }
            }
        } label: {
            HStack(spacing: DSSpace.s) {
                Image(systemName: "trash")
                    .font(.system(size: 13, weight: .semibold))
                Text(model.queueLabel)
                    .font(.dsCaption)
            }
            .foregroundStyle(Color.dsLetGo)
            .padding(.horizontal, DSSpace.m)
            .padding(.vertical, DSSpace.s + 2)
            .background(Color.dsLetGo.opacity(0.12), in: Capsule())
        }
        .frame(minHeight: 44)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var emptyDeck: some View {
        VStack(spacing: DSSpace.l) {
            if model.selectedAlbumIDs.isEmpty {
                EmptyStateView(
                    systemImage: "rectangle.stack.badge.plus",
                    title: "No albums selected",
                    message: "Pick the albums you want to sweep through."
                )
                Button("Choose albums") {
                    Haptics.tap()
                    showingAlbums = true
                }
                .buttonStyle(PillButtonStyle())
            } else {
                if model.lifetimeFreedBytes > 0 {
                    VStack(spacing: DSSpace.xs) {
                        Text("~" + model.formatBytes(model.lifetimeFreedBytes))
                            .font(.dsDisplay)
                            .foregroundStyle(Color.dsInk)
                        Text("freed so far")
                            .font(.dsCaption)
                            .foregroundStyle(Color.dsInkSecondary)
                    }
                }
                EmptyStateView(
                    systemImage: "sparkles",
                    title: "All swept",
                    message: "Nothing left to decide in these albums."
                )
                Button("Choose more albums") {
                    Haptics.tap()
                    showingAlbums = true
                }
                .buttonStyle(PillButtonStyle())
            }
        }
        .padding(.horizontal, DSSpace.l)
    }

    // MARK: - Denied

    private var deniedView: some View {
        VStack(spacing: DSSpace.l) {
            Spacer()
            EmptyStateView(
                systemImage: "photo.on.rectangle.angled",
                title: "Sweep can't see your photos",
                message: "Photo access is off. Turn it on in Settings to start sweeping."
            )
            Spacer()
            Button("Open Settings") {
                Haptics.tap()
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(PillButtonStyle())
        }
        .padding(DSSpace.l)
    }

    // MARK: - Freed moment

    @ViewBuilder
    private var freedOverlay: some View {
        if let freed = model.freedMoment {
            VStack(spacing: DSSpace.s) {
                Image(systemName: "sparkles")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(Color.dsStreak)
                Text("Freed ~" + model.formatBytes(freed))
                    .font(.dsTitle)
                    .foregroundStyle(Color.dsInk)
            }
            .padding(DSSpace.xl)
            .dsCard()
            .transition(.scale(scale: 0.85).combined(with: .opacity))
            .task {
                try? await Task.sleep(for: .seconds(2.2))
                model.clearFreedMoment()
            }
        }
    }

    // MARK: - Screenshot scaffolding (DEBUG only)

    private func applyScreenOverride() {
        #if DEBUG
        switch ProcessInfo.processInfo.environment["SWEEP_SCREEN"] {
        case "albums":
            showingAlbums = true
        case "settings":
            showingSettings = true
        case "queue":
            Task {
                await model.debugQueueFirstAssets()
                showingQueue = true
            }
        case "queued":
            Task { await model.debugQueueFirstAssets() }
        case "delete":
            Task {
                await model.debugQueueFirstAssets()
                await model.deleteQueued()
            }
        default:
            break
        }
        #endif
    }
}

#Preview {
    ContentView().dsTheme(.sweep)
}
