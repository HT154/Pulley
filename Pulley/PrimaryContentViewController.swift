//
//  ViewController.swift
//  Pulley
//
//  Created by Brendan Lee on 7/6/16.
//  Copyright © 2016 52inc. All rights reserved.
//

import UIKit
import MapKit
import Pulley

class PrimaryContentViewController: UIViewController {
    
    @IBOutlet var mapView: MKMapView!
    @IBOutlet var controlsContainer: UIView!
    @IBOutlet var temperatureLabel: UILabel!
    
    @IBOutlet var temperatureLabelBottomConstraint: NSLayoutConstraint!
    
    fileprivate let temperatureLabelBottomDistance: CGFloat = 8.0
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        
        controlsContainer.layer.cornerRadius = 10.0
        temperatureLabel.layer.cornerRadius = 7.0
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
//        Uncomment if you want to change the visual effect style to dark. Note: The rest of the sample app's UI isn't made for dark theme. This just shows you how to do it.
//        if let drawer = self.parent as? PulleyViewController {
//            drawer.drawerBackgroundVisualEffectView = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
//        }
    }

    @IBAction func runPrimaryContentTransitionWithoutAnimation(sender: AnyObject) {
        guard let drawer = self.parent as? PulleyViewController else { return }

        let primaryContent = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "PrimaryTransitionTargetViewController")
        drawer.setPrimaryContentViewController(controller: primaryContent, animated: false)
    }
    
    @IBAction func runPrimaryContentTransition(sender: AnyObject) {
        guard let drawer = self.parent as? PulleyViewController else { return }

        let primaryContent = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "PrimaryTransitionTargetViewController")
        drawer.setPrimaryContentViewController(controller: primaryContent, animated: true)
    }
}

extension PrimaryContentViewController: PulleyPrimaryContentControllerDelegate {
    
    func makeUIAdjustmentsForFullscreen(progress: CGFloat) {
        controlsContainer.alpha = 1.0 - progress
    }
    
    func drawerChangedDistanceFromBottom(drawer: PulleyViewController, distance: CGFloat) {
        temperatureLabelBottomConstraint.constant = min(distance, 268) + temperatureLabelBottomDistance
    }
}

