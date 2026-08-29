import Cutie
import CutieExplorer
import Qt.labs.platform as Labs
import QtQuick
import "Formatting.js" as Formatting

CutieWindow {
	id: mainWindow
	width: 400
	height: 800
	visible: true
	title: qsTr("Files")

	property var folderComponent: Qt.createComponent("FolderView.qml")

	// State properties to track background file operations
	property bool isTransferring: false
	property real transferBytesCopied: 0
	property real transferBytesTotal: 0
	property int transferFilesCopied: 0
	property int transferFilesTotal: 0

	// Quick-access shortcuts - the standard XDG user directories
	property var places: [
		{ text: qsTr("Home"), icon: "user-home-symbolic", path: Formatting.urlToPath(Labs.StandardPaths.writableLocation(Labs.StandardPaths.HomeLocation)) },
		{ text: qsTr("Desktop"), icon: "user-desktop-symbolic", path: Formatting.urlToPath(Labs.StandardPaths.writableLocation(Labs.StandardPaths.DesktopLocation)) },
		{ text: qsTr("Documents"), icon: "folder-documents-symbolic", path: Formatting.urlToPath(Labs.StandardPaths.writableLocation(Labs.StandardPaths.DocumentsLocation)) },
		{ text: qsTr("Downloads"), icon: "folder-download-symbolic", path: Formatting.urlToPath(Labs.StandardPaths.writableLocation(Labs.StandardPaths.DownloadLocation)) },
		{ text: qsTr("Pictures"), icon: "folder-pictures-symbolic", path: Formatting.urlToPath(Labs.StandardPaths.writableLocation(Labs.StandardPaths.PicturesLocation)) },
		{ text: qsTr("Music"), icon: "folder-music-symbolic", path: Formatting.urlToPath(Labs.StandardPaths.writableLocation(Labs.StandardPaths.MusicLocation)) },
		{ text: qsTr("Videos"), icon: "folder-videos-symbolic", path: Formatting.urlToPath(Labs.StandardPaths.writableLocation(Labs.StandardPaths.MoviesLocation)) }
	]

	function openFolder(path, label) {
		if (mainWindow.folderComponent.status === Component.Ready) {
			mainWindow.pageStack.push(mainWindow.folderComponent,
				{ crumbs: [{ label: label, path: path }] });
		}
	}

	// Listen to C++ background worker signals
	Connections {
		target: FileOperations
		
		function onOperationStarted() {
			mainWindow.transferBytesCopied = 0;
			mainWindow.transferBytesTotal = 0;
			mainWindow.transferFilesCopied = 0;
			mainWindow.transferFilesTotal = 0;
			mainWindow.isTransferring = true;
		}
		
		function onOperationProgress(bytesCopied, totalBytes, filesCopied, totalFiles) {
			mainWindow.transferBytesCopied = bytesCopied;
			mainWindow.transferBytesTotal = totalBytes;
			mainWindow.transferFilesCopied = filesCopied;
			mainWindow.transferFilesTotal = totalFiles;
		}
		
		function onOperationFinished(success, message) {
			mainWindow.isTransferring = false;
			// Optional: Trigger a Cutie toast notification here if success === false
		}
	}

	initialPage: CutiePage {
		width: mainWindow.width
		height: mainWindow.height

		Flickable {
			anchors.fill: parent
			contentHeight: column.height

			Column {
				id: column
				width: parent.width

				CutiePageHeader {
					title: mainWindow.title
					width: parent.width
				}

				// ── Places (Home, Desktop, ...) - 2 columns ─────────────
				Grid {
					id: placesGrid
					width: column.width
					columns: 2

					Repeater {
						model: mainWindow.places
						delegate: CutieListItem {
							width: placesGrid.width / 2
							text: mainWindow.places[index]["text"]
							icon.name: mainWindow.places[index]["icon"]
							icon.color: Atmosphere.textColor
							onClicked: mainWindow.openFolder(
								mainWindow.places[index]["path"],
								mainWindow.places[index]["text"]);
						}
					}
				}

				// ── Drives ──────────────────────────────────────────────
				// Populated by DriveManager: Root and (if present)
				// Userdata first, then anything actually mounted under
				// /media, /run/media or /mnt.
				CutieLabel {
					text: qsTr("Drives")
					visible: DriveManager.drives.length > 0
					leftPadding: 20
					topPadding: 20
					bottomPadding: 6
					font.pixelSize: 13
					font.bold: true
					opacity: 0.85
				}

				Repeater {
					model: DriveManager.drives

					delegate: Item {
						width: column.width
						height: driveColumn.height + 20

						Column {
							id: driveColumn
							x: 20
							y: 10
							width: parent.width - 40
							spacing: 6

							Row {
								spacing: 10

								Image {
									anchors.verticalCenter: parent.verticalCenter
									source: "image://theme/drive-removable-media-symbolic"
									sourceSize.width: 20
									sourceSize.height: 20
								}
								CutieLabel {
									anchors.verticalCenter: parent.verticalCenter
									text: modelData.name
									color: Atmosphere.textColor
								}
							}

							// Usage bar - white fill over a dim track,
							// width proportional to used/total space.
							Rectangle {
								width: parent.width
								height: 6
								radius: 3
								color:  Atmosphere.primaryAlphaColor
								opacity: 1

								Rectangle {
									height: parent.height
									radius: 3
									color: Atmosphere.textColor
									width: parent.width * (modelData.totalBytes > 0
										? (modelData.totalBytes - modelData.freeBytes) / modelData.totalBytes
										: 0)
								}
							}

							CutieLabel {
								text: qsTr("%1 free of %2")
									.arg(Formatting.humanSize(modelData.freeBytes))
									.arg(Formatting.humanSize(modelData.totalBytes))
								opacity: 0.85
								font.pixelSize: 12
							}
						}

						MouseArea {
							anchors.fill: parent
							onClicked: mainWindow.openFolder(modelData.path, modelData.name)
						}
					}
				}

				Item { width: 1; height: 16 }
			}
		}
	}

	// ── Global Progress Info Card ──────────────────────────────────────────
	// Overlays on top of the UI at the bottom of the window
	Rectangle {
		id: progressCard
		visible: mainWindow.isTransferring
		
		anchors.bottom: parent.bottom
		anchors.bottomMargin: 24
		anchors.left: parent.left
		anchors.right: parent.right
		anchors.margins: 16
		
		height: progressColumn.height + 24
		radius: 12
		
		color: Atmosphere.secondaryAlphaColor
		border.color: Atmosphere.primaryAlphaColor
		border.width: 1

		Column {
			id: progressColumn
			anchors.centerIn: parent
			width: parent.width - 32
			spacing: 10

			CutieLabel {
				text: qsTr("Transferring %1 of %2 items")
					.arg(mainWindow.transferFilesCopied)
					.arg(mainWindow.transferFilesTotal)
				font.bold: true
				color: Atmosphere.textColor
			}

			// Reuses the styling of the DriveManager usage bar
			Rectangle {
				width: parent.width
				height: 6
				radius: 3
				color: Atmosphere.primaryAlphaColor
				opacity: 1

				Rectangle {
					height: parent.height
					radius: 3
					color: Atmosphere.textColor
					// Calculate width dynamically, guarding against division by zero
					width: mainWindow.transferBytesTotal > 0 
						? parent.width * (mainWindow.transferBytesCopied / mainWindow.transferBytesTotal) 
						: 0
				}
			}

			// Size summary: e.g. "1.2MB / 50MB"
			CutieLabel {
				text: qsTr("%1 / %2")
					.arg(Formatting.humanSize(mainWindow.transferBytesCopied))
					.arg(Formatting.humanSize(mainWindow.transferBytesTotal))
				opacity: 0.85
				font.pixelSize: 12
			}
		}
	}
}