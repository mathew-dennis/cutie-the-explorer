#pragma once

#include <QObject>
#include <QString>
#include <QThread>

// The background worker that handles the actual IO operations.
class FileWorker : public QObject
{
	Q_OBJECT

public:
	FileWorker(const QString &src, const QString &dest, bool isMove);

public Q_SLOTS:
	void process();

Q_SIGNALS:
	// Emits progress metrics. Sizes are in bytes so QML can calculate MBs.
	void progress(qint64 bytesCopied, qint64 totalBytes, int filesCopied, int totalFiles);
	void finished(bool success, const QString &message);

private:
	void calculateTotals(const QString &path);
	bool copyRecursively(const QString &src, const QString &dest);
	bool copyFileChunked(const QString &src, const QString &dest);

	QString m_src;
	QString m_dest;
	bool m_isMove;

	qint64 m_totalBytes = 0;
	qint64 m_copiedBytes = 0;
	int m_totalFiles = 0;
	int m_copiedFiles = 0;
};

// File-level operations backing the Cut/Copy/Paste/Rename actions.
// Operations are now threaded and emit progress signals for the UI.
class FileOperations : public QObject
{
	Q_OBJECT

public:
	explicit FileOperations(QObject *parent = nullptr);

	// Copies sourcePath (file or directory, recursively) into destDir.
	Q_INVOKABLE bool copyPath(const QString &sourcePath, const QString &destDir);

	// Moves sourcePath into destDir. Tries an atomic rename first (same
	// filesystem); falls back to copy-then-delete across filesystems, e.g.
	// internal storage -> SD card.
	Q_INVOKABLE bool movePath(const QString &sourcePath, const QString &destDir);

	// Renames path in place to newName (no path separators allowed).
	Q_INVOKABLE bool renamePath(const QString &path, const QString &newName);
	Q_INVOKABLE bool deletePath(const QString &path);
	
	// Number of entries directly inside path (not recursive), for the
	// "N items" subtitle on folder rows. Returns -1 if path can't be read.
	Q_INVOKABLE int entryCount(const QString &path) const;

Q_SIGNALS:
	void operationFailed(const QString &message);
	
	// UI Progress Signals for the bottom info bar
	void operationStarted();
	void operationProgress(qint64 bytesCopied, qint64 totalBytes, int filesCopied, int totalFiles);
	void operationFinished(bool success, const QString &message);

private:
	bool startWorker(const QString &sourcePath, const QString &destDir, bool isMove);
	bool isSubdirectory(const QString &sourcePath, const QString &destDir) const;

	bool m_busy = false;
};
