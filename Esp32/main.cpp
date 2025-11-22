// main.cpp - ESP32 S3 Super Mini
#include "WiFi.h"
#include "Wire.h"
#include "MAX30105.h"
#include "DFRobot_BMI160.h"
#include "AsyncWebSocket.h"
#include "ArduinoJson.h"

// Configuración WiFi
const char* ssid = "Carolina";
const char* password = "3214661690";
const char* server_ip = "192.168.1.15";  // IP del computador

// Sensores
MAX30105 ppgSensor;
BMI160 imuSensor;

// WebSocket para comunicación
AsyncWebSocket ws("/ws");
AsyncWebServer server(80);

// Buffers de datos
const int BUFFER_SIZE = 500;
float ppg_buffer[BUFFER_SIZE];
float accel_buffer[BUFFER_SIZE][3];
float gyro_buffer[BUFFER_SIZE][3];
int buffer_index = 0;

// Configuración
struct Config {
    int ppg_sample_rate = 100;  // Hz
    int imu_sample_rate = 100;  // Hz
    int transmission_interval = 1000;  // ms
    float fall_threshold = 2.5;  // g
} config;

void setup() {
    Serial.begin(115200);
    
    // Inicializar I2C
    Wire.begin(21, 22);  // SDA, SCL
    
    // Configurar sensores
    setupPPGSensor();
    setupIMUSensor();
    
    // Conectar WiFi
    connectWiFi();
    
    // Configurar WebSocket
    setupWebSocket();
    
    Serial.println("Sistema inicializado correctamente");
}

void setupPPGSensor() {
    if (!ppgSensor.begin()) {
        Serial.println("Error: MAX30102 no encontrado");
        return;
    }
    
    // Configuración optimizada
    ppgSensor.setup(0x1F, 4, 2, 100, 411, 4096);
    /*
     * powerLevel = 0x1F (31) - Máxima potencia LED
     * sampleAverage = 4 - Promedio de 4 muestras
     * ledMode = 2 - Red + IR
     * sampleRate = 100 - 100 Hz
     * pulseWidth = 411 - 18 bits resolución
     * adcRange = 4096 - Rango ADC 0-4096
     */
}

void setupIMUSensor() {
    if (imuSensor.begin() != BMI160_OK) {
        Serial.println("Error: BMI160 no encontrado");
        return;
    }
    
    // Configuración para detección de caídas
    imuSensor.setAccelRange(BMI160_ACCEL_RANGE_8G);
    imuSensor.setGyroRange(BMI160_GYRO_RANGE_1000);
    imuSensor.setAccelOutputDataRate(BMI160_ACCEL_ODR_100HZ);
    imuSensor.setGyroOutputDataRate(BMI160_GYRO_ODR_100HZ);
}

void connectWiFi() {
    WiFi.begin(ssid, password);
    while (WiFi.status() != WL_CONNECTED) {
        delay(500);
        Serial.print(".");
    }
    Serial.println("\nWiFi conectado: " + WiFi.localIP().toString());
}