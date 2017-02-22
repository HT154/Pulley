//
//  PulleyViewController.swift
//  Pulley
//
//  Created by Brendan Lee on 7/6/16.
//  Copyright © 2016 52inc. All rights reserved.
//

import UIKit

/**
 *  The base delegate protocol for Pulley delegates.
 */
@objc public protocol PulleyDelegate: class {

    @objc optional func drawerPositionDidChange(drawer: PulleyViewController)
    @objc optional func makeUIAdjustmentsForFullscreen(progress: CGFloat)
    @objc optional func drawerChangedDistanceFromBottom(drawer: PulleyViewController, distance: CGFloat)
}

/**
 *  View controllers in the drawer can implement this to receive changes in state or provide values for the different drawer positions.
 */
public protocol PulleyDrawerViewControllerDelegate: PulleyDelegate {
    var collapsedDrawerHeight: CGFloat { get }
    var partialRevealDrawerHeight: CGFloat { get }
    var supportedDrawerPositions: [PulleyPosition] { get }
    func setDrawerScrollViewBottomInset(_: CGFloat)
}

extension PulleyDrawerViewControllerDelegate {
    public var collapsedDrawerHeight: CGFloat { return 56 }
    public var partialRevealDrawerHeight: CGFloat { return 56 }
    public var supportedDrawerPositions: [PulleyPosition] { return PulleyPosition.all }
    public func setDrawerScrollViewBottomInset(_: CGFloat) {}
}

extension UIViewController {
    var drawerController: PulleyViewController? {
        return (self as? PulleyViewController) ?? self.parent?.drawerController
    }
}

public class PulleyNavigationController: UINavigationController, PulleyDrawerViewControllerDelegate {

    public var collapsedDrawerHeight: CGFloat {
        if let h = (topViewController as? PulleyDrawerViewControllerDelegate)?.collapsedDrawerHeight {
            return h + navigationBar.bounds.size.height
        }

        return 56
    }

    public var partialRevealDrawerHeight: CGFloat {
        if let h = (topViewController as? PulleyDrawerViewControllerDelegate)?.partialRevealDrawerHeight {
            return h + navigationBar.bounds.size.height
        }

        return 56
    }

    public var supportedDrawerPositions: [PulleyPosition] {
        return (topViewController as? PulleyDrawerViewControllerDelegate)?.supportedDrawerPositions ?? PulleyPosition.all
    }

    public func setDrawerScrollViewBottomInset(_ offset: CGFloat) {
        (topViewController as? PulleyDrawerViewControllerDelegate)?.setDrawerScrollViewBottomInset(offset - navigationBar.bounds.size.height)
    }

    public func drawerPositionDidChange(drawer: PulleyViewController) {
        (topViewController as? PulleyDrawerViewControllerDelegate)?.drawerPositionDidChange?(drawer: drawer)
    }

    public func makeUIAdjustmentsForFullscreen(progress: CGFloat) {
        (topViewController as? PulleyDrawerViewControllerDelegate)?.makeUIAdjustmentsForFullscreen?(progress: progress)
    }

    public func drawerChangedDistanceFromBottom(drawer: PulleyViewController, distance: CGFloat) {
        (topViewController as? PulleyDrawerViewControllerDelegate)?.drawerChangedDistanceFromBottom?(drawer: drawer, distance: distance)
    }

    public override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }

}

/**
 *  View controllers that are the main content can implement this to receive changes in state.
 */
public protocol PulleyPrimaryContentControllerDelegate: PulleyDelegate {

    // Not currently used for anything, but it's here for parity with the hopes that it'll one day be used.
}

/**
 Represents a Pulley drawer position.

 - collapsed:         When the drawer is in its smallest form, at the bottom of the screen.
 - partiallyRevealed: When the drawer is partially revealed.
 - open:              When the drawer is fully open.
 - closed:            When the drawer is off-screen at the bottom of the view. Note: Users cannot close or reopen the drawer on their own. You must set this programatically
 */
public enum PulleyPosition: Int {

    case collapsed = 0
    case partiallyRevealed = 1
    case open = 2
    case closed = 3

    public static let all: [PulleyPosition] = [
        .collapsed,
        .partiallyRevealed,
        .open,
        .closed
    ]

    public static func positionFor(string: String?) -> PulleyPosition {
        guard let positionString = string?.lowercased() else {
            return .collapsed
        }

        switch positionString {
        case "collapsed": return .collapsed
        case "partiallyrevealed": return .partiallyRevealed
        case "open": return .open
        case "closed": return .closed
        default:
            print("PulleyViewController: Position for string '\(positionString)' not found. Available values are: collapsed, partiallyRevealed, open, and closed. Defaulting to collapsed.")
            return .collapsed
        }
    }
}

private let kPulleyDefaultCollapsedHeight: CGFloat = 68.0
private let kPulleyDefaultPartialRevealHeight: CGFloat = 264.0

open class PulleyViewController: UIViewController, UIScrollViewDelegate, PulleyPassthroughScrollViewDelegate {

    // Interface Builder

    /// When using with Interface Builder only! Connect a containing view to this outlet.
    @IBOutlet public var primaryContentContainerView: UIView!

    /// When using with Interface Builder only! Connect a containing view to this outlet.
    @IBOutlet public var drawerContentContainerView: UIView!

    // Internal
    private let primaryContentContainer: UIView = UIView()
    private let drawerContentContainer: UIView = UIView()
    private let drawerShadowView: UIView = UIView()
    private let drawerScrollView: PulleyPassthroughScrollView = PulleyPassthroughScrollView()
    private let drawerMaxWidth: CGFloat = 640
    private let backgroundDimmingView: UIView = UIView()

    private var dimmingViewTapRecognizer: UITapGestureRecognizer?

    /// The current content view controller (shown behind the drawer).
    public fileprivate(set) var primaryContentViewController: UIViewController! {
        willSet {
            guard let controller = primaryContentViewController
                else { return }

            controller.view.removeFromSuperview()
            controller.willMove(toParentViewController: nil)
            controller.removeFromParentViewController()
        }

        didSet {
            guard let controller = primaryContentViewController
                else { return }

            controller.view.translatesAutoresizingMaskIntoConstraints = true

            primaryContentContainer.addSubview(controller.view)
            addChildViewController(controller)
            controller.didMove(toParentViewController: self)

            if isViewLoaded {
                view.setNeedsLayout()
                setNeedsSupportedDrawerPositionsUpdate()
            }
        }
    }

    /// The current drawer view controller (shown in the drawer).
    public fileprivate(set) var drawerContentViewController: UIViewController! {
        willSet {
            guard let controller = drawerContentViewController else { return }

            controller.view.removeFromSuperview()
            controller.willMove(toParentViewController: nil)
            controller.removeFromParentViewController()
        }

        didSet {
            guard let controller = drawerContentViewController else { return }

            controller.view.translatesAutoresizingMaskIntoConstraints = true

            drawerContentContainer.addSubview(controller.view)
            addChildViewController(controller)
            controller.didMove(toParentViewController: self)

            guard isViewLoaded else { return }

            view.setNeedsLayout()
            setNeedsSupportedDrawerPositionsUpdate()
        }
    }

    /// The content view controller and drawer controller can receive delegate events already. This lets another object observe the changes, if needed.
    public weak var delegate: PulleyDelegate?

    /// The current position of the drawer.
    public fileprivate(set) var drawerPosition: PulleyPosition = .collapsed {
        didSet { setNeedsStatusBarAppearanceUpdate() }
    }

    /// The background visual effect layer for the drawer. By default this is the extraLight effect. You can change this if you want, or assign nil to remove it.
    public var drawerBackgroundView: UIView? = UIVisualEffectView(effect: UIBlurEffect(style: .extraLight)) {
        willSet { drawerBackgroundView?.removeFromSuperview() }
        didSet {
            guard let drawerBackgroundVisualEffectView = drawerBackgroundView, isViewLoaded
                else { return  }

            drawerScrollView.insertSubview(drawerBackgroundVisualEffectView, aboveSubview: drawerShadowView)
            drawerBackgroundVisualEffectView.clipsToBounds = true
            drawerBackgroundVisualEffectView.layer.cornerRadius = drawerCornerRadius
        }
    }

    /// The inset from the top of the view controller when fully open.
    @IBInspectable public var topInset: CGFloat = 50.0 {
        didSet {
            guard isViewLoaded else { return }

            view.setNeedsLayout()
        }
    }

    /// The corner radius for the drawer.
    @IBInspectable public var drawerCornerRadius: CGFloat = 13.0 {
        didSet {
            guard isViewLoaded else { return }

            view.setNeedsLayout()
            drawerBackgroundView?.layer.cornerRadius = drawerCornerRadius
        }
    }

    /// The opacity of the drawer shadow.
    @IBInspectable public var shadowOpacity: Float = 0.1 {
        didSet {
            guard isViewLoaded else { return }

            view.setNeedsLayout()
        }
    }

    /// The radius of the drawer shadow.
    @IBInspectable public var shadowRadius: CGFloat = 3.0 {
        didSet {
            guard isViewLoaded else { return }

            view.setNeedsLayout()
        }
    }

    /// The opaque color of the background dimming view.
    @IBInspectable public var backgroundDimmingColor: UIColor = UIColor.black {
        didSet {
            guard isViewLoaded else { return }

            backgroundDimmingView.backgroundColor = backgroundDimmingColor
        }
    }

    /// The maximum amount of opacity when dimming.
    @IBInspectable public var backgroundDimmingOpacity: CGFloat = 0.5 {
        didSet {
            guard isViewLoaded else { return }

            scrollViewDidScroll(drawerScrollView)
        }
    }

    /// The starting position for the drawer when it first loads
    public var initialDrawerPosition: PulleyPosition = .collapsed

    /// This is here exclusively to support IBInspectable in Interface Builder because Interface Builder can't deal with enums. If you're doing this in code use the -initialDrawerPosition property instead. Available strings are: open, closed, partiallyRevealed, collapsed
    @IBInspectable public var initialDrawerPositionFromIB: String? {
        didSet {
            initialDrawerPosition = PulleyPosition.positionFor(string: initialDrawerPositionFromIB)
        }
    }

    /// The drawer positions supported by the drawer
    fileprivate var supportedDrawerPositions: [PulleyPosition] = PulleyPosition.all {
        didSet {
            guard isViewLoaded else { return }
            guard supportedDrawerPositions.count > 0 else {
                supportedDrawerPositions = PulleyPosition.all
                return
            }

            view.setNeedsLayout()

            if supportedDrawerPositions.contains(drawerPosition) {
                setDrawerPosition(position: drawerPosition)
            } else {
                let lowestDrawerState: PulleyPosition = supportedDrawerPositions.min { $0.rawValue < $1.rawValue } ?? .collapsed
                setDrawerPosition(position: lowestDrawerState, animated: false)
            }

            drawerScrollView.isScrollEnabled = supportedDrawerPositions.count > 1
        }
    }

    /**
     Initialize the drawer controller programmtically.

     - parameter contentViewController: The content view controller. This view controller is shown behind the drawer.
     - parameter drawerViewController:  The view controller to display inside the drawer.

     - note: The drawer VC is 20pts too tall in order to have some extra space for the bounce animation. Make sure your constraints / content layout take this into account.

     - returns: A newly created Pulley drawer.
     */
    required public init(contentViewController: UIViewController, drawerViewController: UIViewController) {
        super.init(nibName: nil, bundle: nil)

        _ = {
            self.primaryContentViewController = contentViewController
            self.drawerContentViewController = drawerViewController
        }()
    }

    /**
     Initialize the drawer controller from Interface Builder.

     - note: Usage notes: Make 2 container views in Interface Builder and connect their outlets to -primaryContentContainerView and -drawerContentContainerView. Then use embed segues to place your content/drawer view controllers into the appropriate container.

     - parameter aDecoder: The NSCoder to decode from.

     - returns: A newly created Pulley drawer.
     */
    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    override open func loadView() {
        super.loadView()

        // IB Support
        if primaryContentContainerView != nil {
            primaryContentContainerView.removeFromSuperview()
        }

        if drawerContentContainerView != nil {
            drawerContentContainerView.removeFromSuperview()
        }

        // Setup
        primaryContentContainer.backgroundColor = .white

        drawerScrollView.bounces = true
        drawerScrollView.delegate = self
        drawerScrollView.clipsToBounds = false
        drawerScrollView.showsVerticalScrollIndicator = false
        drawerScrollView.showsHorizontalScrollIndicator = false
        drawerScrollView.delaysContentTouches = true
        drawerScrollView.canCancelContentTouches = true
        drawerScrollView.backgroundColor = .clear
        drawerScrollView.decelerationRate = UIScrollViewDecelerationRateFast
        drawerScrollView.touchDelegate = self

        drawerShadowView.layer.shadowOpacity = shadowOpacity
        drawerShadowView.layer.shadowRadius = shadowRadius
        drawerShadowView.backgroundColor = .clear

        drawerContentContainer.backgroundColor = .clear

        backgroundDimmingView.backgroundColor = backgroundDimmingColor
        backgroundDimmingView.isUserInteractionEnabled = false
        backgroundDimmingView.alpha = 0.0

        drawerBackgroundView?.clipsToBounds = true

        dimmingViewTapRecognizer = UITapGestureRecognizer(target: self, action: #selector(PulleyViewController.dimmingViewTapRecognizerAction(gestureRecognizer:)))
        backgroundDimmingView.addGestureRecognizer(dimmingViewTapRecognizer!)

        drawerScrollView.addSubview(drawerShadowView)

        if let drawerBackgroundVisualEffectView = drawerBackgroundView {
            drawerScrollView.addSubview(drawerBackgroundVisualEffectView)
            drawerBackgroundVisualEffectView.layer.cornerRadius = drawerCornerRadius
        }

        drawerScrollView.addSubview(drawerContentContainer)

        primaryContentContainer.backgroundColor = UIColor.white

        view.backgroundColor = UIColor.white

        view.addSubview(primaryContentContainer)
        view.addSubview(backgroundDimmingView)
        view.addSubview(drawerScrollView)
    }

    override open func viewDidLoad() {
        super.viewDidLoad()

        // IB Support
        if primaryContentViewController == nil || drawerContentViewController == nil {
            assert(primaryContentContainerView != nil && drawerContentContainerView != nil, "When instantiating from Interface Builder you must provide container views with an embedded view controller.")

            // Locate main content VC
            for child in childViewControllers {
                if child.view == primaryContentContainerView.subviews.first {
                    primaryContentViewController = child
                }

                if child.view == drawerContentContainerView.subviews.first {
                    drawerContentViewController = child
                }
            }

            assert(primaryContentViewController != nil && drawerContentViewController != nil, "Container views must contain an embedded view controller.")
        }

        setDrawerPosition(position: initialDrawerPosition, animated: false)

        scrollViewDidScroll(drawerScrollView)
    }

    override open func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        setNeedsSupportedDrawerPositionsUpdate()
    }

    override open func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // Layout main content
        primaryContentContainer.frame = view.bounds
        backgroundDimmingView.frame = view.bounds

        // Layout container
        var collapsedHeight: CGFloat = kPulleyDefaultCollapsedHeight
        var partialRevealHeight: CGFloat = kPulleyDefaultPartialRevealHeight

        if let drawerVCCompliant = drawerContentViewController as? PulleyDrawerViewControllerDelegate {
            collapsedHeight = drawerVCCompliant.collapsedDrawerHeight
            partialRevealHeight = drawerVCCompliant.partialRevealDrawerHeight
        }

        let lowestStop = [view.bounds.size.height - topInset, collapsedHeight, partialRevealHeight].min() ?? 0
        let bounceOverflowMargin: CGFloat = 500

        let drawerW = min(drawerMaxWidth, view.bounds.size.width)
        let drawerX = max(view.bounds.size.width - drawerMaxWidth, 0) / 2

        if supportedDrawerPositions.contains(.open) {
            // Layout scrollview
            drawerScrollView.frame = CGRect(x: drawerX, y: topInset, width: drawerW, height: view.bounds.height - topInset)
        } else {
            // Layout scrollview
            let adjustedTopInset: CGFloat = supportedDrawerPositions.contains(.partiallyRevealed) ? partialRevealHeight : collapsedHeight
            drawerScrollView.frame = CGRect(x: drawerX, y: view.bounds.height - adjustedTopInset, width: drawerW, height: adjustedTopInset)
        }

        drawerContentContainer.frame = CGRect(x: 0, y: drawerScrollView.bounds.height - lowestStop, width: drawerScrollView.bounds.width, height: drawerScrollView.bounds.height + bounceOverflowMargin)
        drawerContentViewController?.view.frame.size.height = drawerScrollView.bounds.height
        (drawerContentViewController as? PulleyDrawerViewControllerDelegate)?.setDrawerScrollViewBottomInset(bounceOverflowMargin)
        drawerBackgroundView?.frame = drawerContentContainer.frame
        drawerShadowView.frame = drawerContentContainer.frame
        drawerScrollView.contentSize = CGSize(width: drawerScrollView.bounds.width, height: (drawerScrollView.bounds.height - lowestStop) + drawerScrollView.bounds.height)

        // Update rounding mask and shadows
        let borderPath = UIBezierPath(roundedRect: drawerContentContainer.bounds, byRoundingCorners: [.topLeft, .topRight], cornerRadii: CGSize(width: drawerCornerRadius, height: drawerCornerRadius)).cgPath

        let cardMaskLayer = CAShapeLayer()
        cardMaskLayer.path = borderPath
        cardMaskLayer.frame = drawerContentContainer.bounds
        cardMaskLayer.fillColor = UIColor.white.cgColor
        cardMaskLayer.backgroundColor = UIColor.clear.cgColor
        drawerContentContainer.layer.mask = cardMaskLayer
        drawerShadowView.layer.shadowPath = borderPath

        // Make VC views match frames
        primaryContentViewController?.view.frame = primaryContentContainer.bounds
        drawerContentViewController?.view.frame = CGRect(x: drawerContentContainer.bounds.minX, y: drawerContentContainer.bounds.minY, width: drawerContentContainer.bounds.width, height: drawerContentContainer.bounds.height)

        setDrawerPosition(position: drawerPosition, animated: false)
    }

    // MARK: Configuration Updates

    /**
     Set the drawer position, with an option to animate.

     - parameter position: The position to set the drawer to.
     - parameter animated: Whether or not to animate the change. (Default: true)
     */

    public func setDrawerPosition(position: PulleyPosition, animated: Bool = true) {
        guard supportedDrawerPositions.contains(position) else {
            print("PulleyViewController: You can't set the drawer position to something not supported by the current view controller contained in the drawer. If you haven't already, you may need to implement the PulleyDrawerViewControllerDelegate.")
            return
        }

        drawerPosition = position

        var collapsedHeight :CGFloat = kPulleyDefaultCollapsedHeight
        var partialRevealHeight: CGFloat = kPulleyDefaultPartialRevealHeight

        if let drawerVCCompliant = drawerContentViewController as? PulleyDrawerViewControllerDelegate {
            collapsedHeight = drawerVCCompliant.collapsedDrawerHeight
            partialRevealHeight = drawerVCCompliant.partialRevealDrawerHeight
        }

        let stopToMoveTo: CGFloat

        switch drawerPosition {
        case .collapsed: stopToMoveTo = collapsedHeight
        case .partiallyRevealed: stopToMoveTo = partialRevealHeight
        case .open: stopToMoveTo = view.bounds.size.height - topInset
        case .closed: stopToMoveTo = 0
        }

        let drawerStops = [view.bounds.size.height - topInset, collapsedHeight, partialRevealHeight]
        let lowestStop = drawerStops.min() ?? 0

        if animated {
            UIView.animate(withDuration: 0.3, delay: 0.0, usingSpringWithDamping: 0.75, initialSpringVelocity: 0.0, options: .curveEaseInOut, animations: { [weak self] in
                self?.drawerScrollView.setContentOffset(CGPoint(x: 0, y: stopToMoveTo - lowestStop), animated: false)

                if let drawer = self {
                    drawer.delegate?.drawerPositionDidChange?(drawer: drawer)
                    (drawer.drawerContentViewController as? PulleyDrawerViewControllerDelegate)?.drawerPositionDidChange?(drawer: drawer)
                    (drawer.primaryContentViewController as? PulleyPrimaryContentControllerDelegate)?.drawerPositionDidChange?(drawer: drawer)

                    drawer.view.layoutIfNeeded()
                }
                }, completion: nil)
        } else {
            drawerScrollView.setContentOffset(CGPoint(x: 0, y: stopToMoveTo - lowestStop), animated: false)

            delegate?.drawerPositionDidChange?(drawer: self)
            (drawerContentViewController as? PulleyDrawerViewControllerDelegate)?.drawerPositionDidChange?(drawer: self)
            (primaryContentViewController as? PulleyPrimaryContentControllerDelegate)?.drawerPositionDidChange?(drawer: self)
        }
    }

    /**
     Change the current primary content view controller (The one behind the drawer)

     - parameter controller: The controller to replace it with
     - parameter animated:   Whether or not to animate the change. Defaults to true.
     */
    public func setPrimaryContentViewController(controller: UIViewController, animated: Bool = true) {
        if animated {
            UIView.transition(with: primaryContentContainer, duration: 0.5, options: UIViewAnimationOptions.transitionCrossDissolve, animations: { [weak self] in
                self?.primaryContentViewController = controller
                }, completion: nil)
        } else {
            primaryContentViewController = controller
        }
    }

    /**
     Change the current drawer content view controller (The one inside the drawer)

     - parameter controller: The controller to replace it with
     - parameter animated:   Whether or not to animate the change.
     */
    public func setDrawerContentViewController(controller: UIViewController, animated: Bool = true) {
        if animated {
            UIView.transition(with: drawerContentContainer, duration: 0.5, options: UIViewAnimationOptions.transitionCrossDissolve, animations: { [weak self] in
                self?.drawerContentViewController = controller
                self?.setDrawerPosition(position: self?.drawerPosition ?? .collapsed, animated: false)
                }, completion: nil)
        } else {
            drawerContentViewController = controller
            setDrawerPosition(position: drawerPosition, animated: false)
        }
    }

    /**
     Update the supported drawer positions allows by the Pulley Drawer
     */
    public func setNeedsSupportedDrawerPositionsUpdate() {
        if let drawerVCCompliant = drawerContentViewController as? PulleyDrawerViewControllerDelegate {
            supportedDrawerPositions = drawerVCCompliant.supportedDrawerPositions
        } else {
            supportedDrawerPositions = PulleyPosition.all
        }
    }

    // MARK: Actions

    func dimmingViewTapRecognizerAction(gestureRecognizer: UITapGestureRecognizer) {
        if gestureRecognizer == dimmingViewTapRecognizer && gestureRecognizer.state == .ended {
            setDrawerPosition(position: .collapsed, animated: true)
        }
    }

    // MARK: UIScrollViewDelegate

    public func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard scrollView == drawerScrollView else { return }

        endDragAction?()
        endDragAction = nil
    }

    public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        if scrollView.contentOffset.y <= 5 { // disable bouncing once drawer is at rest at the bottom
            drawerScrollView.bounces = false
        }
    }

    var endDragAction: (() -> Void)?

    public func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        guard scrollView == drawerScrollView else { return }

        // Find the closest anchor point and snap there.
        var collapsedHeight:CGFloat = kPulleyDefaultCollapsedHeight
        var partialRevealHeight:CGFloat = kPulleyDefaultPartialRevealHeight

        if let drawerVCCompliant = drawerContentViewController as? PulleyDrawerViewControllerDelegate {
            collapsedHeight = drawerVCCompliant.collapsedDrawerHeight
            partialRevealHeight = drawerVCCompliant.partialRevealDrawerHeight
        }

        var drawerStops: [CGFloat] = []

        if supportedDrawerPositions.contains(.open) {
            drawerStops.append(view.bounds.size.height - topInset)
        }

        if supportedDrawerPositions.contains(.partiallyRevealed) {
            drawerStops.append(partialRevealHeight)
        }

        if supportedDrawerPositions.contains(.collapsed) {
            drawerStops.append(collapsedHeight)
        }

        let lowestStop = drawerStops.min() ?? 0

        let distanceFromBottomOfView = lowestStop + targetContentOffset.pointee.y

        var currentClosestStop = lowestStop

        for currentStop in drawerStops
            where abs(currentStop - distanceFromBottomOfView) < abs(currentClosestStop - distanceFromBottomOfView) {
                currentClosestStop = currentStop
        }

        if abs(Float(currentClosestStop - (view.bounds.size.height - topInset))) <= FLT_EPSILON && supportedDrawerPositions.contains(.open) {
            if distanceFromBottomOfView < (view.bounds.size.height - topInset) {
                targetContentOffset.pointee = scrollView.contentOffset
                endDragAction = {
                    self.setDrawerPosition(position: .open, animated: true)
                }
            } else { // we're above the top stop, let the scroll view bounce for us
                endDragAction = {
                    self.drawerPosition = .open
                    self.delegate?.drawerPositionDidChange?(drawer: self)
                    (self.drawerContentViewController as? PulleyDrawerViewControllerDelegate)?.drawerPositionDidChange?(drawer: self)
                    (self.primaryContentViewController as? PulleyPrimaryContentControllerDelegate)?.drawerPositionDidChange?(drawer: self)
                }
            }
        } else if abs(Float(currentClosestStop - collapsedHeight)) <= FLT_EPSILON && supportedDrawerPositions.contains(.collapsed) {
            if distanceFromBottomOfView > collapsedHeight {
                targetContentOffset.pointee = scrollView.contentOffset
                endDragAction = {
                    self.setDrawerPosition(position: .collapsed, animated: true)
                }
            } else { // we're below the bottom stop, let the scroll view bounce for us
                endDragAction = {
                    self.drawerPosition = .collapsed
                    self.delegate?.drawerPositionDidChange?(drawer: self)
                    (self.drawerContentViewController as? PulleyDrawerViewControllerDelegate)?.drawerPositionDidChange?(drawer: self)
                    (self.primaryContentViewController as? PulleyPrimaryContentControllerDelegate)?.drawerPositionDidChange?(drawer: self)
                }
            }
        } else if supportedDrawerPositions.contains(.partiallyRevealed) {
            targetContentOffset.pointee = scrollView.contentOffset
            endDragAction = {
                self.setDrawerPosition(position: .partiallyRevealed, animated: true)
            }
        }
    }

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView == drawerScrollView else { return }

        var partialRevealHeight: CGFloat = kPulleyDefaultPartialRevealHeight
        var collapsedHeight: CGFloat = kPulleyDefaultCollapsedHeight

        if let drawerVCCompliant = drawerContentViewController as? PulleyDrawerViewControllerDelegate {
            collapsedHeight = drawerVCCompliant.collapsedDrawerHeight
            partialRevealHeight = drawerVCCompliant.partialRevealDrawerHeight
        }

        var drawerStops: [CGFloat] = []

        if supportedDrawerPositions.contains(.open) {
            drawerStops.append(view.bounds.size.height - topInset)
        }

        if supportedDrawerPositions.contains(.partiallyRevealed) {
            drawerStops.append(partialRevealHeight)
        }

        if supportedDrawerPositions.contains(.collapsed) {
            drawerStops.append(collapsedHeight)
        }

        let lowestStop = drawerStops.min() ?? 0

        if scrollView.contentOffset.y > partialRevealHeight - lowestStop {
            // Calculate percentage between partial and full reveal
            let fullRevealHeight = view.bounds.size.height - topInset

            let progress = (scrollView.contentOffset.y - (partialRevealHeight - lowestStop)) / (fullRevealHeight - partialRevealHeight)

            delegate?.makeUIAdjustmentsForFullscreen?(progress: progress)
            (drawerContentViewController as? PulleyDrawerViewControllerDelegate)?.makeUIAdjustmentsForFullscreen?(progress: progress)
            (primaryContentViewController as? PulleyPrimaryContentControllerDelegate)?.makeUIAdjustmentsForFullscreen?(progress: progress)

            backgroundDimmingView.alpha = progress * backgroundDimmingOpacity

            backgroundDimmingView.isUserInteractionEnabled = true
        } else if backgroundDimmingView.alpha >= 0.001 {
            backgroundDimmingView.alpha = 0.0

            delegate?.makeUIAdjustmentsForFullscreen?(progress: 0.0)
            (drawerContentViewController as? PulleyDrawerViewControllerDelegate)?.makeUIAdjustmentsForFullscreen?(progress: 0.0)
            (primaryContentViewController as? PulleyPrimaryContentControllerDelegate)?.makeUIAdjustmentsForFullscreen?(progress: 0.0)

            backgroundDimmingView.isUserInteractionEnabled = false
        }

        delegate?.drawerChangedDistanceFromBottom?(drawer: self, distance: scrollView.contentOffset.y + lowestStop)
        (drawerContentViewController as? PulleyDrawerViewControllerDelegate)?.drawerChangedDistanceFromBottom?(drawer: self, distance: scrollView.contentOffset.y + lowestStop)
        (primaryContentViewController as? PulleyPrimaryContentControllerDelegate)?.drawerChangedDistanceFromBottom?(drawer: self, distance: scrollView.contentOffset.y + lowestStop)

        if drawerScrollView.contentOffset.y > 0 && drawerScrollView.contentOffset.y < drawerStops.max()! - drawerStops.min()! {
            // enable bouncing if scrolling between the bottom and top stops
            drawerScrollView.bounces = true
        }
    }

    // MARK: Touch Passthrough ScrollView Delegate

    func shouldTouchPassthroughScrollView(scrollView: PulleyPassthroughScrollView, point: CGPoint) -> Bool {
        let contentDrawerLocation = drawerContentContainer.frame.origin.y

        return point.y < contentDrawerLocation
    }

    func viewToReceiveTouch(scrollView: PulleyPassthroughScrollView) -> UIView {
        if drawerPosition == .open || (!supportedDrawerPositions.contains(.open) && drawerPosition == .partiallyRevealed) {
            return backgroundDimmingView
        }

        return primaryContentContainer
    }

    // MARK: Propogate child view controller style / status bar presentation based on drawer state

    override open var childViewControllerForStatusBarStyle: UIViewController? {
        get {
            if drawerPosition == .open {
                return drawerContentViewController
            }

            return primaryContentViewController
        }
    }

    override open var childViewControllerForStatusBarHidden: UIViewController? {
        get {
            if drawerPosition == .open {
                return drawerContentViewController
            }

            return primaryContentViewController
        }
    }
}
