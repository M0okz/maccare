import SwiftUI

struct HomeActivityTile<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8, content: content)
            .padding(12).frame(maxWidth: .infinity, minHeight: 126, maxHeight: .infinity, alignment: .topLeading)
            .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.06)))
            .contentShape(RoundedRectangle(cornerRadius: 10))
    }
}
