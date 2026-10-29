import SwiftUI
import UIKit

/// How a screen wants the status bar and the home indicator.
struct SystemBarsLook: Equatable {
    /// Light status bar content (a dark reading theme over the app).
    var lightStatusBar = false
    /// Full screen: no status bar, the home indicator dimmed.
    var hidden = false
}

extension View {
    /// Light status bar content while `lightStatusBar` is on (a dark reading theme); no status bar
    /// and a dimmed home indicator while `hidden` is (a reading page in full screen).
    ///
    /// SwiftUI sets the status bar style only through a colour scheme for the whole window, which
    /// would flip the surface under it too. Instead, while either is on, a clear window that
    /// takes no touches and has nothing for VoiceOver sits just above the app's and answers for
    /// both bars: being on top, it is the window the system asks. When both turn off, it answers
    /// as the app's window does while the bars fade back, then goes (`SystemBarsAnchorView`).
    func systemBars(lightStatusBar: Bool, hidden: Bool) -> some View {
        let look = SystemBarsLook(lightStatusBar: lightStatusBar, hidden: hidden)
        // Zero-sized: a still render (`ImageRenderer`) draws a UIKit view as a placeholder.
        return background(alignment: .topLeading) {
            if lightStatusBar || hidden { SystemBarsAnchor(look: look).frame(width: 0, height: 0) }
        }
    }
}

private struct SystemBarsAnchor: UIViewRepresentable {
    let look: SystemBarsLook

    func makeUIView(context: Context) -> SystemBarsAnchorView {
        SystemBarsAnchorView(look: look)
    }

    func updateUIView(_ view: SystemBarsAnchorView, context: Context) {
        view.look = look
    }

    static func dismantleUIView(_ view: SystemBarsAnchorView, coordinator: ()) {
        view.release()
    }
}

/// Shows the system bars window while it is in a window, until it is released. Then the window
/// stays, with the app's look, until the bars have faded back (`lingers`): a window that goes away
/// takes its look with it at once, so the status bar would pop back. Only that long: kept for a
/// reading page's life, the window made automated runs about 35 s longer.
final class SystemBarsAnchorView: UIView {
    var look: SystemBarsLook {
        didSet { if look != oldValue { statusWindow?.controller.look = look } }
    }

    private var released = false
    private var statusWindow: SystemBarsWindow?

    init(look: SystemBarsLook) {
        self.look = look
        super.init(frame: .zero)
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

    /// How long a released window stays: the bars' fade (`SystemBarsController.look`).
    private static let lingers = Motion.standardResponse * 1.5

    private func update() {
        guard !released, let scene = window?.windowScene else { return retire() }
        if statusWindow == nil {
            statusWindow = SystemBarsWindow(windowScene: scene, look: look)
        }
        statusWindow?.isHidden = false
    }

    private func retire() {
        guard let statusWindow else { return }
        self.statusWindow = nil
        statusWindow.controller.look = SystemBarsLook()
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.lingers) { statusWindow.isHidden = true }
    }
}

/// Above the app's window; every touch falls through to it.
private final class SystemBarsWindow: UIWindow {
    let controller: SystemBarsController

    init(windowScene: UIWindowScene, look: SystemBarsLook) {
        controller = SystemBarsController(look: look)
        super.init(windowScene: windowScene)
        windowLevel = .normal + 1
        backgroundColor = .clear
        accessibilityElementsHidden = true
        rootViewController = controller
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
}

private final class SystemBarsController: UIViewController {
    var look: SystemBarsLook {
        didSet {
            UIView.animate(withDuration: Motion.standardResponse) { self.setNeedsStatusBarAppearanceUpdate() }
            setNeedsUpdateOfHomeIndicatorAutoHidden()
        }
    }

    init(look: SystemBarsLook) {
        self.look = look
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var preferredStatusBarStyle: UIStatusBarStyle { look.lightStatusBar ? .lightContent : .default }
    override var prefersStatusBarHidden: Bool { look.hidden }
    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation { .fade }
    override var prefersHomeIndicatorAutoHidden: Bool { look.hidden }

    override func loadView() {
        view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.accessibilityElementsHidden = true
    }
}
