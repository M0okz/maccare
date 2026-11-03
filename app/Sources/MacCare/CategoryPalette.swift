import SwiftUI

struct CategoryPalette {
    let base: Color
    let middle: Color
    let edge: Color
    let sidebar: Color
    let accent: Color
}

extension NavigationSection {
    var palette: CategoryPalette {
        switch self {
        case .battery:
            return .init(base: Color(hex: "10382E"), middle: Color(hex: "185B45"), edge: Color(hex: "123D34"),
                         sidebar: Color(hex: "102F29"), accent: Theme.ok)
        case .home:
            return .init(base: Color(hex: "160C2E"), middle: Color(hex: "392166"), edge: Color(hex: "21123F"),
                         sidebar: Color(hex: "211536"), accent: ModuleColor.clean)
        case .cleaning:
            return .init(base: Color(hex: "21184D"), middle: Color(hex: "413581"), edge: Color(hex: "2B225C"),
                         sidebar: Color(hex: "241C48"), accent: ModuleColor.clean)
        case .performance:
            return .init(base: Color(hex: "3D1D0D"), middle: Color(hex: "652C0C"), edge: Color(hex: "4C220C"),
                         sidebar: Color(hex: "3E230F"), accent: ModuleColor.startup)
        case .applications:
            return .init(base: Color(hex: "3B164F"), middle: Color(hex: "592472"), edge: Color(hex: "421D5D"),
                         sidebar: Color(hex: "351B46"), accent: ModuleColor.uninstall)
        case .files:
            return .init(base: Color(hex: "063940"), middle: Color(hex: "087C79"), edge: Color(hex: "064C51"),
                         sidebar: Color(hex: "063D43"), accent: FilesStyle.accent)
        case .space:
            return .init(base: Color(hex: "0D2347"), middle: Color(hex: "123E70"), edge: Color(hex: "102F58"),
                         sidebar: Color(hex: "142C4B"), accent: ModuleColor.space)
        case .tools:
            return .init(base: Color(hex: "352A0A"), middle: Color(hex: "4C3B0A"), edge: Color(hex: "40340C"),
                         sidebar: Color(hex: "332B15"), accent: ModuleColor.maint)
        }
    }
}
