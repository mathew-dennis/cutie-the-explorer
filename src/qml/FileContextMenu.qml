import Cutie
import CutieExplorer
import QtQuick

// The 6-action context menu (Cut/Copy/Paste/Rename/Properties/Delete) for a
// single file or folder entry. Shared by the list and grid delegates so
// the action set only lives in one place.
//
// "Paste" always targets currentFolder - the folder being browsed - not
// whatever entry the menu happened to be opened on, matching how Explorer's
// own per-item context menu behaves.
CutieMenu {
	id: fileMenu

	property string currentFolder: ""
	property string targetName: ""
	property string targetPath: ""
	property bool targetIsDir: false
	property real targetSize: 0
	property var targetModified: undefined

	signal renameRequested(string name, string path)
	signal propertiesRequested(string name, string path, bool isDir, real size, var modified)
	signal deleteRequested(string name, string path)

	CutieMenuItem {
		text: qsTr("Cut")
		onTriggered: FileClipboard.cut(fileMenu.targetPath)
	}
	CutieMenuItem {
		text: qsTr("Copy")
		onTriggered: FileClipboard.copy(fileMenu.targetPath)
	}
	CutieMenuItem {
		text: qsTr("Paste")
		enabled: FileClipboard.hasContent
		onTriggered: {
			if (FileClipboard.mode === "cut")
				FileOperations.movePath(FileClipboard.sourcePath, fileMenu.currentFolder);
			else
				FileOperations.copyPath(FileClipboard.sourcePath, fileMenu.currentFolder);
			FileClipboard.clear();
		}
	}
	CutieMenuItem {
		text: qsTr("Delete")
		onTriggered: fileMenu.deleteRequested(fileMenu.targetName, fileMenu.targetPath)
	}
	CutieMenuItem {
		text: qsTr("Rename")
		onTriggered: fileMenu.renameRequested(fileMenu.targetName, fileMenu.targetPath)
	}
	CutieMenuItem {
		text: qsTr("Properties")
		onTriggered: fileMenu.propertiesRequested(fileMenu.targetName, fileMenu.targetPath,
			fileMenu.targetIsDir, fileMenu.targetSize, fileMenu.targetModified)
	}
}
