import SwiftUI
import AppKit

struct MacPhotoGalleryView: View {
    let photos: [PhotoAsset]
    let startIndex: Int

    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex: Int
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0

    init(photos: [PhotoAsset], startIndex: Int) {
        self.photos = photos
        self.startIndex = startIndex
        _currentIndex = State(initialValue: startIndex)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Photo display
            if !photos.isEmpty {
                photoPage(for: photos[currentIndex])
                    .id(currentIndex)
            }

            // Controls overlay
            VStack {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(Color.white.opacity(0.15))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 20)
                    .padding(.top, 20)

                    Spacer()

                    Text("\(currentIndex + 1) / \(photos.count)")
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.trailing, 20)
                        .padding(.top, 20)
                }

                Spacer()

                // Navigation row
                HStack(spacing: 20) {
                    Button {
                        if currentIndex > 0 {
                            currentIndex -= 1
                            scale = 1.0
                            lastScale = 1.0
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(currentIndex > 0 ? .white : Color.white.opacity(0.2))
                            .frame(width: 40, height: 40)
                            .background(Color.white.opacity(currentIndex > 0 ? 0.15 : 0.05))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(currentIndex <= 0)

                    // Indicator dots
                    if photos.count > 1 {
                        HStack(spacing: 6) {
                            ForEach(photos.indices, id: \.self) { i in
                                Circle()
                                    .fill(i == currentIndex ? Color("accentBright") : Color.white.opacity(0.3))
                                    .frame(width: 6, height: 6)
                            }
                        }
                    }

                    Button {
                        if currentIndex < photos.count - 1 {
                            currentIndex += 1
                            scale = 1.0
                            lastScale = 1.0
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(currentIndex < photos.count - 1 ? .white : Color.white.opacity(0.2))
                            .frame(width: 40, height: 40)
                            .background(Color.white.opacity(currentIndex < photos.count - 1 ? 0.15 : 0.05))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(currentIndex >= photos.count - 1)
                }
                .padding(.bottom, 24)
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .onKeyPress(.leftArrow) {
            if currentIndex > 0 { currentIndex -= 1; scale = 1.0; lastScale = 1.0 }
            return .handled
        }
        .onKeyPress(.rightArrow) {
            if currentIndex < photos.count - 1 { currentIndex += 1; scale = 1.0; lastScale = 1.0 }
            return .handled
        }
    }

    private func photoPage(for photo: PhotoAsset) -> some View {
        let img = NSImage(data: photo.imageData)

        return Group {
            if let img {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                scale = min(max(lastScale * value, 1.0), 4.0)
                            }
                            .onEnded { _ in
                                lastScale = scale
                            }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            scale = 1.0
                            lastScale = 1.0
                        }
                    }
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.white.opacity(0.4))
            }
        }
    }
}
