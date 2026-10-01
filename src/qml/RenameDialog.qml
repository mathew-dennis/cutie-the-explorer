import CutieExplorer
import QtQuick
import QtQuick.Controls

Dialog {
	id: renameDialog
	title: qsTr("Rename")
	modal: true
	standardButtons: Dialog.Ok | Dialog.Cancel
	anchors.centerIn: parent
	width: 300

	property string targetPath: ""

	function openFor(currentName, path) {
		renameDialog.targetPath = path;
		nameField.text = currentName;
		renameDialog.open();
		nameField.selectAll();
		nameField.forceActiveFocus();
	}

	onAccepted: {
		if (nameField.text.length > 0)
			FileOperations.renamePath(renameDialog.targetPath, nameField.text);
	}

	contentItem: TextField {
		id: nameField
		selectByMouse: true
	}
}
