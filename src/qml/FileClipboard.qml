pragma Singleton
import QtQuick

// Registered as the CutieExplorer.FileClipboard singleton in main.cpp.
// The URL-based qmlRegisterSingletonType() overload in main.cpp requires
// this pragma to be present, or the engine refuses to load the type.
// Just holds cut/copy state - the actual file move/copy happens in
// FileOperations (C++) when something is pasted.
QtObject {
	id: clipboard

	property var sourcePaths: []
	property string mode: ""          // "cut" | "copy" | ""
	readonly property bool hasContent: sourcePaths.length > 0

	function cut(path) {
		clipboard.cutMany([path]);
	}

	function copy(path) {
		clipboard.copyMany([path]);
	}

	function cutMany(paths) {
		clipboard.sourcePaths = paths.slice();
		clipboard.mode = "cut";
	}

	function copyMany(paths) {
		clipboard.sourcePaths = paths.slice();
		clipboard.mode = "copy";
	}

	function clear() {
		clipboard.sourcePaths = [];
		clipboard.mode = "";
	}
}
