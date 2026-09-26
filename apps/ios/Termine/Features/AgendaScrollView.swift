import SwiftUI
import UIKit

/// Public gesture APIs arbitrate before either scroll view starts moving.
/// Recognizing this gate vetoes its dependent scroll view for the whole touch.
private final class AxisVeto: UIGestureRecognizer {
  let rejectedAxis: AgendaAxisLock.Axis
  var finished: (() -> Void)?
  private var origin: CGPoint?
  private var lock = AgendaAxisLock()
  init(rejecting axis: AgendaAxisLock.Axis) {
    rejectedAxis = axis
    super.init(target: nil, action: nil)
    cancelsTouchesInView = false
  }
  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
    origin = touches.first?.location(in: view)
  }
  override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
    guard state == .possible, let origin, let point = touches.first?.location(in: view),
      let axis = lock.update(x: point.x - origin.x, y: point.y - origin.y)
    else { return }
    state = axis == rejectedAxis ? .began : .failed
  }
  override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
    state = state == .possible ? .failed : .ended
    finished?()
  }
  override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
    state = .cancelled
    finished?()
  }
  override func reset() {
    super.reset()
    origin = nil
    lock.reset()
  }
  override func canPrevent(_ other: UIGestureRecognizer) -> Bool { false }
  override func canBePrevented(by other: UIGestureRecognizer) -> Bool { false }
}

/// One vertical offset and one fixed gutter for three finger-driven day pages.
/// UIKit owns the offset. Only explicit navigation or a scale change moves it.
struct AgendaScrollView: UIViewControllerRepresentable {
  let date: Date
  let projection: ReadableAgendaLayout
  let pages: (Double, Double) -> [AnyView]
  let gutter: AnyView
  let showsTimeline: Bool
  let dataReady: Bool
  let initialMinute: Double
  let reset: Int
  let selectDate: (Date) -> Void

  func makeUIViewController(context: Context) -> Controller { Controller() }
  func updateUIViewController(_ controller: Controller, context: Context) {
    controller.receive(self)
  }

  final class Controller: UIViewController, UIScrollViewDelegate {
    private let vertical = UIScrollView()
    private let horizontal = UIScrollView()
    private var hosts: [UIHostingController<AnyView>] = []
    private let timeHost = UIHostingController(rootView: AnyView(EmptyView()))
    private var current: AgendaScrollView?
    private var pending: AgendaScrollView?
    private var lastSize = CGSize.zero
    private var applying = false
    private var previousReset = -1
    private var awaitingDate: Date?
    private let verticalVeto = AxisVeto(rejecting: .horizontal)
    private let nestedScrolls = NSHashTable<UIScrollView>.weakObjects()
    private var settlementTask: Task<Void, Never>?

    private var busy: Bool {
      vertical.isTracking || vertical.isDragging || vertical.isDecelerating || horizontal.isTracking
        || horizontal.isDragging || horizontal.isDecelerating
        || nestedScrolls.allObjects.contains { $0.isTracking || $0.isDragging || $0.isDecelerating }
    }
    override func viewDidLoad() {
      super.viewDidLoad()
      vertical.delegate = self
      horizontal.delegate = self
      vertical.contentInsetAdjustmentBehavior = .never
      horizontal.contentInsetAdjustmentBehavior = .never
      horizontal.isPagingEnabled = true
      horizontal.showsHorizontalScrollIndicator = false
      horizontal.alwaysBounceHorizontal = true
      vertical.alwaysBounceVertical = false
      vertical.accessibilityIdentifier = "day-timeline"
      horizontal.accessibilityIdentifier = "agenda-days"
      view.addSubview(vertical)
      vertical.addSubview(horizontal)
      addChild(timeHost)
      vertical.addSubview(timeHost.view)
      timeHost.didMove(toParent: self)
      timeHost.view.backgroundColor = .clear
      for _ in 0..<3 {
        let host = UIHostingController(rootView: AnyView(EmptyView()))
        addChild(host)
        horizontal.addSubview(host.view)
        host.didMove(toParent: self)
        host.view.backgroundColor = .clear
        hosts.append(host)
      }
      let horizontalVeto = AxisVeto(rejecting: .vertical)
      view.addGestureRecognizer(horizontalVeto)
      view.addGestureRecognizer(verticalVeto)
      horizontalVeto.finished = { [weak self] in self?.drainAfterTouch() }
      verticalVeto.finished = { [weak self] in self?.drainAfterTouch() }
      horizontal.panGestureRecognizer.require(toFail: horizontalVeto)
      vertical.panGestureRecognizer.require(toFail: verticalVeto)
    }
    func receive(_ value: AgendaScrollView) {
      loadViewIfNeeded()
      pending = value
      if !busy { applyPending() } else { observeSettlement() }
    }
    override func viewDidLayoutSubviews() {
      super.viewDidLayoutSubviews()
      if view.bounds.size != lastSize, !busy { applyPending() }
      for host in hosts { gateNestedScrolls(in: host.view) }
    }
    private func applyPending() {
      guard !applying, let value = pending ?? current, view.bounds.width > 0 else { return }
      applying = true
      defer { applying = false }
      let old = current
      let sizeChanged = view.bounds.size != lastSize
      let scaleChanged = old?.projection.pointsPerHour != value.projection.pointsPerHour
      let jump = value.dataReady && value.reset != previousReset
      let oldY = vertical.contentOffset.y
      let anchor = old?.projection.minute(at: oldY) ?? value.initialMinute
      if value.dataReady { previousReset = value.reset }
      if let old, old.date != value.date {
        let delta = Calendar.current.dateComponents([.day], from: old.date, to: value.date).day
        // Move the already visible neighbour into the centre, preserving its host.
        if delta == 1 { hosts.append(hosts.removeFirst()) }
        if delta == -1 { hosts.insert(hosts.removeLast(), at: 0) }
      }
      current = value
      pending = nil
      awaitingDate = nil
      lastSize = view.bounds.size
      vertical.frame = view.bounds
      let height = max(view.bounds.height, value.projection.height + 52)
      let gutterWidth: CGFloat = 56
      timeHost.rootView = value.gutter
      timeHost.view.isHidden = !value.showsTimeline
      timeHost.view.frame = CGRect(x: 0, y: 0, width: gutterWidth, height: height)
      horizontal.frame = CGRect(
        x: gutterWidth, y: 0, width: view.bounds.width - gutterWidth, height: height)
      horizontal.contentSize = CGSize(width: horizontal.bounds.width * 3, height: height)
      vertical.contentSize = CGSize(width: view.bounds.width, height: height)
      let requestedY =
        jump
        ? value.projection.y(value.initialMinute)
        : scaleChanged ? value.projection.y(anchor) : oldY
      let y = min(max(0, requestedY), max(0, height - view.bounds.height))
      let pages = value.pages(view.bounds.height, y)
      for (index, host) in hosts.enumerated() {
        let pageDate = Calendar.current.date(byAdding: .day, value: index - 1, to: value.date)!
        host.rootView = AnyView(
          pages[index].id(pageDate).frame(
            maxWidth: .infinity, maxHeight: .infinity, alignment: .top))
        host.view.frame = CGRect(
          x: CGFloat(index) * horizontal.bounds.width, y: 0,
          width: horizontal.bounds.width, height: height)
      }
      if old == nil || old?.date != value.date || sizeChanged || jump {
        horizontal.contentOffset = CGPoint(x: horizontal.bounds.width, y: 0)
      }
      if jump || scaleChanged || sizeChanged {
        vertical.contentOffset = CGPoint(x: 0, y: y)
      }
      vertical.isScrollEnabled = value.showsTimeline
      for host in hosts {
        host.view.layoutIfNeeded()
        gateNestedScrolls(in: host.view)
      }
    }
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
      if !decelerate { settle() }
    }
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { settle() }
    private func drainAfterTouch() {
      // UIKit updates tracking flags after the recognizer's terminal callback.
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        if self.busy { self.observeSettlement() } else { self.settle() }
      }
    }
    private func gateNestedScrolls(in view: UIView) {
      if let scroll = view as? UIScrollView, !nestedScrolls.contains(scroll) {
        scroll.panGestureRecognizer.require(toFail: verticalVeto)
        nestedScrolls.add(scroll)
      }
      for child in view.subviews { gateNestedScrolls(in: child) }
    }
    private func observeSettlement() {
      guard settlementTask == nil else { return }
      settlementTask = Task { @MainActor [weak self] in
        while !Task.isCancelled {
          try? await Task.sleep(for: .milliseconds(50))
          guard let self else { return }
          if !self.busy {
            self.settlementTask = nil
            self.settle()
            return
          }
        }
      }
    }
    private func settle() {
      guard !busy, awaitingDate == nil, let current, horizontal.bounds.width > 0 else { return }
      if let pending, pending.date != current.date || pending.reset != current.reset {
        applyPending()
        return
      }
      let page = min(
        2, max(0, Int((horizontal.contentOffset.x / horizontal.bounds.width).rounded())))
      if page != 1 {
        let date = Calendar.current.date(byAdding: .day, value: page - 1, to: current.date)!
        awaitingDate = date
        current.selectDate(date)
      } else {
        applyPending()
      }
    }
  }
}
