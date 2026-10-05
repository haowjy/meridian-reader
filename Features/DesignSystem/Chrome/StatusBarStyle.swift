import SwiftUI
import UIKit

extension View {
    /// Light status bar content while `light` is on (the player sheet, dark in both appearances).
    ///
    /// SwiftUI sets the status bar only through a colour scheme for the whole window, which would
    /// flip the surface under the sheet too. Instead, while it's on, a clear window that takes no
    /// touches and has nothing for VoiceOver sits just above the app's and asks for the style.
    func lightStatusBar(_ light: Bool) -> some View {
        // Zero-sized: a still render (`ImageRenderer`) draws a UIKit view as a placeholder.
        background(alignment: .topLeading) {
            if light { StatusBarStyleAnchor().frame(width: 0, height: 0) }
        }
    }
}

private struct StatusBarStyleAnchor: UIViewRepresentable {
    func makeUIView(context: Context) -> StatusBarAnchorView {
        StatusBarAnchorView()
    }

    func updateUIView(_ view: StatusBarAnchorView, context: Context) {}

    static func dismantleUIView(_ view: StatusBarAnchorView, coordinator: ()) {
        view.release()
    }
}

/// Shows the status bar window while it is in a window, until it is released.
final class StatusBarAnchorView: UIView {
    private var released = false
    private var statusWindow: LightStatusBarWindow?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        update()
    }

    func release() {
        released = true
        update()
    }

    private func update() {
        guard !released, let scene = window?.windowScene else {
            statusWindow?.isHidden = true
            statusWindow = nil
            return
        }
        if statusWindow == nil {
            statusWindow = LightStatusBarWindow(windowScene: scene)
        }
        statusWindow?.isHidden = false
    }
}

/// Above the app's window; every touch falls through to it.
private final class LightStatusBarWindow: UIWindow {
    override init(windowScene: UIWindowScene) {
        super.init(windowScene: windowScene)
        windowLevel = .normal + 1
        backgroundColor = .clear
        accessibilityElementsHidden = true
        rootViewController = LightStatusBarController()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
}

private final class LightStatusBarController: UIViewController {
    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func loadView() {
        view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.accessibilityElementsHidden = true
    }
}
