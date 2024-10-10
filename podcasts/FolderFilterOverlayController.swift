import PocketCastsDataModel
import UIKit

class FolderFilterOverlayController: FolderChooserViewController, FolderSelectionDelegate {
	var filterToEdit: FolderFilter!
    var filterTintColor: UIColor!

    var selectAllSwitch: ThemeableSwitch!
    var headerView: FolderSelectionHeaderView!
    var footerView: ThemeableView!

    let folderFilterCellId = "FolderFilterCell"
    var saveButton: UIButton!

	override func viewDidLoad() {
        super.viewDidLoad()
        delegate = self
        folderTable.delegate = self
        folderTable.dataSource = self
        folderTable.separatorStyle = .none
        folderTable.register(UINib(nibName: "FolderFilterSelectionCell", bundle: nil), forCellReuseIdentifier: folderFilterCellId)

        setupNavBar()
        navigationController?.navigationBar.sizeToFit()
        setupHeader()
        setupSaveButton()

		// TODO setup selected folders
        updateSwitchStatus()
        updateRightBarBtn()
    }

	func setupNavBar() {
        setupCloseButton()
        changeNavTint(titleColor: nil, iconsColor: AppTheme.colorForStyle(.primaryIcon02))
        title = L10n.filterChooseFolders
        navigationController?.navigationBar.prefersLargeTitles = true

        let appearance = UINavigationBarAppearance()
        appearance.backgroundColor = AppTheme.colorForStyle(.primaryUi01)
        appearance.largeTitleTextAttributes = [
            NSAttributedString.Key.foregroundColor: AppTheme.colorForStyle(.primaryText01)
        ]
        appearance.titleTextAttributes = [
            NSAttributedString.Key.foregroundColor: AppTheme.colorForStyle(.primaryText01)
        ]
        navigationController?.navigationBar.scrollEdgeAppearance = appearance
        navigationController?.navigationBar.standardAppearance = appearance
    }

    func setupCloseButton() {
        let closeButton = createStandardCloseButton(imageName: "cancel")
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        let backButtonItem = UIBarButtonItem(customView: closeButton)
        navigationItem.leftBarButtonItem = backButtonItem
    }

	 func setupSaveButton() {
        footerView = ThemeableView()
        footerView.backgroundColor = AppTheme.viewBackgroundColor()
        saveButton = UIButton(type: .custom)
        saveButton.backgroundColor = filterToEdit.playlistColor()
        setupSaveButtonTitle()
        saveButton.layer.cornerRadius = 12
        saveButton.addTarget(self, action: #selector(saveTapped(sender:)), for: .touchUpInside)
        footerView.addSubview(saveButton)
        footerView.translatesAutoresizingMaskIntoConstraints = false
        saveButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            saveButton.leadingAnchor.constraint(equalTo: footerView.leadingAnchor, constant: 16),
            saveButton.trailingAnchor.constraint(equalTo: footerView.trailingAnchor, constant: -16),
            saveButton.bottomAnchor.constraint(equalTo: footerView.bottomAnchor, constant: -34),
            saveButton.topAnchor.constraint(equalTo: footerView.topAnchor, constant: 16)
        ])

        view.addSubview(footerView)
        view.bringSubviewToFront(footerView)
        NSLayoutConstraint.activate([
            footerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 0),
            footerView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: 0),
            footerView.heightAnchor.constraint(equalToConstant: 110),
            footerView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: 0)
        ])

        view.layoutSubviews()
    }

	private func setupSaveButtonTitle() {
        let attributedTitle = NSAttributedString(string: L10n.filterUpdate, attributes: [NSAttributedString.Key.foregroundColor: ThemeColor.primaryInteractive02(), NSAttributedString.Key.font: UIFont.systemFont(ofSize: 18.0, weight: .semibold)])
        saveButton.setAttributedTitle(attributedTitle, for: .normal)
    }

}