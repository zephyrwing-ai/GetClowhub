import SwiftUI
import AppKit

struct CursorDotConfiguration {
    var dotSize: CGFloat = 5
    var ringSize: CGFloat = 20
    var smoothing: CGFloat = 0.18
    var dotColor: Color = .white
    var ringColor: Color = .white.opacity(0.74)
}

struct CursorDotOverlay: View {
    static let coordinateSpaceName = "CursorDotOverlayCoordinateSpace"

    let isEnabled: Bool
    let configuration: CursorDotConfiguration
    let disabledFrames: [CGRect]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var effectiveEnabled: Bool {
        isEnabled && !reduceMotion
    }

    var body: some View {
        CursorDotTrackingView(
            isEnabled: effectiveEnabled,
            configuration: configuration,
            disabledFrames: disabledFrames
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct CursorDotOverlayModifier: ViewModifier {
    let isEnabled: Bool
    let configuration: CursorDotConfiguration

    @State private var disabledFrames: [CGRect] = []

    func body(content: Content) -> some View {
        content
            .coordinateSpace(name: CursorDotOverlay.coordinateSpaceName)
            .onPreferenceChange(CursorDotDisabledPreferenceKey.self) { frames in
                disabledFrames = frames
            }
            .overlay {
                CursorDotOverlay(
                    isEnabled: isEnabled,
                    configuration: configuration,
                    disabledFrames: disabledFrames
                )
            }
    }
}

extension View {
    func cursorDotOverlay(
        isEnabled: Bool = true,
        configuration: CursorDotConfiguration = CursorDotConfiguration()
    ) -> some View {
        modifier(CursorDotOverlayModifier(isEnabled: isEnabled, configuration: configuration))
    }

    func cursorDotDisabledRegion() -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: CursorDotDisabledPreferenceKey.self,
                    value: [proxy.frame(in: .named(CursorDotOverlay.coordinateSpaceName))]
                )
            }
        )
    }
}

private struct CursorDotDisabledPreferenceKey: PreferenceKey {
    static var defaultValue: [CGRect] = []

    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) {
        value.append(contentsOf: nextValue())
    }
}

private struct CursorDotTrackingView: NSViewRepresentable {
    let isEnabled: Bool
    let configuration: CursorDotConfiguration
    let disabledFrames: [CGRect]

    func makeNSView(context: Context) -> CursorDotTrackingNSView {
        let view = CursorDotTrackingNSView()
        view.configuration = configuration
        view.isEffectEnabled = isEnabled
        view.disabledFrames = disabledFrames
        return view
    }

    func updateNSView(_ nsView: CursorDotTrackingNSView, context: Context) {
        nsView.configuration = configuration
        nsView.disabledFrames = disabledFrames
        nsView.isEffectEnabled = isEnabled
    }
}

private final class CursorDotTrackingNSView: NSView {
    private enum Metrics {
        static let frameInterval: TimeInterval = 1.0 / 60.0
        static let ringSnapDistance: CGFloat = 0.5
    }

    var configuration = CursorDotConfiguration() {
        didSet {
            applyConfiguration()
        }
    }
    var disabledFrames: [CGRect] = []
    var isEffectEnabled = true {
        didSet {
            if !isEffectEnabled {
                hideCursorLayers()
                setSystemCursorHidden(false)
            }
        }
    }

    private let dotLayer = CAShapeLayer()
    private let ringLayer = CAShapeLayer()
    private var trackingArea: NSTrackingArea?
    private var isSystemCursorHidden = false
    private var windowObservers: [NSObjectProtocol] = []
    private var animationTimer: Timer?
    private var targetPointerLocation: CGPoint?
    private var ringLocation: CGPoint?

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupLayers()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayers()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let options: NSTrackingArea.Options = [
            .activeInKeyWindow,
            .inVisibleRect,
            .mouseEnteredAndExited,
            .mouseMoved
        ]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func mouseEntered(with event: NSEvent) {
        updatePointer(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        updatePointer(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        hideCursorLayers()
        setSystemCursorHidden(false)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            removeWindowObservers()
            setSystemCursorHidden(false)
            hideCursorLayers()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        installWindowObservers()
    }

    deinit {
        removeWindowObservers()
        stopRingAnimation()
        setSystemCursorHidden(false)
    }

    private func setupLayers() {
        wantsLayer = true
        layer?.masksToBounds = false
        dotLayer.isHidden = true
        ringLayer.isHidden = true
        dotLayer.actions = disabledLayerActions
        ringLayer.actions = disabledLayerActions
        layer?.addSublayer(ringLayer)
        layer?.addSublayer(dotLayer)
        applyConfiguration()
    }

    private var disabledLayerActions: [String: NSNull] {
        [
            "bounds": NSNull(),
            "position": NSNull(),
            "path": NSNull(),
            "hidden": NSNull(),
            "opacity": NSNull(),
            "backgroundColor": NSNull(),
            "fillColor": NSNull(),
            "strokeColor": NSNull()
        ]
    }

    private func applyConfiguration() {
        dotLayer.bounds = CGRect(origin: .zero, size: CGSize(width: configuration.dotSize, height: configuration.dotSize))
        dotLayer.path = CGPath(ellipseIn: dotLayer.bounds, transform: nil)
        dotLayer.fillColor = NSColor(configuration.dotColor).cgColor

        ringLayer.bounds = CGRect(origin: .zero, size: CGSize(width: configuration.ringSize, height: configuration.ringSize))
        ringLayer.path = CGPath(ellipseIn: ringLayer.bounds, transform: nil)
        ringLayer.fillColor = NSColor.clear.cgColor
        ringLayer.strokeColor = NSColor(configuration.ringColor).cgColor
        ringLayer.lineWidth = 1
    }

    private func updatePointer(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let inside = bounds.contains(point)

        guard isEffectEnabled, inside else {
            hideCursorLayers()
            setSystemCursorHidden(false)
            return
        }

        if isDisabledRegion(at: point) {
            hideCursorLayers()
            setSystemCursorHidden(false)
            return
        }

        showCursorLayers(at: point)
        setSystemCursorHidden(true)
    }

    private func showCursorLayers(at point: CGPoint) {
        targetPointerLocation = point
        if ringLocation == nil {
            ringLocation = point
            ringLayer.position = point
        }

        dotLayer.position = point
        dotLayer.isHidden = false
        ringLayer.isHidden = false
        startRingAnimationIfNeeded()
    }

    private func hideCursorLayers() {
        targetPointerLocation = nil
        ringLocation = nil
        dotLayer.isHidden = true
        ringLayer.isHidden = true
        stopRingAnimation()
    }

    private func startRingAnimationIfNeeded() {
        guard animationTimer == nil,
              let targetPointerLocation,
              let ringLocation,
              distance(from: ringLocation, to: targetPointerLocation) > Metrics.ringSnapDistance else {
            return
        }

        animationTimer = Timer.scheduledTimer(withTimeInterval: Metrics.frameInterval, repeats: true) { [weak self] _ in
            self?.advanceRing()
        }
    }

    private func stopRingAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    private func advanceRing() {
        guard let targetPointerLocation,
              let currentRing = ringLocation else {
            stopRingAnimation()
            return
        }

        let nextRing = CGPoint(
            x: currentRing.x + (targetPointerLocation.x - currentRing.x) * configuration.smoothing,
            y: currentRing.y + (targetPointerLocation.y - currentRing.y) * configuration.smoothing
        )

        if distance(from: nextRing, to: targetPointerLocation) <= Metrics.ringSnapDistance {
            ringLocation = targetPointerLocation
            ringLayer.position = targetPointerLocation
            stopRingAnimation()
        } else {
            ringLocation = nextRing
            ringLayer.position = nextRing
        }
    }

    private func distance(from lhs: CGPoint, to rhs: CGPoint) -> CGFloat {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }

    private func isDisabledRegion(at point: CGPoint) -> Bool {
        disabledFrames.contains { $0.insetBy(dx: -2, dy: -2).contains(point) }
    }

    private func setSystemCursorHidden(_ hidden: Bool) {
        guard hidden != isSystemCursorHidden else { return }

        if hidden {
            NSCursor.hide()
        } else {
            NSCursor.unhide()
        }
        isSystemCursorHidden = hidden
    }

    private func installWindowObservers() {
        removeWindowObservers()
        guard let window else { return }

        let center = NotificationCenter.default
        windowObservers.append(
            center.addObserver(
                forName: NSWindow.didResignKeyNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.hideCursorLayers()
                self?.setSystemCursorHidden(false)
            }
        )
        windowObservers.append(
            center.addObserver(
                forName: NSWindow.didMiniaturizeNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.hideCursorLayers()
                self?.setSystemCursorHidden(false)
            }
        )
    }

    private func removeWindowObservers() {
        for observer in windowObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        windowObservers.removeAll()
    }
}
