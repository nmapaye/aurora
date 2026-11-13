import SwiftUI

/// The composer's photo-logging entry point, kept in its own file so the
/// composer itself only places it.
struct DrinkPhotoButton: View {
    @Binding var isPresented: Bool

    var body: some View {
        Button { isPresented = true } label: {
            Image(systemName: "camera").font(.title3)
                .frame(width: Metrics.minimumTouchTarget, height: Metrics.minimumTouchTarget)
        }
        .accessibilityLabel("Log a drink from a photo")
        .accessibilityHint("Reads the photo on this device. You confirm before anything is saved.")
        .accessibilityShowsLargeContentViewer { Label("Log a drink from a photo", systemImage: "camera") }
        .accessibilityIdentifier("assistant-photo-log")
        .sheet(isPresented: $isPresented) { DrinkPhotoSheet() }
    }
}
