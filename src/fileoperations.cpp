#include "fileoperations.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>

// ==========================================
// FileWorker Implementation
// ==========================================

FileWorker::FileWorker(const QString &src, const QString &dest, bool isMove)
	: m_src(src), m_dest(dest), m_isMove(isMove)
{
}

void FileWorker::calculateTotals(const QString &path)
{
	QFileInfo info(path);
	if (info.isDir()) {
		QDir dir(path);
		const auto entries = dir.entryInfoList(QDir::AllEntries | QDir::NoDotAndDotDot);
		for (const QFileInfo &entry : entries) {
			calculateTotals(entry.absoluteFilePath());
		}
	} else {
		m_totalBytes += info.size();
		m_totalFiles++;
	}
}

bool FileWorker::copyFileChunked(const QString &src, const QString &dest)
{
	QFile srcFile(src);
	QFile destFile(dest);

	if (!srcFile.open(QIODevice::ReadOnly))
		return false;
	if (!destFile.open(QIODevice::WriteOnly))
		return false;

	// Copy in 1MB chunks to ensure smooth progress updates for large files
	const qint64 chunkSize = 1024 * 1024;
	QByteArray buffer;

	while (!srcFile.atEnd()) {
		buffer = srcFile.read(chunkSize);
		if (buffer.isEmpty()) break;

		qint64 written = destFile.write(buffer);
		if (written < 0) return false;

		m_copiedBytes += written;
		Q_EMIT progress(m_copiedBytes, m_totalBytes, m_copiedFiles, m_totalFiles);
	}

	// Preserve basic permissions
	destFile.setPermissions(srcFile.permissions());
	
	m_copiedFiles++;
	Q_EMIT progress(m_copiedBytes, m_totalBytes, m_copiedFiles, m_totalFiles);
	return true;
}

bool FileWorker::copyRecursively(const QString &src, const QString &dest)
{
	QFileInfo srcInfo(src);

	if (srcInfo.isDir()) {
		QDir destDir(dest);
		if (!destDir.mkpath(dest))
			return false;

		QDir srcDir(src);
		const auto entries = srcDir.entryList(QDir::AllEntries | QDir::NoDotAndDotDot);
		for (const QString &entry : entries) {
			if (!copyRecursively(srcDir.filePath(entry), destDir.filePath(entry)))
				return false;
		}
		return true;
	}

	if (QFile::exists(dest))
		QFile::remove(dest);

	return copyFileChunked(src, dest);
}

void FileWorker::process()
{
	calculateTotals(m_src);
	
	// Initial progress setup
	Q_EMIT progress(0, m_totalBytes, 0, m_totalFiles);

	QString destPath = QDir(m_dest).filePath(QFileInfo(m_src).fileName());
	bool success = true;

	if (m_isMove) {
		QDir dir;
		// Try atomic same-filesystem rename first
		if (dir.rename(m_src, destPath)) {
			m_copiedBytes = m_totalBytes;
			m_copiedFiles = m_totalFiles;
			Q_EMIT progress(m_copiedBytes, m_totalBytes, m_copiedFiles, m_totalFiles);
		} else {
			// Fallback to copy-then-delete across filesystems
			success = copyRecursively(m_src, destPath);
			if (success) {
				if (QFileInfo(m_src).isDir())
					QDir(m_src).removeRecursively();
				else
					QFile::remove(m_src);
			}
		}
	} else {
		success = copyRecursively(m_src, destPath);
	}

	Q_EMIT finished(success, success ? "Operation completed successfully" : "Operation failed");
}

// ==========================================
// FileOperations Implementation
// ==========================================

FileOperations::FileOperations(QObject *parent)
	: QObject(parent)
{
}

bool FileOperations::isSubdirectory(const QString &sourcePath, const QString &destDir) const
{
	QFileInfo srcInfo(sourcePath);
	QFileInfo destDirInfo(destDir);
	
	QString srcAbs = srcInfo.absoluteFilePath();
	QString destAbs = QDir(destDirInfo.absoluteFilePath()).filePath(srcInfo.fileName());

	// Prevent copying /folder into /folder/subfolder, which causes infinite recursion
	if (destAbs.startsWith(srcAbs + QDir::separator()) || destAbs == srcAbs) {
		return true;
	}
	return false;
}

bool FileOperations::startWorker(const QString &sourcePath, const QString &destDir, bool isMove)
{
	if (m_busy) {
		Q_EMIT operationFailed(tr("An operation is already in progress."));
		return false;
	}

	QFileInfo sourceInfo(sourcePath);
	if (!sourceInfo.exists()) {
		Q_EMIT operationFailed(tr("%1 no longer exists").arg(sourcePath));
		return false;
	}

	if (isSubdirectory(sourcePath, destDir)) {
		Q_EMIT operationFailed(tr("Cannot paste a folder into itself."));
		return false;
	}

	const QString destPath = QDir(destDir).filePath(sourceInfo.fileName());
	if (destPath == sourcePath) {
		Q_EMIT operationFailed(tr("Source and destination are the same"));
		return false;
	}

	m_busy = true;
	Q_EMIT operationStarted();

	QThread *thread = new QThread;
	FileWorker *worker = new FileWorker(sourcePath, destDir, isMove);
	worker->moveToThread(thread);

    // Wire up thread lifecycle and progress signals
	connect(thread, &QThread::started, worker, &FileWorker::process);
    
	connect(worker, &FileWorker::progress, this, &FileOperations::operationProgress);
	
	connect(worker, &FileWorker::finished, this, [this, thread, worker](bool success, const QString &msg) {
		m_busy = false;
		Q_EMIT operationFinished(success, msg);
		if (!success) Q_EMIT operationFailed(msg);
		
		thread->quit();
        thread->wait(); // Safely wait for thread shutdown
		worker->deleteLater();
		thread->deleteLater();
	});

	thread->start();
    return true; // Indicates the process successfully started
}

bool FileOperations::copyPath(const QString &sourcePath, const QString &destDir)
{
	return startWorker(sourcePath, destDir, false);
}

bool FileOperations::movePath(const QString &sourcePath, const QString &destDir)
{
	return startWorker(sourcePath, destDir, true);
}

bool FileOperations::renamePath(const QString &path, const QString &newName)
{
	if (newName.isEmpty() || newName.contains(QLatin1Char('/'))) {
		Q_EMIT operationFailed(tr("Invalid name"));
		return false;
	}

	QFileInfo info(path);
	const QString destPath = info.absoluteDir().filePath(newName);

	QDir dir;
	if (!dir.rename(path, destPath)) {
		Q_EMIT operationFailed(tr("Could not rename to %1").arg(newName));
		return false;
	}
	return true;
}

bool FileOperations::deletePath(const QString &path)
{
	QFileInfo info(path);
	if (!info.exists()) {
		Q_EMIT operationFailed(tr("Item no longer exists: %1").arg(path));
		return false;
	}

	bool success = false;
	if (info.isDir()) {
		success = QDir(path).removeRecursively();
	} else {
		success = QFile::remove(path);
	}

	if (!success) {
		Q_EMIT operationFailed(tr("Could not delete %1").arg(path));
	}
	
	return success;
}

int FileOperations::entryCount(const QString &path) const
{
	QDir dir(path);
	if (!dir.exists())
		return -1;
	return dir.entryList(QDir::AllEntries | QDir::NoDotAndDotDot).count();
}
