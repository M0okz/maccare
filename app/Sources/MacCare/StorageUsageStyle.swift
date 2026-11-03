import SwiftUI

struct StorageUsageStyle: ProgressViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.hairline)
                Capsule().fill(LinearGradient(colors: [Theme.accent, ModuleColor.privacy], startPoint: .leading, endPoint: .trailing))
                    .frame(width: geometry.size.width * max(0, min(configuration.fractionCompleted ?? 0, 1)))
            }
        }
        .frame(height: 8)
    }
}
