import Cutie
import CutieExplorer
import Qt.labs.folderlistmodel
import Qt.labs.settings
import QtQuick
import QtQuick.Controls
import "Formatting.js" as Formatting

CutiePage {
	id: folderView

	// Full navigation trail down to this folder, e.g.
	// [{label:"Home", path:"/home/mathew"}, {label:"Photos", path:"/home/mathew/Photos"}]
	// Passed straight through and extended on each push, so the breadcrumb
	// can show the whole trail without any single page needing to know its
	// ancestors. Always supplied by whoever pushes this page.
	property var crumbs: []

	readonly property string folderPath: crumbs.length ? crumbs[crumbs.length - 1].path : ""
	readonly property string folderName: crumbs.length ? crumbs[crumbs.length - 1].label : ""

	property var folderComponent: Qt.createComponent("FolderView.qml")

	// View mode persists via Qt.labs.settings, so it's remembered the next
	// time the app opens - shared across all FolderView instances since
	// they all read/write the same "view/mode" key.
	Settings {
		id: viewSettings
		category: "view"
		property string mode: "list"
	}

	function openChild(path, label) {
		if (folderView.folderComponent.status === Component.Ready) {
			mainWindow.pageStack.push(folderView.folderComponent,
				{ crumbs: folderView.crumbs.concat([{ label: label, path: path }]) });
		}
	}

	// Re-pushing for a breadcrumb tap grows the stack, so back-swipe would
	// return to wherever you'd drilled down to, not the folder above the
	// one you tapped. Popping back to that page instead keeps the stack's
	// depth matching the breadcrumb trail, so a normal back-swipe from
	// there goes up exactly one level, as expected.
	//
	// Todo: test further or fix cutie pageStack
	//
	// Cutie's PageStack doesn't expose get()/pop(item) like a plain
	// QtQuick StackView does - only push() and no-arg pop() are confirmed
	// to exist (see ApnCfg.qml/WifiPsk.qml in cutie-settings) - so this
	// just calls pop() once per level instead of targeting a page directly.
	function goToCrumb(index) {
		var popCount = folderView.crumbs.length - (index + 1);
		for (var i = 0; i < popCount; i++)
			mainWindow.pageStack.pop();
	}

	function handleRename(name, path) {
		renameDialog.openFor(name, path);
	}

	function handleProperties(name, path, isDir, size, modified) {
		propertiesDialog.fileName = name;
		propertiesDialog.filePath = path;
		propertiesDialog.fileIsDir = isDir;
		propertiesDialog.fileSize = size;
		propertiesDialog.fileModified = modified;
		propertiesDialog.open();
	}

	function handleDelete(name, path) {
		deleteDialog.targetName = name;
		deleteDialog.targetPath = path;
		deleteDialog.open();
	}

	FolderListModel {
		id: dirModel
		folder: "file://" + folderView.folderPath
		showDirsFirst: true
		showDotAndDotDot: false
		showHidden: false
		sortField: FolderListModel.Name
	}

	// ── Header + breadcrumb ─────────────────────────────────────────────
	Column {
		id: topColumn
		width: parent.width

		CutiePageHeader {
			id: header
			title: folderView.folderName
			width: parent.width

			CutieButton {
				id: overflowButton
				anchors.right: parent.right
				anchors.verticalCenter: parent.verticalCenter
				anchors.rightMargin: 15
				icon.name: "view-more-symbolic"
				background: null
				onClicked: viewMenu.open()
			}

			CutieMenu {
				id: viewMenu
				CutieMenuItem {
					text: qsTr("List view")
					onTriggered: viewSettings.mode = "list"
				}
				CutieMenuItem {
					text: qsTr("Grid view (large icons)")
					onTriggered: viewSettings.mode = "grid"
				}
			}
		}

		Flickable {
			width: parent.width
			height: crumbRow.height + 16
			contentWidth: crumbRow.width
			flickableDirection: Flickable.HorizontalFlick
			clip: true

			Row {
				id: crumbRow
				anchors.verticalCenter: parent.verticalCenter
				leftPadding: 16
				spacing: 4

				Repeater {
					model: folderView.crumbs
					delegate: Row {
						spacing: 4

						CutieLabel {
							text: modelData.label
							font.bold: index === folderView.crumbs.length - 1
							opacity: index === folderView.crumbs.length - 1 ? 1.0 : 0.7

							MouseArea {
								anchors.fill: parent
								enabled: index < folderView.crumbs.length - 1
								onClicked: folderView.goToCrumb(index)
							}
						}
						CutieLabel {
							text: "\u203a"
							opacity: 0.4
							visible: index < folderView.crumbs.length - 1
						}
					}
				}
			}
		}

		Rectangle {
			width: parent.width
			height: 1
			color: Atmosphere.secondaryAlphaColor
			opacity: 0.2
		}
	}

	// ── List view ────────────────────────────────────────────────────────
	ListView {
		id: listContent
		visible: viewSettings.mode === "list"
		anchors.top: topColumn.bottom
		anchors.left: parent.left
		anchors.right: parent.right
		anchors.bottom: parent.bottom
		model: dirModel
		clip: true

		delegate: CutieListItem {
			width: listContent.width
			text: fileName
			subText: fileIsDir
				? qsTr("%1 items | %2").arg(FileOperations.entryCount(filePath)).arg(Formatting.formatDate(fileModified))
				: qsTr("%1 | %2").arg(Formatting.humanSize(fileSize)).arg(Formatting.formatDate(fileModified))
			icon.name: fileIsDir ? "folder-symbolic" : "text-x-generic-symbolic"
			icon.color: Atmosphere.textColor

			onClicked: {
				if (fileIsDir)
					folderView.openChild(filePath, fileName);
				else
					listMenu.open();
			}
			onPressAndHold: listMenu.open()

			FileContextMenu {
				id: listMenu
				currentFolder: folderView.folderPath
				targetName: fileName
				targetPath: filePath
				targetIsDir: fileIsDir
				targetSize: fileSize
				targetModified: fileModified
				onRenameRequested: folderView.handleRename(name, path)
				onPropertiesRequested: folderView.handleProperties(name, path, isDir, size, modified)
				onDeleteRequested: folderView.handleDelete(name, path)
			}
		}
	}

	// ── Grid view (large icons) ─────────────────────────────────────────
	GridView {
		id: gridContent
		visible: viewSettings.mode === "grid"
		anchors.top: topColumn.bottom
		anchors.left: parent.left
		anchors.right: parent.right
		anchors.bottom: parent.bottom
		model: dirModel
		clip: true
		cellWidth: width / 3
		cellHeight: cellWidth

		delegate: Item {
			width: gridContent.cellWidth
			height: gridContent.cellHeight

			Column {
				anchors.centerIn: parent
				spacing: 6

				Image {
					anchors.horizontalCenter: parent.horizontalCenter
					source: "image://theme/" + (fileIsDir ? "folder" : "text-x-generic")
					sourceSize.width: 64
					sourceSize.height: 64
				}

				CutieLabel {
					width: gridContent.cellWidth - 12
					text: fileName
					horizontalAlignment: Text.AlignHCenter
					elide: Text.ElideMiddle
					font.pixelSize: 12
				}
			}

			MouseArea {
				anchors.fill: parent
				onClicked: {
					if (fileIsDir)
						folderView.openChild(filePath, fileName);
					else
						gridMenu.open();
				}
				onPressAndHold: gridMenu.open()
			}

			FileContextMenu {
				id: gridMenu
				currentFolder: folderView.folderPath
				targetName: fileName
				targetPath: filePath
				targetIsDir: fileIsDir
				targetSize: fileSize
				targetModified: fileModified
				onRenameRequested: folderView.handleRename(name, path)
				onPropertiesRequested: folderView.handleProperties(name, path, isDir, size, modified)
				onDeleteRequested: folderView.handleDelete(name, path)
			}
		}
	}

	RenameDialog {
		id: renameDialog
	}

	PropertiesDialog {
		id: propertiesDialog
	}

	Dialog {
		id: deleteDialog
		title: qsTr("Delete")
		modal: true
		standardButtons: Dialog.Yes | Dialog.No
		anchors.centerIn: parent

		property string targetName: ""
		property string targetPath: ""

		contentItem: CutieLabel {
			text: qsTr("Are you sure you want to permanently delete '%1'?").arg(deleteDialog.targetName)
			wrapMode: Text.Wrap
			width: 250
		}

		onAccepted: {
			FileOperations.deletePath(deleteDialog.targetPath);
		}
	}
}