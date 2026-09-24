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
	property string pendingPasteSource: ""
	property string pendingPasteFolder: ""
	property string pendingPasteMode: ""
	property bool multiSelectMode: false
	property var selectedPaths: []
	property var pendingPastePaths: []
	property int pendingPasteIndex: 0
	property bool pasteQueueActive: false
	property bool waitingForPasteDecision: false

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

	function isSelected(path) {
		return selectedPaths.indexOf(path) !== -1;
	}

	function toggleSelected(path) {
		var paths = selectedPaths.slice();
		var index = paths.indexOf(path);
		if (index === -1)
			paths.push(path);
		else
			paths.splice(index, 1);
		selectedPaths = paths;
	}

	function setSelectionClipboard(mode) {
		if (selectedPaths.length === 0)
			return;
		if (mode === "cut")
			FileClipboard.cutMany(selectedPaths);
		else
			FileClipboard.copyMany(selectedPaths);
		multiSelectMode = false;
		selectedPaths = [];
	}

	function startPaste(destFolder) {
		if (pasteQueueActive || !FileClipboard.hasContent)
			return;
		pendingPastePaths = FileClipboard.sourcePaths.slice();
		pendingPasteFolder = destFolder;
		pendingPasteMode = FileClipboard.mode;
		pendingPasteIndex = 0;
		pasteQueueActive = true;
		processNextPaste();
	}

	function processNextPaste() {
		if (pendingPasteIndex >= pendingPastePaths.length) {
			finishPasteQueue();
			return;
		}

		pendingPasteSource = pendingPastePaths[pendingPasteIndex];
		if (FileOperations.destinationExists(pendingPasteSource, pendingPasteFolder)) {
			waitingForPasteDecision = true;
			replaceDialog.open();
			return;
		}
		startCurrentPaste();
	}

	function startCurrentPaste() {
		var started = pendingPasteMode === "cut"
			? FileOperations.movePath(pendingPasteSource, pendingPasteFolder)
			: FileOperations.copyPath(pendingPasteSource, pendingPasteFolder);
		if (!started)
			advancePasteQueue();
	}

	function resolvePasteConflict(replace) {
		if (!waitingForPasteDecision)
			return;
		waitingForPasteDecision = false;
		replaceDialog.close();
		if (replace)
			startCurrentPaste();
		else
			advancePasteQueue();
	}

	function advancePasteQueue() {
		pendingPasteIndex++;
		Qt.callLater(processNextPaste);
	}

	function finishPasteQueue() {
		pasteQueueActive = false;
		FileClipboard.clear();
		pendingPasteSource = "";
		pendingPasteFolder = "";
		pendingPasteMode = "";
		pendingPastePaths = [];
		pendingPasteIndex = 0;
		waitingForPasteDecision = false;
	}

	Connections {
		target: FileOperations
		function onOperationFinished(success, message) {
			if (folderView.pasteQueueActive)
				folderView.advancePasteQueue();
		}
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
					text: folderView.multiSelectMode ? qsTr("Finish selection") : qsTr("Select multiple")
					onTriggered: {
						folderView.multiSelectMode = !folderView.multiSelectMode;
						if (!folderView.multiSelectMode)
							folderView.selectedPaths = [];
					}
				}
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

	CutieMenu {
		id: selectionMenu
		CutieMenuItem {
			text: qsTr("Copy selected")
			onTriggered: folderView.setSelectionClipboard("copy")
		}
		CutieMenuItem {
			text: qsTr("Cut selected")
			onTriggered: folderView.setSelectionClipboard("cut")
		}
	}

	CutieMenu {
		id: emptyFolderMenu
		CutieMenuItem {
			text: qsTr("Paste")
			enabled: FileClipboard.hasContent
			onTriggered: folderView.startPaste(folderView.folderPath)
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
			highlighted: folderView.multiSelectMode && folderView.isSelected(filePath)

			onClicked: {
				if (folderView.multiSelectMode)
					folderView.toggleSelected(filePath);
				else if (fileIsDir)
					folderView.openChild(filePath, fileName);
				else
					mainWindow.openFile(filePath);
			}
			onPressAndHold: {
				if (folderView.multiSelectMode) {
					if (!folderView.isSelected(filePath))
						folderView.toggleSelected(filePath);
					selectionMenu.open();
				} else {
					listMenu.open();
				}
			}

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
				onOpenRequested: mainWindow.openFile(path)
				onPasteRequested: folderView.startPaste(destFolder)
			}
		}

		MouseArea {
			anchors.fill: parent
			enabled: dirModel.count === 0
			onClicked: emptyFolderMenu.open()
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

			Rectangle {
				anchors.fill: parent
				radius: 8
				color: Atmosphere.secondaryAlphaColor
				opacity: 0.4
				visible: folderView.multiSelectMode && folderView.isSelected(filePath)
			}

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
					if (folderView.multiSelectMode)
						folderView.toggleSelected(filePath);
					else if (fileIsDir)
						folderView.openChild(filePath, fileName);
					else
						mainWindow.openFile(filePath);
				}
				onPressAndHold: {
					if (folderView.multiSelectMode) {
						if (!folderView.isSelected(filePath))
							folderView.toggleSelected(filePath);
						selectionMenu.open();
					} else {
						gridMenu.open();
					}
				}
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
				onOpenRequested: mainWindow.openFile(path)
				onPasteRequested: folderView.startPaste(destFolder)
			}
		}

		MouseArea {
			anchors.fill: parent
			enabled: dirModel.count === 0
			onClicked: emptyFolderMenu.open()
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

	Dialog {
		id: replaceDialog
		title: qsTr("File already exists")
		modal: true
		anchors.centerIn: parent
		onRejected: folderView.resolvePasteConflict(false)

		contentItem: CutieLabel {
			text: qsTr("'%1' already exists here. Replace it or skip this paste?")
				.arg(folderView.pendingPasteSource.split("/").pop())
			wrapMode: Text.Wrap
			width: 250
		}

		footer: DialogButtonBox {
			Button {
				text: qsTr("Skip")
				DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
				onClicked: {
					folderView.resolvePasteConflict(false);
				}
			}
			Button {
				text: qsTr("Replace")
				DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole
				onClicked: {
					folderView.resolvePasteConflict(true);
				}
			}
		}
	}
}
