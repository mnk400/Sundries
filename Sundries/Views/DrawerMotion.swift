import SwiftUI

/// The spatial relationship between the drawer's current and next content.
enum DrawerMotion: Equatable {
    /// Content is attached directly below its trigger and reveals vertically.
    case reveal
    /// Content moves deeper into a hierarchy or to a peer on its right.
    case forward
    /// Content returns up a hierarchy or to a peer on its left.
    case backward

    static func animation(reduceMotion: Bool) -> Animation? {
        reduceMotion
            ? .easeOut(duration: 0.12)
            : .snappy(duration: 0.24, extraBounce: 0)
    }

    func transition(reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }

        switch self {
        case .reveal:
            return .asymmetric(
                insertion: .opacity.combined(with: .move(edge: .top)),
                removal: .opacity.combined(with: .move(edge: .top))
            )
        case .forward:
            return .asymmetric(
                insertion: .opacity.combined(with: .move(edge: .trailing)),
                removal: .opacity.combined(with: .move(edge: .leading))
            )
        case .backward:
            return .asymmetric(
                insertion: .opacity.combined(with: .move(edge: .leading)),
                removal: .opacity.combined(with: .move(edge: .trailing))
            )
        }
    }
}

/// Route and motion state shared by top-level drawers and nested drawer pages.
struct DrawerState<Route: Hashable> {
    var route: Route?
    private(set) var motion: DrawerMotion?

    init(route: Route? = nil) {
        self.route = route
        motion = nil
    }

    mutating func toggle(
        _ target: Route,
        replacementMotion: DrawerMotion
    ) {
        if route == target {
            dismiss()
        } else if route == nil {
            motion = .reveal
            route = target
        } else {
            motion = replacementMotion
            route = target
        }
    }

    mutating func navigate(to target: Route, motion: DrawerMotion) {
        self.motion = motion
        route = target
    }

    mutating func dismiss() {
        motion = .reveal
        route = nil
    }
}

/// Clips animated pages to one drawer surface and applies the route's motion.
struct DrawerContentHost<Route: Hashable, Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let state: DrawerState<Route>
    var dividerLeadingPadding: CGFloat?
    @ViewBuilder let content: (Route) -> Content

    var body: some View {
        VStack(spacing: 0) {
            if state.route != nil, let dividerLeadingPadding {
                Divider()
                    .padding(.leading, dividerLeadingPadding)
                    .transition(.opacity)
            }

            ZStack(alignment: .top) {
                if let route = state.route {
                    content(route)
                        .id(route)
                        .transition(transition)
                }
            }
            .clipped()
        }
    }

    private var transition: AnyTransition {
        state.motion?.transition(reduceMotion: reduceMotion) ?? .identity
    }
}
