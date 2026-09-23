cmake_minimum_required(VERSION 3.16)
project(cutie-explorer VERSION 1.0 LANGUAGES CXX)

set(CMAKE_INCLUDE_CURRENT_DIR ON)

find_package(Qt6 REQUIRED COMPONENTS Core Quick Qml LinguistTools)

qt_standard_project_setup()

set(cutie-explorer_SOURCES
	src/main.cpp
	src/drivemanager.cpp
	src/fileoperations.cpp
	src/recentfiles.h
	src/recentfiles.cpp
)

qt_add_resources(APP_RESOURCES
	${CMAKE_SOURCE_DIR}/src/qml/qml.qrc)

qt_add_executable(cutie-explorer ${cutie-explorer_SOURCES} ${APP_RESOURCES})

target_include_directories(cutie-explorer PUBLIC src)

target_link_libraries(cutie-explorer PUBLIC Qt::Core Qt::Quick Qt::Qml)

install(TARGETS cutie-explorer RUNTIME DESTINATION "${CMAKE_INSTALL_BINDIR}")
install(FILES cutie-explorer.desktop DESTINATION "${CMAKE_INSTALL_DATADIR}/applications")
install(FILES cutie-explorer.svg DESTINATION "${CMAKE_INSTALL_DATADIR}/icons/hicolor/scalable/apps")
