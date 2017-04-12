//
//  SpinnerView.swift
//  FilterCam
//
//  Created by Shreesha on 20/03/17.
//  Copyright © 2017 YML. All rights reserved.
//

import UIKit

class SpinnerView: UIView {

    @IBOutlet weak var spinnerActivity: UIActivityIndicatorView!
    /*
    // Only override draw() if you perform custom drawing.
    // An empty implementation adversely affects performance during animation.
    override func draw(_ rect: CGRect) {
        // Drawing code
    }
    */

}

extension UIViewController {
    func showSpinner() {
        let _view = Bundle.main.loadNibNamed("SpinnerView", owner: nil, options: nil)?.last as? SpinnerView
        _view?.tag = 12009
        _view?.frame = UIScreen.main.bounds
        _view?.backgroundColor = UIColor.black.withAlphaComponent(0.65)
        _view?.spinnerActivity.startAnimating()
        self.view.addSubview(_view!)
    }

    func hideSpinner() {
        
        if let _view = view.viewWithTag(12009) as? SpinnerView {
            _view.spinnerActivity.stopAnimating()
            _view.removeFromSuperview()
        }
    }
}
