//
//  SettingsViewController.swift
//  FilterCam
//
//  Created by Shreesha on 20/03/17.
//  Copyright © 2017 YML. All rights reserved.
//

import UIKit
import Photos

protocol SettingsViewControllerDelegate: class {
    func settingsViewController(vc: SettingsViewController, didSelectOPtion option: PHAssetMediaType)
}

class SettingsViewController: UIViewController {

    @IBOutlet weak var settingsTableView: UITableView!
    fileprivate let dataSource = ["Photo", "Video"]

    var currentCaptureTaype: PHAssetMediaType!

    weak var delegate: SettingsViewControllerDelegate?

    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
    }

    @IBAction func cancelButtonDidClick(_ sender: Any) {
        dismiss(animated: true, completion: nil)
    }
}

extension SettingsViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 2
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SettingsTableViewCell", for: indexPath) as! SettingsTableViewCell
        cell.titleLabel.text = dataSource[indexPath.row]

        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 50
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        switch indexPath.row {
        case 0:
            currentCaptureTaype = .image
        case 1:
            currentCaptureTaype = .video
        default: break
        }

        delegate?.settingsViewController(vc: self, didSelectOPtion: currentCaptureTaype)
    }
}
