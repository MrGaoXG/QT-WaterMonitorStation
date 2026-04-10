#include "SystemData.h"
#include <QRandomGenerator>
#include <QDebug>
#include <QDateTime>
#include <QJsonDocument>
#include <QJsonObject>
#include <QStringConverter>
#include <QSerialPortInfo>

SystemData::SystemData(QObject *parent) : QObject(parent),
    m_phValue(7.40),
    m_dissolvedOxygen(8.80),
    m_turbidity(2.60),
    m_droneRunning(false),
    m_shipRunning(false),
    m_temperature(26.5),
    m_humidity(45.0),
    m_windSpeed(3.2),
    m_windDirection("东北 NE"),
    m_hasAlarm(false),
    m_alarmAcknowledged(false),
    m_currentUdpPort(8080)
{
    // 初始化串口对象
    m_serialPort = new QSerialPort(this);
    connect(m_serialPort, &QSerialPort::readyRead, this, &SystemData::onReadyRead);

    // 初始化UDP Socket对象
    m_udpSocket = new QUdpSocket(this);
    connect(m_udpSocket, &QUdpSocket::readyRead, this, &SystemData::onUdpReadyRead);

    // 初始化遥测数据
    m_droneTelemetry = {
        {"battery", 100},
        {"altitude", 0},
        {"speed", 0},
        {"signal", 100}
    };
    m_shipTelemetry = {
        {"battery", 100},
        {"speed", 0},
        {"heading", 0},
        {"signal", 100}
    };

    // 初始化空数据列表 (7个数据点)
    for(int i=0; i<7; ++i) {
        m_droneData.append(0);
        m_shipData.append(0);
    }

    // 设置定时器模拟外部数据输入
    // 在实际项目中，这里可能是初始化串口、建立 TCP 连接等
    m_timer = new QTimer(this);
    connect(m_timer, &QTimer::timeout, this, &SystemData::onSimulateDataUpdate);
    m_timer->start(2000); // 连接定时器槽函数
    connect(m_timer, &QTimer::timeout, this, &SystemData::onSimulateDataUpdate);
    // m_timer->start(2000); // 现在由串口数据驱动，不使用定时器模拟数据了
}

SystemData::~SystemData()
{
    closeSerialPort();
    closeUdpPort();
}

bool SystemData::isSerialOpen() const
{
    return m_serialPort && m_serialPort->isOpen();
}

QString SystemData::currentPortName() const
{
    if (m_serialPort && m_serialPort->isOpen()) {
        return m_serialPort->portName();
    }
    return "";
}

bool SystemData::isUdpOpen() const
{
    return m_udpSocket && m_udpSocket->state() == QUdpSocket::BoundState;
}

int SystemData::currentUdpPort() const
{
    return m_currentUdpPort;
}

QStringList SystemData::getAvailablePorts()
{
    QStringList portList;
    const auto infos = QSerialPortInfo::availablePorts();
    for (const QSerialPortInfo &info : infos) {
        portList << info.portName();
    }
    return portList;
}

bool SystemData::openSerialPort(const QString &portName, int baudRate)
{
    if (m_serialPort->isOpen()) {
        m_serialPort->close();
    }
    
    m_serialPort->setPortName(portName);
    m_serialPort->setBaudRate(baudRate);
    m_serialPort->setDataBits(QSerialPort::Data8);
    m_serialPort->setParity(QSerialPort::NoParity);
    m_serialPort->setStopBits(QSerialPort::OneStop);
    m_serialPort->setFlowControl(QSerialPort::NoFlowControl);

    // 以读写模式打开串口，才能发送指令
    if (m_serialPort->open(QIODevice::ReadWrite)) {
        emit logMessage(QString("串口 %1 已成功打开").arg(portName));
        emit serialStatusChanged();
        return true;
    } else {
        emit logMessage(QString("无法打开串口 %1: %2").arg(portName).arg(m_serialPort->errorString()));
        emit serialStatusChanged();
        return false;
    }
}

void SystemData::closeSerialPort()
{
    if (m_serialPort->isOpen()) {
        m_serialPort->close();
        emit logMessage("串口已手动关闭");
        emit serialStatusChanged();
    }
}

bool SystemData::openUdpPort(int port)
{
    if (m_udpSocket->state() == QUdpSocket::BoundState) {
        m_udpSocket->close();
    }
    
    // 绑定到所有本地网络接口的指定端口，支持广播和多播接收
    if (m_udpSocket->bind(QHostAddress::AnyIPv4, port, QUdpSocket::ShareAddress | QUdpSocket::ReuseAddressHint)) {
        m_currentUdpPort = port;
        emit logMessage(QString("UDP监听已在端口 %1 启动").arg(port));
        emit udpStatusChanged();
        return true;
    } else {
        emit logMessage(QString("无法绑定UDP端口 %1: %2").arg(port).arg(m_udpSocket->errorString()));
        emit udpStatusChanged();
        return false;
    }
}

void SystemData::closeUdpPort()
{
    if (m_udpSocket->state() == QUdpSocket::BoundState) {
        m_udpSocket->close();
        emit logMessage("UDP监听已手动关闭");
        emit udpStatusChanged();
    }
}

void SystemData::sendCommand(const QString &device, const QString &action)
{
    QJsonObject jsonObj;
    jsonObj[device] = action; // device为 "UVA" 或 "USV", action为 "start" 或 "close"

    QJsonDocument doc(jsonObj);
    QByteArray data = doc.toJson(QJsonDocument::Compact) + "\n"; // 压缩格式并追加换行符

    // 优先通过串口发送
    if (m_serialPort->isOpen()) {
        qint64 bytesWritten = m_serialPort->write(data);
        if (bytesWritten == -1) {
            emit logMessage(QString("发送命令失败: %1").arg(m_serialPort->errorString()));
        } else {
            emit logMessage(QString("已通过串口发送控制命令: %1").arg(QString(data).trimmed()));
        }
    } 
    // 如果串口未开，但 UDP 监听正常，则通过 UDP 广播发送 (假定 Python 脚本监听 8081 接收指令并转发给串口)
    else if (m_udpSocket->state() == QUdpSocket::BoundState) {
        qint64 bytesWritten = m_udpSocket->writeDatagram(data, QHostAddress::Broadcast, 8081);
        // 如果需要发给本机，也可以写 QHostAddress::LocalHost
        if (bytesWritten == -1) {
            emit logMessage(QString("UDP发送命令失败: %1").arg(m_udpSocket->errorString()));
        } else {
            emit logMessage(QString("已通过UDP发送控制命令: %1").arg(QString(data).trimmed()));
        }
    } else {
        emit logMessage(QString("发送失败：串口未打开且UDP未绑定"));
    }
}

void SystemData::sendAlarmToSerial(const QString &msg)
{
    QJsonObject jsonObj;
    jsonObj["ALARM"] = msg;
    
    QJsonDocument doc(jsonObj);
    QByteArray data = doc.toJson(QJsonDocument::Compact) + "\n";
    
    if (m_serialPort->isOpen()) {
        m_serialPort->write(data);
        emit logMessage(QString("<font color='red'>[警报已通过串口发送] %1</font>").arg(msg));
    } else if (m_udpSocket->state() == QUdpSocket::BoundState) {
        m_udpSocket->writeDatagram(data, QHostAddress::Broadcast, 8081);
        emit logMessage(QString("<font color='red'>[警报已通过UDP发送] %1</font>").arg(msg));
    }
}

void SystemData::acknowledgeAlarm()
{
    m_alarmAcknowledged = true;
    emit alarmStatusChanged();
}

void SystemData::askAI(const QString &question)
{
    // 创建一个临时的 UDP socket 用来发送 AI 请求
    // 这样做可以绕过 m_udpSocket 是否绑定的限制，确保请求始终能发出去
    QUdpSocket tempSocket;
    QByteArray data = question.toUtf8();
    
    // 发送到 8082 端口供 Python 的 AI 监听线程处理
    qint64 bytes = tempSocket.writeDatagram(data, QHostAddress::LocalHost, 8082);
    
    if (bytes != -1) {
        emit logMessage(QString("<font color='#AAAAAA'>[AI咨询] %1</font>").arg(question));
    } else {
        emit logMessage("<font color='red'>AI咨询发送失败</font>");
    }
}

void SystemData::checkAlarms()
{
    QStringList alarms;
    
    // 1. 水质报警条件
    if (m_phValue < 6.0 || m_phValue > 9.0) alarms << QString("PH值异常 (%.1f)").arg(m_phValue);
    if (m_dissolvedOxygen < 4.0) alarms << QString("溶解氧过低 (%.1f)").arg(m_dissolvedOxygen);
    if (m_turbidity > 5.0) alarms << QString("浊度过高 (%.1f)").arg(m_turbidity); // 新增浊度报警
    
    // 2. 气象报警条件
    if (m_windSpeed > 10.0) alarms << QString("风速过大 (%.1f m/s)").arg(m_windSpeed);
    if (m_temperature > 40.0 || m_temperature < -10.0) alarms << QString("温度极端 (%.1f °C)").arg(m_temperature);
    
    // 3. 设备电量报警条件
    int droneBat = m_droneTelemetry.value("battery").toInt();
    int shipBat = m_shipTelemetry.value("battery").toInt();
    
    if (droneBat > 0 && droneBat < 20) alarms << QString("无人机电量低 (%1%)").arg(droneBat);
    if (shipBat > 0 && shipBat < 20) alarms << QString("无人船电量低 (%1%)").arg(shipBat);
    
    if (!alarms.isEmpty()) {
        QString newAlarmMsg = alarms.join(" | ");
        
        // 只有当有新报警产生，或者之前的报警变了，才重新触发弹窗
        if (!m_hasAlarm || m_currentAlarmMsg != newAlarmMsg) {
            m_currentAlarmMsg = newAlarmMsg;
            m_hasAlarm = true;
            m_alarmAcknowledged = false; // 重置确认状态，强制弹出
            emit alarmStatusChanged();
            
            // 自动向串口发送报警
            sendAlarmToSerial(m_currentAlarmMsg);
        }
    } else {
        // 如果所有值都恢复正常，自动解除报警状态
        if (m_hasAlarm) {
            m_hasAlarm = false;
            m_alarmAcknowledged = false;
            m_currentAlarmMsg = "";
            emit alarmStatusChanged();
            emit logMessage("<font color='#00FF00'>所有指标已恢复正常</font>");
        }
    }
}

void SystemData::onReadyRead()
{
    // 接收串口数据并存入缓存
    m_serialBuffer.append(m_serialPort->readAll());
    processJsonData(m_serialBuffer);
}

void SystemData::onUdpReadyRead()
{
    while (m_udpSocket->hasPendingDatagrams()) {
        QByteArray datagram;
        datagram.resize(m_udpSocket->pendingDatagramSize());
        m_udpSocket->readDatagram(datagram.data(), datagram.size());
        
        // --- 新增：处理非 JSON 格式的特殊消息 (如 AI 诊断回复) ---
        QString msgStr = QString::fromUtf8(datagram);
        // 兼容新旧两种前缀
        if (msgStr.startsWith("[AI诊断回复]") || msgStr.startsWith("AI_REPLY:")) {
            // 如果是 AI_REPLY: 前缀，可以把前缀替换为中文标签再显示
            if (msgStr.startsWith("AI_REPLY:")) {
                msgStr.replace("AI_REPLY:", "[AI诊断回复] ");
            }
            // 如果是 AI 回复，直接作为日志消息发送，不要丢给 processJsonData 处理
            emit logMessage(msgStr);
            continue; // 跳过当前循环，不将数据追加到 JSON 缓存中
        }
        
        // 由于UDP通常是完整的数据包，我们将其追加到缓存中进行统一处理
        m_serialBuffer.append(datagram);
    }
    processJsonData(m_serialBuffer);
}

void SystemData::processJsonData(QByteArray &buffer)
{
    // 不再简单依赖 '\n' 作为单行分割，而是通过大括号匹配来寻找完整的 JSON 对象
    // 这可以完美处理带有换行符的格式化 JSON 字符串
    int braceCount = 0;
    int startIndex = -1;
    bool inString = false;
    
    for (int i = 0; i < buffer.length(); ++i) {
        char c = buffer.at(i);
        
        // 处理字符串中的大括号（忽略它们）
        if (c == '"' && (i == 0 || buffer.at(i-1) != '\\')) {
            inString = !inString;
            continue;
        }
        
        if (!inString) {
            if (c == '{') {
                if (braceCount == 0) {
                    startIndex = i; // 记录 JSON 起始位置
                }
                braceCount++;
            } else if (c == '}') {
                braceCount--;
                if (braceCount == 0 && startIndex != -1) {
                    // 找到了一个完整的 JSON 对象
                    QByteArray jsonStr = buffer.mid(startIndex, i - startIndex + 1);
                    
                    // 将处理过的部分从缓存中移除 (包括它前面的无用字符)
                    buffer.remove(0, i + 1);
                    
                    // 重新从头开始找下一个 JSON (因为缓存长度改变了)
                    i = -1; 
                    startIndex = -1;
                    
                    // 开始解析这个完整的 JSON
                    // 处理Windows串口助手发送的GBK编码中文字符
                    QString jsonString = QString::fromLocal8Bit(jsonStr);
                    QByteArray utf8Json = jsonString.toUtf8();
                    
                    QJsonParseError parseError;
                    QJsonDocument jsonDoc = QJsonDocument::fromJson(utf8Json, &parseError);

                    if (parseError.error == QJsonParseError::NoError && jsonDoc.isObject()) {
                        QJsonObject jsonObj = jsonDoc.object();
                        
                        // 解析水质指标 (支持长短键名)
                        if (jsonObj.contains("ph")) {
                            m_phValue = jsonObj["ph"].toDouble();
                            emit phValueChanged();
                        }
                        if (jsonObj.contains("do")) {
                            m_dissolvedOxygen = jsonObj["do"].toDouble();
                            emit dissolvedOxygenChanged();
                        }
                        if (jsonObj.contains("turbidity") || jsonObj.contains("turb")) {
                            m_turbidity = jsonObj.contains("turbidity") ? jsonObj["turbidity"].toDouble() : jsonObj["turb"].toDouble();
                            emit turbidityChanged();
                        }
                        
                        // 解析环境气象数据
                        if (jsonObj.contains("temperature") || jsonObj.contains("temp")) {
                            m_temperature = jsonObj.contains("temperature") ? jsonObj["temperature"].toDouble() : jsonObj["temp"].toDouble();
                            emit temperatureChanged();
                        }
                        if (jsonObj.contains("humidity") || jsonObj.contains("hum")) {
                            m_humidity = jsonObj.contains("humidity") ? jsonObj["humidity"].toDouble() : jsonObj["hum"].toDouble();
                            emit humidityChanged();
                        }
                        if (jsonObj.contains("windSpeed") || jsonObj.contains("ws")) {
                            m_windSpeed = jsonObj.contains("windSpeed") ? jsonObj["windSpeed"].toDouble() : jsonObj["ws"].toDouble();
                            emit windSpeedChanged();
                        }
                        if (jsonObj.contains("windDirection") || jsonObj.contains("wd")) {
                            m_windDirection = jsonObj.contains("windDirection") ? jsonObj["windDirection"].toString() : jsonObj["wd"].toString();
                            emit windDirectionChanged();
                        }
                        
                        // 解析无人机遥测数据 (兼容 UVA_telemetry 和 drone)
                        QString droneKey = jsonObj.contains("UVA_telemetry") ? "UVA_telemetry" : (jsonObj.contains("drone") ? "drone" : "");
                        if (!droneKey.isEmpty() && jsonObj[droneKey].isObject()) {
                            QJsonObject uvaObj = jsonObj[droneKey].toObject();
                            QVariantMap uvaMap = m_droneTelemetry;
                            if (uvaObj.contains("battery")) uvaMap["battery"] = uvaObj["battery"].toInt();
                            else if (uvaObj.contains("bat")) uvaMap["battery"] = uvaObj["bat"].toInt();
                            
                            if (uvaObj.contains("altitude")) uvaMap["altitude"] = uvaObj["altitude"].toDouble();
                            else if (uvaObj.contains("alt")) uvaMap["altitude"] = uvaObj["alt"].toDouble();
                            
                            if (uvaObj.contains("speed")) uvaMap["speed"] = uvaObj["speed"].toDouble();
                            else if (uvaObj.contains("spd")) uvaMap["speed"] = uvaObj["spd"].toDouble();
                            
                            if (uvaObj.contains("signal")) uvaMap["signal"] = uvaObj["signal"].toInt();
                            else if (uvaObj.contains("sig")) uvaMap["signal"] = uvaObj["sig"].toInt();
                            
                            m_droneTelemetry = uvaMap;
                            emit droneTelemetryChanged();
                        }
                        
                        // 解析无人船遥测数据 (兼容 USV_telemetry 和 ship)
                        QString shipKey = jsonObj.contains("USV_telemetry") ? "USV_telemetry" : (jsonObj.contains("ship") ? "ship" : "");
                        if (!shipKey.isEmpty() && jsonObj[shipKey].isObject()) {
                            QJsonObject usvObj = jsonObj[shipKey].toObject();
                            QVariantMap usvMap = m_shipTelemetry;
                            if (usvObj.contains("battery")) usvMap["battery"] = usvObj["battery"].toInt();
                            else if (usvObj.contains("bat")) usvMap["battery"] = usvObj["bat"].toInt();
                            
                            if (usvObj.contains("speed")) usvMap["speed"] = usvObj["speed"].toDouble();
                            else if (usvObj.contains("spd")) usvMap["speed"] = usvObj["spd"].toDouble();
                            
                            if (usvObj.contains("heading")) usvMap["heading"] = usvObj["heading"].toDouble();
                            else if (usvObj.contains("hdg")) usvMap["heading"] = usvObj["hdg"].toDouble();
                            
                            if (usvObj.contains("signal")) usvMap["signal"] = usvObj["signal"].toInt();
                            else if (usvObj.contains("sig")) usvMap["signal"] = usvObj["sig"].toInt();
                            
                            m_shipTelemetry = usvMap;
                            emit shipTelemetryChanged();
                        }
                        
                        emit logMessage(QString("收到有效传感器/遥测数据"));
                        
                        // 每次收到新数据并解析完成后，检查是否需要报警
                        checkAlarms();
                        
                    } else {
                        emit logMessage(QString("JSON解析失败: %1").arg(QString(jsonStr).simplified()));
                        qDebug() << "JSON parse error:" << parseError.errorString() << " Data:" << jsonStr;
                    }
                }
            }
        }
    }
}

void SystemData::setDroneRunning(bool running)
{
    if (m_droneRunning == running)
        return;

    m_droneRunning = running;
    emit droneRunningChanged();

    // 发送日志信号
    QString status = running ? "启动" : "停止";
    emit logMessage(QString("收到指令: 无人机巡检%1").arg(status));
}

void SystemData::setShipRunning(bool running)
{
    if (m_shipRunning == running)
        return;

    m_shipRunning = running;
    emit shipRunningChanged();

    // 发送日志信号
    QString status = running ? "启动" : "停止";
    emit logMessage(QString("收到指令: 无人船航行%1").arg(status));
}

void SystemData::onSimulateDataUpdate()
{
    // ============================================================
    // TODO: 在这里替换为真实的外部数据读取代码
    // 例如：
    // serialPort->readAll();
    // tcpSocket->readAll();
    // ============================================================

    // 只有在设备运行时才模拟数据变化
    if (m_droneRunning) {
        // 模拟 PH 值波动 (7.2 ~ 8.4)
        double newVal = 7.2 + QRandomGenerator::global()->generateDouble() * 1.2;
        // 保留两位小数
        m_phValue = QString::number(newVal, 'f', 2).toDouble();
        emit phValueChanged();

        // 模拟无人机遥测数据变化
        int currentBattery = m_droneTelemetry["battery"].toInt();
        if (currentBattery > 0) {
            m_droneTelemetry["battery"] = currentBattery - 1;
        }
        m_droneTelemetry["altitude"] = 120 + QRandomGenerator::global()->bounded(10); // 高度 120-130m
        m_droneTelemetry["speed"] = 15 + QRandomGenerator::global()->bounded(5);      // 速度 15-20m/s
        m_droneTelemetry["signal"] = 85 + QRandomGenerator::global()->bounded(15);    // 信号 85-100%
        emit droneTelemetryChanged();

        // 模拟无人机传感器数据
        QVariantList newData;
        for(int i=0; i<7; ++i) {
            newData.append(QRandomGenerator::global()->bounded(100));
        }
        m_droneData = newData;
        emit droneDataChanged();
    }

    if (m_shipRunning) {
        // 模拟无人船遥测数据变化
        int currentBattery = m_shipTelemetry["battery"].toInt();
        if (currentBattery > 0) {
            m_shipTelemetry["battery"] = currentBattery - 1;
        }
        m_shipTelemetry["speed"] = 5 + QRandomGenerator::global()->bounded(3);        // 速度 5-8kn
        m_shipTelemetry["heading"] = QRandomGenerator::global()->bounded(360);        // 航向 0-359度
        m_shipTelemetry["signal"] = 90 + QRandomGenerator::global()->bounded(10);     // 信号 90-100%
        emit shipTelemetryChanged();

        // 模拟无人船传感器数据
        QVariantList newData;
        for(int i=0; i<7; ++i) {
            newData.append(QRandomGenerator::global()->bounded(100));
        }
        m_shipData = newData;
        emit shipDataChanged();
    }
}
