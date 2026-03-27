#ifndef SYSTEMDATA_H
#define SYSTEMDATA_H

#include <QObject>
#include <QTimer>
#include <QVariantList>
#include <QSerialPort>
#include <QUdpSocket>

/**
 * @brief SystemData 类是 QML 和 C++ 后端之间的桥梁。
 * 它可以从串口接收外部传感器数据，并通过属性和信号将数据传递给 QML 界面。
 */
class SystemData : public QObject
{
    Q_OBJECT

    // --- 定义暴露给 QML 的属性 ---
    // Q_PROPERTY 宏使得 QML 可以像访问 JavaScript 对象属性一样访问这些 C++ 成员
    // NOTIFY 关键字指定了当属性值变化时发射的信号，这对于 QML 的数据绑定至关重要

    // PH值
    Q_PROPERTY(double phValue READ phValue NOTIFY phValueChanged)
    
    // 溶解氧
    Q_PROPERTY(double dissolvedOxygen READ dissolvedOxygen NOTIFY dissolvedOxygenChanged)
    
    // 浊度
    Q_PROPERTY(double turbidity READ turbidity NOTIFY turbidityChanged)

    // 无人机运行状态
    Q_PROPERTY(bool droneRunning READ droneRunning WRITE setDroneRunning NOTIFY droneRunningChanged)
    
    // 无人船运行状态
    Q_PROPERTY(bool shipRunning READ shipRunning WRITE setShipRunning NOTIFY shipRunningChanged)
    
    // 无人机传感器数据列表 (对应 QML 中的 variant/list)
    Q_PROPERTY(QVariantList droneData READ droneData NOTIFY droneDataChanged)
    
    // 无人船传感器数据列表
    Q_PROPERTY(QVariantList shipData READ shipData NOTIFY shipDataChanged)

    // 无人机遥测参数
    Q_PROPERTY(QVariantMap droneTelemetry READ droneTelemetry NOTIFY droneTelemetryChanged)
    
    // 无人船遥测参数
    Q_PROPERTY(QVariantMap shipTelemetry READ shipTelemetry NOTIFY shipTelemetryChanged)

public:
    explicit SystemData(QObject *parent = nullptr);
    ~SystemData();

    // --- Getter 方法 ---
    double phValue() const { return m_phValue; }
    double dissolvedOxygen() const { return m_dissolvedOxygen; }
    double turbidity() const { return m_turbidity; }
    bool droneRunning() const { return m_droneRunning; }
    bool shipRunning() const { return m_shipRunning; }
    QVariantList droneData() const { return m_droneData; }
    QVariantList shipData() const { return m_shipData; }
    QVariantMap droneTelemetry() const { return m_droneTelemetry; }
    QVariantMap shipTelemetry() const { return m_shipTelemetry; }

    // --- Setter 方法 (Q_INVOKABLE 可选，但通过属性写入通常更好) ---
    Q_INVOKABLE void setDroneRunning(bool running);
    Q_INVOKABLE void setShipRunning(bool running);
    
    // 获取系统中可用的串口列表
    Q_INVOKABLE QStringList getAvailablePorts();

    // 提供给QML调用，用于打开串口
    Q_INVOKABLE bool openSerialPort(const QString &portName, int baudRate = QSerialPort::Baud9600);
    Q_INVOKABLE void closeSerialPort();
    
    // 提供给QML调用，用于发送JSON指令
    Q_INVOKABLE void sendCommand(const QString &device, const QString &action);
    
    // 提供给QML调用，用于打开UDP监听
    Q_INVOKABLE bool openUdpPort(int port = 8080);
    Q_INVOKABLE void closeUdpPort();
    
    // 确认报警已读
    Q_INVOKABLE void acknowledgeAlarm();

    // 新增：环境气象数据属性
    Q_PROPERTY(double temperature READ temperature NOTIFY temperatureChanged)
    Q_PROPERTY(double humidity READ humidity NOTIFY humidityChanged)
    Q_PROPERTY(double windSpeed READ windSpeed NOTIFY windSpeedChanged)
    Q_PROPERTY(QString windDirection READ windDirection NOTIFY windDirectionChanged)
    
    // 报警状态
    Q_PROPERTY(bool hasAlarm READ hasAlarm NOTIFY alarmStatusChanged)
    Q_PROPERTY(QString currentAlarmMsg READ currentAlarmMsg NOTIFY alarmStatusChanged)
    
    // 串口/UDP状态
    Q_PROPERTY(bool isSerialOpen READ isSerialOpen NOTIFY serialStatusChanged)
    Q_PROPERTY(QString currentPortName READ currentPortName NOTIFY serialStatusChanged)
    Q_PROPERTY(bool isUdpOpen READ isUdpOpen NOTIFY udpStatusChanged)
    Q_PROPERTY(int currentUdpPort READ currentUdpPort NOTIFY udpStatusChanged)

public:
    double temperature() const { return m_temperature; }
    double humidity() const { return m_humidity; }
    double windSpeed() const { return m_windSpeed; }
    QString windDirection() const { return m_windDirection; }
    
    bool hasAlarm() const { return m_hasAlarm && !m_alarmAcknowledged; }
    QString currentAlarmMsg() const { return m_currentAlarmMsg; }
    
    bool isSerialOpen() const;
    QString currentPortName() const;
    
    bool isUdpOpen() const;
    int currentUdpPort() const;

signals:
    // --- 属性变化信号 ---
    void phValueChanged();
    void dissolvedOxygenChanged();
    void turbidityChanged();
    void droneRunningChanged();
    void shipRunningChanged();
    void droneDataChanged();
    void shipDataChanged();
    void droneTelemetryChanged();
    void shipTelemetryChanged();
    
    void temperatureChanged();
    void humidityChanged();
    void windSpeedChanged();
    void windDirectionChanged();
    
    void alarmStatusChanged();
    void serialStatusChanged();
    void udpStatusChanged();

    // --- 自定义信号 ---
    // 发送日志消息给 QML 显示
    void logMessage(const QString &msg);

private slots:
    // 内部模拟数据更新的槽函数
    void onSimulateDataUpdate();
    // 串口读取数据的槽函数
    void onReadyRead();
    // UDP读取数据的槽函数
    void onUdpReadyRead();

private:
    void checkAlarms(); // 检查各项数据是否触发报警
    void sendAlarmToSerial(const QString &msg); // 向串口发送报警数据
    void processJsonData(QByteArray &buffer); // 解析JSON数据的通用函数

    double m_phValue;
    double m_dissolvedOxygen;
    double m_turbidity;
    bool m_droneRunning;
    bool m_shipRunning;
    QVariantList m_droneData;
    QVariantList m_shipData;
    QVariantMap m_droneTelemetry;
    QVariantMap m_shipTelemetry;
    
    double m_temperature;
    double m_humidity;
    double m_windSpeed;
    QString m_windDirection;

    bool m_hasAlarm;
    bool m_alarmAcknowledged;
    QString m_currentAlarmMsg;

    QTimer *m_timer; // 用于定时模拟数据更新
    QSerialPort *m_serialPort; // 串口对象
    QUdpSocket *m_udpSocket; // UDP socket对象
    int m_currentUdpPort; // 当前监听的UDP端口
    QByteArray m_serialBuffer; // 串口数据缓存
};

#endif // SYSTEMDATA_H
