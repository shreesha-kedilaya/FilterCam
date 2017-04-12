//
//  ImagePreviewViewController.swift
//  FilterCam
//
//  Created by Shreesha on 20/03/17.
//  Copyright © 2017 YML. All rights reserved.
//

import UIKit

class ImagePreviewViewController: UIViewController {

    @IBOutlet weak var imageView: UIImageView!
    var image: UIImage!
    override func viewDidLoad() {
        super.viewDidLoad()
        self.imageView.image = image
        // Do any additional setup after loading the view.
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    @IBAction func filterButtonDidClick(_ sender: Any) {
        let filterViewController = storyboard?.instantiateViewController(withIdentifier: "FilterViewController") as! FilterViewController
        filterViewController.delegate = self
        filterViewController.image = self.imageView.image

        navigationController?.present(filterViewController, animated: true, completion: nil)
    }
}

extension ImagePreviewViewController: FilterViewControllerDelegate {
    func filterViewController(viewController: FilterViewController, didSelectFilter filter: CIFilter?) {
        viewController.dismiss(animated: true) { 
            self.showSpinner()
            FilterGenerator.filteredImageFor(filter: filter, image: self.imageView.image) { (image) in
                Async.main {
                    self.hideSpinner()
                    self.imageView.image = image

                    LibraryUtils.shared.saveImage(image: image!, completion: { (success) in

                    })
                }
            }
        }
    }
}
