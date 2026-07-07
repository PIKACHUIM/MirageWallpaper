//
//  Mirage Wallpaper
//
//  Copyright © 2026 王孝慈. All rights reserved.
//

import SwiftUI

struct DiscoverBannerView: View {
    var items: [WorkshopItem]
    @ObservedObject var workshopViewModel: WorkshopViewModel
    @ObservedObject var contentViewModel: ContentViewModel

    @State private var currentIndex: Int = 0
    @State private var timer: Timer?
    @State private var isHovered = false

    var body: some View {
        ZStack(alignment: .bottom) {
            if !items.isEmpty {
                ZStack {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        BannerCard(item: item)
                            .opacity(index == currentIndex ? 1 : 0)
                            .animation(.easeInOut(duration: 0.5), value: currentIndex)
                            .onTapGesture {
                                workshopViewModel.selectedItem = item
                            }
                    }
                }

                LinearGradient(
                    colors: [.clear, .black.opacity(0.5)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .frame(height: 80)
                .allowsHitTesting(false)

                HStack(spacing: 8) {
                    ForEach(0..<items.count, id: \.self) { index in
                        Capsule()
                            .fill(index == currentIndex ? Color.white : Color.white.opacity(0.4))
                            .frame(width: index == currentIndex ? 20 : 8, height: 6)
                            .animation(.spring(response: 0.3), value: currentIndex)
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.4)) {
                                    currentIndex = index
                                }
                            }
                    }
                }
                .padding(.bottom, 12)
            }
        }
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onHover { hovered in
            isHovered = hovered
            if hovered {
                stopTimer()
            } else {
                startTimer()
            }
        }
        .onAppear { startTimer() }
        .onDisappear { stopTimer() }
    }

    private func startTimer() {
        stopTimer()
        guard items.count > 1 else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.5)) {
                currentIndex = (currentIndex + 1) % items.count
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

struct BannerCard: View {
    var item: WorkshopItem

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomLeading) {
                AsyncImage(url: item.previewImageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                    case .failure:
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [.blue.opacity(0.3), .purple.opacity(0.3)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    default:
                        Rectangle()
                            .fill(Color.secondary.opacity(0.08))
                            .overlay {
                                ProgressView()
                            }
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.title3)
                        .bold()
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .shadow(color: .black.opacity(0.6), radius: 4)

                    HStack(spacing: 12) {
                        Label(item.formattedSubscriptions, systemImage: "arrow.down.circle.fill")
                        Label(item.formattedViews, systemImage: "eye.fill")
                        Label(item.kind.displayName, systemImage: "tag.fill")
                    }
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
                    .shadow(color: .black.opacity(0.5), radius: 2)
                }
                .padding(16)
            }
        }
    }
}
