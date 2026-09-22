import SwiftUI
import UIKit

struct DiagramPlateSheet: View {
    let diagram: WordDiagram
    let displayImageName: String
    @Environment(\.dismiss) private var dismiss
    @State private var showInfo = false

    init(diagram: WordDiagram, displayImageName: String? = nil) {
        self.diagram = diagram
        self.displayImageName = displayImageName ?? diagram.plateName
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color.black.ignoresSafeArea()

                ZoomableImageView(
                    imageName: displayImageName,
                    bottomInset: showInfo ? 180 : 0,
                    onTap: {
                        if showInfo {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showInfo = false
                            }
                        }
                    }
                )
                .ignoresSafeArea(edges: .bottom)

                if showInfo {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(diagram.title)
                                    .font(.theme(.headline, weight: .bold))
                                    .foregroundStyle(.primary)

                                Text(diagram.plateTitle)
                                    .font(.theme(.caption, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showInfo = false
                                }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.theme(.title3))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if let caption = diagram.caption {
                            Text(caption)
                                .font(.theme(.subheadline))
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 2)
                        }
                    }
                    .padding(16)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationTitle(displayImageName == diagram.plateName ? diagram.plateTitle : diagram.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Theme.canvas, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showInfo.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: showInfo ? "info.circle.fill" : "info.circle")
                            Text("Info")
                                .font(.theme(.subheadline))
                        }
                        .foregroundStyle(showInfo ? Theme.primary : .secondary)
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.theme(.body, weight: .semibold))
                }
            }
        }
    }
}

// MARK: - Pinch & Double-Tap Zoomable Scroll View

struct ZoomableImageView: UIViewRepresentable {
    let imageName: String
    var bottomInset: CGFloat = 0
    var onTap: (() -> Void)? = nil

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.maximumZoomScale = 5.0
        scrollView.minimumZoomScale = 1.0
        scrollView.bouncesZoom = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.backgroundColor = .black

        let imageView = UIImageView()
        imageView.image = UIImage(named: imageName)
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(imageView)
        context.coordinator.imageView = imageView

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            imageView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            imageView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
        ])

        let doubleTapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTapGesture.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTapGesture)

        let singleTapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSingleTap(_:)))
        singleTapGesture.numberOfTapsRequired = 1
        singleTapGesture.require(toFail: doubleTapGesture)
        scrollView.addGestureRecognizer(singleTapGesture)

        return scrollView
    }

    func updateUIView(_ uiView: UIScrollView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.currentImageName != imageName {
            context.coordinator.currentImageName = imageName
            context.coordinator.imageView?.image = UIImage(named: imageName)
            uiView.setZoomScale(1.0, animated: false)
        }
        uiView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: bottomInset, right: 0)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var parent: ZoomableImageView
        weak var imageView: UIImageView?
        var currentImageName: String?

        init(_ parent: ZoomableImageView) {
            self.parent = parent
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        @objc func handleSingleTap(_ recognizer: UITapGestureRecognizer) {
            parent.onTap?()
        }

        @objc func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard let scrollView = recognizer.view as? UIScrollView else { return }
            if scrollView.zoomScale > 1.0 {
                scrollView.setZoomScale(1.0, animated: true)
            } else {
                let point = recognizer.location(in: imageView)
                let size = scrollView.bounds.size
                let w = size.width / 2.5
                let h = size.height / 2.5
                let rect = CGRect(x: point.x - w / 2, y: point.y - h / 2, width: w, height: h)
                scrollView.zoom(to: rect, animated: true)
            }
        }
    }
}
