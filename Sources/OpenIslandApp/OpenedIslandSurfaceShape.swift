import SwiftUI

struct OpenedIslandSurfaceShape: Shape {
    enum TopProfile: Equatable {
        case notch
        case topBar
    }

    var topProfile: TopProfile
    var bottomCornerRadius: CGFloat = NotchShape.openedBottomRadius

    var animatableData: CGFloat {
        get { bottomCornerRadius }
        set { bottomCornerRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        switch topProfile {
        case .notch:
            return NotchShape(
                topCornerRadius: NotchShape.openedTopRadius,
                bottomCornerRadius: bottomCornerRadius
            )
            .path(in: rect)
        case .topBar:
            return V6ClosedPillShape(cornerRadius: bottomCornerRadius)
                .path(in: rect)
        }
    }
}
