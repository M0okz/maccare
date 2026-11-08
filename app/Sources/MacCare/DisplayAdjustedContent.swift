import SwiftUI

struct DisplayAdjustedContent: ViewModifier {
    let layout: MainWindowLayout

    func body(content: Content) -> some View {
        GeometryReader { geometry in
            let size = layout.contentSize(in: geometry.size)
            content
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .scaleEffect(layout.scale, anchor: .topLeading)
        }
        .frame(minWidth: layout.minimumWindowSize.width, minHeight: layout.minimumWindowSize.height)
        .animation(nil, value: layout)
    }
}
