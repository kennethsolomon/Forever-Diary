import SwiftUI

struct PhotoGalleryView: View {
    let photos: [PhotoAsset]
    let startIndex: Int

    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex: Int
    @State private var dragOffset: CGSize = .zero
    @State private var dragOpacity: Double = 1.0
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

            TabView(selection: $currentIndex) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                    photoPage(photo: photo)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .onChange(of: currentIndex) { _, _ in
                withAnimation(.spring(response: 0.3)) { scale = 1.0 }
            }

            overlayControls
        }
        .offset(y: dragOffset.height)
        .opacity(dragOpacity)
        .gesture(
            DragGesture()
                .onChanged { value in
                    guard value.translation.height > 0 else { return }
                    dragOffset = CGSize(width: 0, height: value.translation.height)
                    dragOpacity = max(0.0, 1.0 - Double(value.translation.height / 250))
                }
                .onEnded { value in
                    if value.translation.height > 80 {
                        dismiss()
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            dragOffset = .zero
                            dragOpacity = 1.0
                        }
                    }
                }
        )
    }

    private func photoPage(photo: PhotoAsset) -> some View {
        Group {
            if let uiImage = UIImage(data: photo.imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                let delta = value / lastScale
                                lastScale = value
                                scale = min(max(scale * delta, 1.0), 4.0)
                            }
                            .onEnded { _ in
                                lastScale = 1.0
                                if scale < 1.0 {
                                    withAnimation(.spring(response: 0.3)) { scale = 1.0 }
                                }
                            }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.spring(response: 0.3)) { scale = 1.0 }
                    }
            } else {
                Color.black
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var overlayControls: some View {
        VStack {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.15))
                        .clipShape(Circle())
                }
                .padding(.leading, 16)
                .padding(.top, 16)

                Spacer()

                Text("\(currentIndex + 1) / \(photos.count)")
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.trailing, 16)
                    .padding(.top, 16)
            }

            Spacer()

            HStack(spacing: 6) {
                ForEach(photos.indices, id: \.self) { index in
                    Circle()
                        .fill(index == currentIndex ? Color("accentBright") : Color.white.opacity(0.3))
                        .frame(width: 6, height: 6)
                        .animation(.easeInOut(duration: 0.2), value: currentIndex)
                }
            }
            .padding(.bottom, 24)
        }
    }
}
