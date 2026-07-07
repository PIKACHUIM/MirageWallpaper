//
//  Mirage Wallpaper
//
//  Copyright © 2026 王孝慈. All rights reserved.
//

import SwiftUI

struct DiscoverSectionView: View {
    var title: String
    var icon: String
    var iconColor: Color
    var items: [WorkshopItem]
    @ObservedObject var workshopViewModel: WorkshopViewModel
    @ObservedObject var contentViewModel: ContentViewModel
    var onSeeAll: () -> Void

    @State private var hoveredId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(iconColor)
                    .font(.title3)
                Text(title)
                    .font(.title3)
                    .bold()
                Spacer()
                Button {
                    onSeeAll()
                } label: {
                    HStack(spacing: 4) {
                        Text("查看全部")
                        Image(systemName: "chevron.right")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(items) { item in
                        DiscoverCard(
                            item: item,
                            isHovered: hoveredId == item.id,
                            isSelected: workshopViewModel.selectedItem?.id == item.id,
                            isDownloaded: SteamWebAPI.shared.isItemDownloaded(item.publishedFileId),
                            downloadState: workshopViewModel.downloadState(for: item.publishedFileId)
                        )
                        .onHover { hovered in
                            withAnimation(.easeInOut(duration: 0.2)) {
                                hoveredId = hovered ? item.id : nil
                            }
                        }
                        .onTapGesture {
                            workshopViewModel.showCustomization = false
                            workshopViewModel.selectedItem = item
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

struct DiscoverCard: View {
    var item: WorkshopItem
    var isHovered: Bool
    var isSelected: Bool
    var isDownloaded: Bool
    var downloadState: DownloadState?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                AsyncImage(url: item.previewImageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        Rectangle()
                            .fill(Color.secondary.opacity(0.2))
                            .overlay {
                                Image(systemName: "photo")
                                    .foregroundStyle(.tertiary)
                            }
                    default:
                        Rectangle()
                            .fill(Color.secondary.opacity(0.1))
                            .overlay {
                                ProgressView()
                                    .scaleEffect(0.7)
                            }
                    }
                }
                .frame(width: 220, height: 124)
                .clipped()

                if isDownloaded {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.white, .green)
                        .symbolRenderingMode(.palette)
                        .font(.caption)
                        .padding(6)
                } else if let state = downloadState {
                    downloadStateIndicator(state)
                        .padding(6)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.caption)
                    .lineLimit(1)
                    .bold()

                HStack(spacing: 8) {
                    Label(item.formattedSubscriptions, systemImage: "arrow.down.circle")
                    Label(item.kind.displayName, systemImage: "tag")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .background(Color(nsColor: NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.accentColor, lineWidth: 2)
            }
        }
        .shadow(color: .black.opacity(isHovered ? 0.2 : 0.08), radius: isHovered ? 8 : 3)
        .scaleEffect(isHovered ? 1.03 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isHovered)
    }

    @ViewBuilder
    func downloadStateIndicator(_ state: DownloadState) -> some View {
        switch state {
        case .downloading(let percent):
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 20, height: 20)
                Circle()
                    .trim(from: 0, to: percent)
                    .stroke(Color.blue, lineWidth: 2)
                    .frame(width: 16, height: 16)
                    .rotationEffect(.degrees(-90))
            }
        case .queued, .starting:
            Image(systemName: "clock.fill")
                .foregroundStyle(.white, .orange)
                .symbolRenderingMode(.palette)
                .font(.caption)
        case .validating:
            ProgressView()
                .scaleEffect(0.5)
        default:
            EmptyView()
        }
    }
}
