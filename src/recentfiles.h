#pragma once

#include <QObject>
#include <QDateTime>
#include <QStringList>
#include <QThread>
#include <QVariantList>

class RecentFileScanThread;

class RecentFiles : public QObject
{
	Q_OBJECT
	Q_PROPERTY(QVariantList entries READ entries NOTIFY entriesChanged)

public:
	explicit RecentFiles(QObject *parent = nullptr);
	~RecentFiles() override;

	QVariantList entries() const;
	Q_INVOKABLE void logOpen(const QString &path);
	Q_INVOKABLE void scanFolders(const QStringList &folders);

Q_SIGNALS:
	void entriesChanged();

private Q_SLOTS:
	void mergeScanResults(const QVariantList &found);

private:
	void load();
	void save() const;
	void addEntry(const QString &path, const QDateTime &activityTime);
	void trimEntries();

	QVariantList m_entries;
	RecentFileScanThread *m_scanner = nullptr;
};

class RecentFileScanThread : public QThread
{
	Q_OBJECT

public:
	RecentFileScanThread(const QStringList &folders, const QDateTime &cutoff,
		QObject *parent = nullptr);

Q_SIGNALS:
	void scanFinished(const QVariantList &found);

protected:
	void run() override;

private:
	QStringList m_folders;
	QDateTime m_cutoff;
};
