#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QtGui/QGuiApplication>
#include <QtQml/QQmlContext>
#include <QtQml/QQmlEngine>
#include <QtQuick/QQuickItem>
#include <QtQuick/QQuickView>
#include <QTranslator>

#include "drivemanager.h"
#include "fileoperations.h"
#include "recentfiles.h"

int main(int argc, char *argv[])
{
#if QT_VERSION < QT_VERSION_CHECK(6, 0, 0)
	QCoreApplication::setAttribute(Qt::AA_EnableHighDpiScaling);
#endif
	QGuiApplication app(argc, argv);
	QString locale = QLocale::system().name();
	QTranslator translator;
	(void)translator.load(QString(":/i18n/cutie-explorer_") + locale);
	app.installTranslator(&translator);

	// DriveManager/FileOperations are plain C++ singletons - exposed the
	// same way BatteryHistory/PowerSaving are in Cutie.Battery, so QML can
	// reach them as `DriveManager.drives` / `FileOperations.copyPath(...)`
	// without instantiating anything.
	qmlRegisterSingletonType<DriveManager>("CutieExplorer", 1, 0, "DriveManager",
		[](QQmlEngine *, QJSEngine *) -> QObject * { return new DriveManager(); });

	qmlRegisterSingletonType<FileOperations>("CutieExplorer", 1, 0, "FileOperations",
		[](QQmlEngine *, QJSEngine *) -> QObject * { return new FileOperations(); });

	qmlRegisterSingletonType<RecentFiles>("CutieExplorer", 1, 0, "RecentFiles",
		[](QQmlEngine *, QJSEngine *) -> QObject * { return new RecentFiles(); });

	// FileClipboard only holds cut/copy state - plain QML is enough, so it's
	// registered straight from FileClipboard.qml instead of a C++ class.
	qmlRegisterSingletonType(QUrl("qrc:/FileClipboard.qml"), "CutieExplorer", 1, 0, "FileClipboard");

	QQmlApplicationEngine engine;
	const QUrl url(QStringLiteral("qrc:/main.qml"));
	QObject::connect(
		&engine, &QQmlApplicationEngine::objectCreated, &app,
		[url](QObject *obj, const QUrl &objUrl) {
			if (!obj && url == objUrl)
				QCoreApplication::exit(-1);
		},
		Qt::QueuedConnection);
	engine.load(url);
	return app.exec();
}
