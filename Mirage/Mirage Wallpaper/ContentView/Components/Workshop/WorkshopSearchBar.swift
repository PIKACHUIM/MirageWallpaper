//
//  Mirage Wallpaper
//
//  Copyright © 2026 王孝慈. All rights reserved.
//

import SwiftUI

struct WorkshopSearchBar: View {
    @ObservedObject var workshopViewModel: WorkshopViewModel

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索创意工坊壁纸...", text: $workshopViewModel.searchText)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        workshopViewModel.currentPage = 1
                        workshopViewModel.search()
                    }
                if !workshopViewModel.searchText.isEmpty {
                    Button {
                        workshopViewModel.searchText = ""
                        workshopViewModel.currentPage = 1
                        workshopViewModel.search()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
            .background(Color(nsColor: NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            )

            Picker("排序", selection: Binding(
                get: { workshopViewModel.sortOrder },
                set: { newValue in
                    workshopViewModel.sortOrder = newValue
                    workshopViewModel.currentPage = 1
                    workshopViewModel.search()
                }
            )) {
                ForEach(WorkshopSortOrder.allCases) { order in
                    Text(order.label).tag(order)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 120)
        }
    }
}
