#include "recentfiles.h"

#include <QCoreApplication>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QStandardPaths>
#include <algorithm>

namespace {
constexpr int kMaximumEntries = 20;

QString recentFilesPath()
{
	return QDir(QStandardPaths::writableLocation(QStandardPaths::AppDataLocation))
		.filePath(QStringLiteral("recent-files.json"));
}

QVariantMap makeEntry(const QString &path, const QDateTime &activityTime)
{
	return {
		{QStringLiteral("path"), path},
		{QStringLiteral("name"), QFileInfo(path).fileName()},
		{QStringLiteral("activityTime"), activityTime},
	};
}
}

RecentFiles::RecentFiles(QObject *parent)
	: QObject(parent)
{
	load();
	connect(QCoreApplication::instance(), &QCoreApplication::aboutToQuit,
		this, &RecentFiles::save);
}

RecentFiles::~RecentFiles()
{
	if (m_scanner && m_scanner->isRunning())
		m_scanner->wait();
}

QVariantList RecentFiles::entries() const
{
	return m_entries;
}

void RecentFiles::logOpen(const QString &path)
{
	addEntry(path, QDateTime::currentDateTime());
}

void RecentFiles::scanFolders(const QStringList &folders)
{
	if (m_scanner)
		return;

	QDateTime cutoff;
	for (const QVariant &value : m_entries) {
		const QDateTime time = value.toMap().value(QStringLiteral("activityTime")).toDateTime();
		if (time > cutoff)
			cutoff = time;
	}

	m_scanner = new RecentFileScanThread(folders, cutoff, this);
	connect(m_scanner, &RecentFileScanThread::scanFinished,
		this, &RecentFiles::mergeScanResults);
	connect(m_scanner, &QThread::finished, this, [this]() {
		m_scanner = nullptr;
	});
	m_scanner->start();
}

void RecentFiles::mergeScanResults(const QVariantList &found)
{
	bool changed = false;
	for (const QVariant &value : found) {
		const QVariantMap item = value.toMap();
		const QString path = item.value(QStringLiteral("path")).toString();
		const QDateTime activityTime = item.value(QStringLiteral("activityTime")).toDateTime();
		bool alreadyPresent = false;
		for (const QVariant &existing : m_entries) {
			if (existing.toMap().value(QStringLiteral("path")).toString() == path) {
				alreadyPresent = true;
				break;
			}
		}
		if (!alreadyPresent) {
			m_entries.append(makeEntry(path, activityTime));
			changed = true;
		}
	}

	if (changed) {
		trimEntries();
		Q_EMIT entriesChanged();
	}
}

void RecentFiles::load()
{
	QFile file(recentFilesPath());
	if (!file.open(QIODevice::ReadOnly))
		return;

	const QJsonDocument document = QJsonDocument::fromJson(file.readAll());
	if (!document.isArray())
		return;

	for (const QJsonValue &value : document.array()) {
		if (!value.isObject())
			continue;
		const QJsonObject object = value.toObject();
		const QString path = object.value(QStringLiteral("path")).toString();
		const QDateTime activityTime = QDateTime::fromString(
			object.value(QStringLiteral("activityTime")).toString(), Qt::ISODateWithMs);
		if (!path.isEmpty() && activityTime.isValid() && QFileInfo::exists(path))
			m_entries.append(makeEntry(path, activityTime));
	}
	trimEntries();
}

void RecentFiles::save() const
{
	const QString path = recentFilesPath();
	if (!QDir().mkpath(QFileInfo(path).absolutePath()))
		return;

	QJsonArray array;
	for (const QVariant &value : m_entries) {
		const QVariantMap item = value.toMap();
		QJsonObject object;
		object.insert(QStringLiteral("path"), item.value(QStringLiteral("path")).toString());
		object.insert(QStringLiteral("activityTime"),
			item.value(QStringLiteral("activityTime")).toDateTime().toString(Qt::ISODateWithMs));
		array.append(object);
	}

	QFile file(path);
	if (file.open(QIODevice::WriteOnly | QIODevice::Truncate))
		file.write(QJsonDocument(array).toJson(QJsonDocument::Indented));
}

void RecentFiles::addEntry(const QString &path, const QDateTime &activityTime)
{
	for (qsizetype i = m_entries.size() - 1; i >= 0; --i) {
		if (m_entries.at(i).toMap().value(QStringLiteral("path")).toString() == path)
			m_entries.removeAt(i);
	}
	m_entries.prepend(makeEntry(path, activityTime));
	trimEntries();
	Q_EMIT entriesChanged();
}

void RecentFiles::trimEntries()
{
	std::sort(m_entries.begin(), m_entries.end(), [](const QVariant &left, const QVariant &right) {
		return left.toMap().value(QStringLiteral("activityTime")).toDateTime()
			> right.toMap().value(QStringLiteral("activityTime")).toDateTime();
	});
	while (m_entries.size() > kMaximumEntries)
		m_entries.removeLast();
}

RecentFileScanThread::RecentFileScanThread(const QStringList &folders,
	const QDateTime &cutoff, QObject *parent)
	: QThread(parent), m_folders(folders), m_cutoff(cutoff)
{
}

void RecentFileScanThread::run()
{
	QVariantList found;
	for (const QString &folder : m_folders) {
		QDir root(folder);
		if (!root.exists())
			continue;

		const auto addRecentFiles = [this, &found](const QFileInfoList &files) {
			for (const QFileInfo &file : files) {
				const QDateTime modified = file.lastModified();
				if (file.isFile() && modified > m_cutoff)
					found.append(makeEntry(file.absoluteFilePath(), modified));
			}
		};

		addRecentFiles(root.entryInfoList(QDir::Files | QDir::NoDotAndDotDot));
		const QFileInfoList subfolders = root.entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot);
		for (const QFileInfo &subfolder : subfolders) {
			QDir child(subfolder.absoluteFilePath());
			addRecentFiles(child.entryInfoList(QDir::Files | QDir::NoDotAndDotDot));
		}
	}
	Q_EMIT scanFinished(found);
}
