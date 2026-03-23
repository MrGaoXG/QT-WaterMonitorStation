#include <QApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include "SystemData.h"

int main(int argc, char *argv[])
{
#if QT_VERSION < QT_VERSION_CHECK(6, 0, 0)
    QCoreApplication::setAttribute(Qt::AA_EnableHighDpiScaling);
#endif
    // 使用 QApplication 代替 QGuiApplication，因为 QtCharts 依赖于 QtWidgets 模块
    QApplication app(argc, argv);

    // 实例化后端数据管理类
    SystemData systemData;

    QQmlApplicationEngine engine;

    // 将 C++ 对象注册为 QML 上下文属性，使得 QML 可以全局访问 systemData
    engine.rootContext()->setContextProperty("systemData", &systemData);

    const QUrl url(QStringLiteral("qrc:/main.qml"));
    QObject::connect(
        &engine,
        &QQmlApplicationEngine::objectCreated,
        &app,
        [url](QObject *obj, const QUrl &objUrl) {
            if (!obj && url == objUrl) {
                qCritical() << "Error: Could not load QML file from" << url; // 如果失败会打印
                QCoreApplication::exit(-1);
            } else {
                qDebug() << "Successfully loaded QML!"; // 如果成功会打印
            }
        },
        Qt::QueuedConnection);

    engine.load(url);

    return QCoreApplication::exec();
}
