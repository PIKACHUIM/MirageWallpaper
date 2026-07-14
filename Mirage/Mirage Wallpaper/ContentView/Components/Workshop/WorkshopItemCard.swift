//
//  Mirage Wallpaper
//
//  Copyright © 2026 王孝慈. All rights reserved.
//

import SwiftUI

struct WorkshopItemCard: View {
    var item: WorkshopItem
    var isHovered: Bool
    var isDownloaded: Bool
    var downloadState: DownloadState?

    var body: some View {
        ZStack(alignment: .bottom) {
            ZStack(alignment: .topTrailing) {
                AsyncImage(url: item.previewImageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        Rectangle()
                            .fill(Color.secondary.opacity(0.15))
                            .overlay {
                                Image(systemName: "photo")
                                    .font(.title2)
                                    .foregroundStyle(.tertiary)
                            }
                    default:
                        Rectangle()
                            .fill(Color.secondary.opacity(0.08))
                            .overlay {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                    }
                }
                .frame(minHeight: 120)

                if let state = downloadState {
                    downloadBadge(state)
                        .padding(6)
                } else if isDownloaded {
                    HStack(spacing: 3) {
                        Image(systemName: "checkmark")
                            .font(.caption2)
                            .bold()
                        Text("已下载")
                            .font(.caption2)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.green)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .padding(6)
                }
            }

            VStack(spacing: 0) {
                LinearGradient(
                    colors: [.clear, .black.opacity(0.65)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 50)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.caption)
                            .bold()
                            .lineLimit(1)
                            .foregroundStyle(.white)

                        HStack(spacing: 6) {
                            Label(item.formattedSubscriptions, systemImage: "arrow.down.circle")
                            Label(item.formattedViews, systemImage: "eye")

                            Text(item.kind.displayName)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(kindColor.opacity(0.8))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.8))
                    }
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 6)
                .background(Color.black.opacity(0.5))
            }
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(isHovered ? 0.25 : 0.1), radius: isHovered ? 8 : 3, y: isHovered ? 4 : 1)
        .scaleEffect(isHovered ? 1.04 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isHovered)
    }

    private var kindColor: Color {
        switch item.kind {
        case .scene: return .purple
        case .web: return .orange
        case .video: return .blue
        case .unsupported: return .gray
        }
    }

    @ViewBuilder
    private func downloadBadge(_ state: DownloadState) -> some View {
        switch state {
        case .downloading(let percent):
            HStack(spacing: 4) {
                if let percent {
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.3), lineWidth: 2)
                            .frame(width: 14, height: 14)
                        Circle()
                            .trim(from: 0, to: percent)
                            .stroke(Color.white, lineWidth: 2)
                            .frame(width: 14, height: 14)
                            .rotationEffect(.degrees(-90))
                    }
                    Text("\(Int(percent * 100))%")
                        .font(.caption2)
                } else {
                    Image(systemName: "arrow.down")
                        .font(.caption2)
                    Text("连接中")
                        .font(.caption2)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.blue)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        case .queued:
            HStack(spacing: 3) {
                Image(systemName: "clock")
                    .font(.caption2)
                Text("排队中")
                    .font(.caption2)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.orange)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        case .starting, .validating:
            HStack(spacing: 3) {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 12, height: 12)
                Text("处理中")
                    .font(.caption2)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.blue)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        case .failed:
            HStack(spacing: 3) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.caption2)
                Text("失败")
                    .font(.caption2)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.red)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        case .completed:
            HStack(spacing: 3) {
                Image(systemName: "checkmark")
                    .font(.caption2)
                Text("已下载")
                    .font(.caption2)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.green)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }
}
