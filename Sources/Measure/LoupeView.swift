import SwiftUI

/// Okrągła lupa 3× z celownikiem; `center` = punkt w układzie wyświetlanego obrazu (0…1).
struct LoupeView: View {
    let image: UIImage
    let imageSize: CGSize        // rozmiar obrazu w widoku (layout.rect.size)
    let center: NormalizedPoint
    private let diameter: CGFloat = 120
    private let zoom: CGFloat = 3

    var body: some View {
        ZStack {
            Image(uiImage: image)
                .resizable()
                .frame(width: imageSize.width * zoom, height: imageSize.height * zoom)
                .offset(x: -CGFloat(center.x - 0.5) * imageSize.width * zoom,
                        y: -CGFloat(center.y - 0.5) * imageSize.height * zoom)
            Circle().fill(.red).frame(width: 6, height: 6)
            Rectangle().fill(.red.opacity(0.7)).frame(width: 24, height: 1)
            Rectangle().fill(.red.opacity(0.7)).frame(width: 1, height: 24)
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .overlay(Circle().stroke(.white, lineWidth: 2))
        .shadow(radius: 4)
    }
}
