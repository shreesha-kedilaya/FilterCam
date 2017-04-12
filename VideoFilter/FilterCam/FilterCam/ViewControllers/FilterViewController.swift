//
//  FilterViewController.swift
//  FilterCam
//
//  Created by Shreesha on 01/09/16.
//  Copyright © 2016 YML. All rights reserved.
//

import UIKit
import CoreImage

protocol FilterViewControllerDelegate: class {
    func filterViewController(viewController: FilterViewController, didSelectFilter filter: CIFilter?)
}

class FilterViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {

    @IBOutlet weak var filterCollectionView: UICollectionView!
    
    @IBOutlet weak var cancelButton: UIButton!
    var filter: CIFilter?
    var image: UIImage?
    var allCIFilters: ([CIFilter?], [String])!

    var filtersTexts = ["Hue", "Kaleidoscope", "Pixellate", "Vibrancy", "Blend"]

    private var currentSelectedIndex = 0

    weak var delegate: FilterViewControllerDelegate?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Filter"
        let image = #imageLiteral(resourceName: "Cancel").withRenderingMode(.alwaysTemplate)
        cancelButton.setImage(image, for: .normal)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        ciFilters { (filters) in
            self.allCIFilters = filters
            Async.main {
                self.filterCollectionView.reloadData()
            }
        }
    }

    deinit {
        print("Deinit for FilterViewController is called")
    }

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return allCIFilters?.0.count ?? 0
    }

    @IBAction func didSelectCancel(_ sender: Any) {
        dismiss(animated: true, completion: nil)
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "FilterCollectionViewCell", for: indexPath) as? FilterCollectionViewCell
        cell?.nameLabel.text = allCIFilters.1[indexPath.item]
        if let image = image {
            cell?.filterImageView.image = image
        } else {
            cell?.filterImageView.image = UIImage(named: "placeHolderVideo")
        }

        return cell!
    }

    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {

        let currentCell = cell as? FilterCollectionViewCell
        FilterGenerator.filteredImageFor(filter: allCIFilters.0[indexPath.item], image: image, completion: { (image) in
            Async.main {
                if let image = image {
                    currentCell?.filterImageView.image = image
                } else {
                    currentCell?.filterImageView.image = self.image
                }
            }
        })
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        filterCollectionView.reloadData()
    }

    private func filteredImageFor(indexPath: IndexPath, completion: @escaping (UIImage?) -> Void) {
        Async.global(.background) {
            FilterGenerator.filteredImageFor(filter: self.allCIFilters.0[indexPath.row], image: self.image) { (image) in
                completion(image)
            }
        }
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        return CGSize(width: 150, height: 175)
    }


    func ciFilters(completion: @escaping (([CIFilter?], [String])) -> Void) {

        Async.global(.background) {
            let filters = [nil,FilterGenerator.colorClamp(min: CIVector(values: [1, 1, 0, 0.8], count: 4), max: CIVector(values: [0, 0.5, 1, 0.6], count: 4)),
                           FilterGenerator.colorControls(saturation: 0.5, brightness: 0.1, contrast: 0.6),
                           FilterGenerator.colorMatrix(rVector: CIVector(values: [0, 0, 0, 2], count: 4), gVector: CIVector(values: [0, 1, 0, 0], count: 4), bVector: CIVector(values: [0, 0, 0, 0.5], count: 4), aVector: CIVector(values: [0, 0, 1, 1], count: 4), biasVector: CIVector(values: [0, 0.6, 0, 0], count: 4)),
                           FilterGenerator.bumpDistortion(inputCenter: CIVector(values: [self.image!.size.width / 2, self.image!.size.height / 2], count: 2), inputRadius: 300, inputScale: 1),
                           FilterGenerator.droste(inputInsetPoint0: CIVector(values: [self.image!.size.width / 2, self.image!.size.height / 2], count: 2), inputInsetPoint1: CIVector(values: [self.image!.size.width / 2 + 20, self.image!.size.height / 2 + 20], count: 2), inputStrands: 10, inputPeriodicity: 5, inputRotation: 0, inputZoom: 10),
                           FilterGenerator.lightTunnel(inputCenter: CIVector(values: [self.image!.size.width / 2, self.image!.size.height / 2], count: 2), inputRotation: 2, inputRadius: 150),
                           FilterGenerator.hueAdjust(angleInRadians: 1),
                           FilterGenerator.pixellate(scale: 20),
                           FilterGenerator.kaleidoscope(),
                           FilterGenerator.swapRGBFilter(inputAmount: 1),
                           FilterGenerator.vignetteEffect(),
                           FilterGenerator.chromaFilter(),
                           FilterGenerator.customToneCurveFilter(fileName: "OceanFree"),
                           FilterGenerator.customToneCurveFilter(fileName: "goldenCurve"),
                           FilterGenerator.customToneCurveFilter(fileName: "desert"),
                           FilterGenerator.customToneCurveFilter(fileName: "Country"),
                           FilterGenerator.customToneCurveFilter(fileName: "peacockFeather"),
                           FilterGenerator.customToneCurveFilter(fileName: "wildHeart")

            ]

            let strings = ["Normal","Color Clamp", "Color Controls", "Color Matrix", "Bump", "Droste", "Light Tunnel", "Hue", "Pixellate", "Keleidoscope", "Custom Filter", "VignetteFilter", "Chroma key", "Ocean free", "Golden feet", "Desert", "Country", "Peacock", "Wild Heart"]
            completion(filters, strings)
        }
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        currentSelectedIndex = indexPath.item
        let filter = allCIFilters.0[currentSelectedIndex]
        delegate?.filterViewController(viewController: self, didSelectFilter: filter)
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
        return UIEdgeInsets.zero
    }
}
