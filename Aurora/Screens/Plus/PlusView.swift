import SwiftUI

/// The Aurora Plus screen: what it includes, the price from the App Store,
/// Buy, and Restore. Shown from Settings and when a locked range is chosen.
struct PlusView: View {
    @Environment(PurchaseService.self) private var purchases
    @Environment(\.dismiss) private var dismiss
    /// True when shown as its own sheet, so it gets a Close button.
    var showsClose = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.lg) {
                VStack(alignment: .leading, spacing: Metrics.xs) {
                    Text("Aurora Plus")
                        .font(.largeTitle.bold())
                        .foregroundStyle(Palette.textPrimary)
                    Text("One purchase. No subscription.")
                        .font(.headline)
                        .foregroundStyle(Palette.textSecondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)

                Card {
                    ForEach(PlusAccess.included, id: \.title) { item in
                        HStack(alignment: .top, spacing: Metrics.sm) {
                            Image(systemName: item.symbol)
                                .font(.title3)
                                .foregroundStyle(Palette.tint)
                                .frame(width: 28)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title).font(.headline).foregroundStyle(Palette.textPrimary)
                                Text(item.detail)
                                    .font(.subheadline)
                                    .foregroundStyle(Palette.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }

                actions

                if let notice = purchases.notice {
                    Text(notice.text)
                        .font(.footnote)
                        .foregroundStyle(notice.isError ? StatusTone.error.foreground : Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("plus-notice")
                }

                Text("Payment is charged to your Apple Account. Plus stays unlocked on every iPhone and iPad signed in to the same Apple Account, including after reinstalling.")
                    .font(.caption)
                    .foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Metrics.lg)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.modalBackground)
        .navigationTitle("Aurora Plus")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsClose {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .task {
            if purchases.productState == .unavailable && !purchases.isUnlocked {
                await purchases.loadProduct()
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        if purchases.isUnlocked {
            Label("Aurora Plus is unlocked. Thank you.", systemImage: "checkmark.seal.fill")
                .font(.headline)
                .foregroundStyle(Palette.tint)
                .accessibilityIdentifier("plus-unlocked")
        } else {
            VStack(spacing: Metrics.sm) {
                Button {
                    Task { await purchases.purchase() }
                } label: {
                    Group {
                        if purchases.isWorking {
                            ProgressView()
                        } else if let product = purchases.product {
                            Text("Unlock for \(product.displayPrice)")
                        } else if purchases.productState == .loading {
                            Text("Loading price…")
                        } else {
                            Text("Unavailable right now")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.auroraPrimary)
                .disabled(purchases.product == nil || purchases.isWorking)
                .accessibilityIdentifier("plus-buy")

                Button("Restore Purchase") {
                    Task { await purchases.restore() }
                }
                .buttonStyle(.auroraSecondary)
                .disabled(purchases.isWorking)
                .accessibilityIdentifier("plus-restore")

                if purchases.productState == .unavailable {
                    Button("Try Again") {
                        Task { await purchases.loadProduct() }
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }
        }
    }
}

/// A short line under a range control when the longer ranges need Plus.
struct PlusRangeHint: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Two-week and month views come with Aurora Plus.", systemImage: "lock.fill")
                .font(.footnote)
                .foregroundStyle(Palette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows Aurora Plus")
        .accessibilityIdentifier("plus-range-hint")
    }
}
