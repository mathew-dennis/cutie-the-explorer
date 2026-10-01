import Cutie
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "Formatting.js" as Formatting

Dialog {
	id: propertiesDialog
	title: qsTr("Properties")
	modal: true
	standardButtons: Dialog.Ok
	anchors.centerIn: parent
	width: 300

	property string fileName: ""
	property string filePath: ""
	property bool fileIsDir: false
	property real fileSize: 0
	property var fileModified: undefined

	contentItem: ColumnLayout {
		spacing: 10

		CutieLabel {
			text: propertiesDialog.fileName
			font.bold: true
			font.pixelSize: 16
			Layout.fillWidth: true
			elide: Text.ElideMiddle
		}
		CutieLabel {
			text: qsTr("Type: %1").arg(propertiesDialog.fileIsDir ? qsTr("Folder") : qsTr("File"))
		}
		CutieLabel {
			text: qsTr("Location: %1").arg(propertiesDialog.filePath)
			wrapMode: Text.WrapAnywhere
			Layout.fillWidth: true
		}
		CutieLabel {
			visible: !propertiesDialog.fileIsDir
			text: qsTr("Size: %1").arg(Formatting.humanSize(propertiesDialog.fileSize))
		}
		CutieLabel {
			visible: Formatting.formatDate(propertiesDialog.fileModified) !== ""
			text: qsTr("Modified: %1").arg(Formatting.formatDate(propertiesDialog.fileModified))
		}
	}
}
