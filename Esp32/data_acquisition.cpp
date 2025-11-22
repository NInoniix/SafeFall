// data_acquisition.cpp

class DataProcessor {
private:
    // Filtros digitales
    float ppg_filter_buffer[5] = {0};
    float accel_filter_buffer[3][5] = {{0}};
    
    // Detector de caídas en tiempo real
    bool fall_detection_active = false;
    unsigned long fall_start_time = 0;
    
public:
    void processData() {
        // Leer sensores
        readPPGData();
        readIMUData();
        
        // Procesamiento en tiempo real
        float filtered_ppg = filterPPG(ppg_buffer[buffer_index]);
        filterIMUData();
        
        // Detección rápida de caídas
        if (quickFallDetection()) {
            triggerEmergencyAlert();
        }
        
        // Incrementar índice del buffer
        buffer_index = (buffer_index + 1) % BUFFER_SIZE;
    }
    
    void readPPGData() {
        if (ppgSensor.available()) {
            ppg_buffer[buffer_index] = ppgSensor.getRed();
            ppgSensor.nextSample();
        }
    }
    
    void readIMUData() {
        int16_t accelX, accelY, accelZ;
        int16_t gyroX, gyroY, gyroZ;
        
        imuSensor.getAcceleration(&accelX, &accelY, &accelZ);
        imuSensor.getRotation(&gyroX, &gyroY, &gyroZ);
        
        // Convertir a unidades físicas
        accel_buffer[buffer_index][0] = accelX / 4096.0;  // g
        accel_buffer[buffer_index][1] = accelY / 4096.0;
        accel_buffer[buffer_index][2] = accelZ / 4096.0;
        
        gyro_buffer[buffer_index][0] = gyroX / 32.8;      // °/s
        gyro_buffer[buffer_index][1] = gyroY / 32.8;
        gyro_buffer[buffer_index][2] = gyroZ / 32.8;
    }
    
    float filterPPG(float raw_value) {
        // Filtro pasa-banda IIR simple (0.5-8 Hz aprox)
        // Desplazar buffer
        for (int i = 4; i > 0; i--) {
            ppg_filter_buffer[i] = ppg_filter_buffer[i-1];
        }
        ppg_filter_buffer[0] = raw_value;
        
        // Aplicar coeficientes del filtro
        float filtered = 0.1 * (ppg_filter_buffer[0] + ppg_filter_buffer[4]) +
                        0.2 * (ppg_filter_buffer[1] + ppg_filter_buffer[3]) +
                        0.4 * ppg_filter_buffer[2];
        
        return filtered;
    }
    
    bool quickFallDetection() {
        // Cálculo rápido de magnitud
        float magnitude = sqrt(
            accel_buffer[buffer_index][0] * accel_buffer[buffer_index][0] +
            accel_buffer[buffer_index][1] * accel_buffer[buffer_index][1] +
            accel_buffer[buffer_index][2] * accel_buffer[buffer_index][2]
        );
        
        // Detección de caída libre (< 0.5g)
        if (magnitude < 0.5 && !fall_detection_active) {
            fall_detection_active = true;
            fall_start_time = millis();
            return false;
        }
        
        // Detección de impacto (> 3g) después de caída libre
        if (fall_detection_active && magnitude > 3.0) {
            fall_detection_active = false;
            return true;  // ¡CAÍDA DETECTADA!
        }
        
        // Reset si pasa mucho tiempo sin impacto
        if (fall_detection_active && (millis() - fall_start_time) > 2000) {
            fall_detection_active = false;
        }
        
        return false;
    }
    
    void triggerEmergencyAlert() {
        // Envío inmediato de alerta
        DynamicJsonDocument alert(200);
        alert["type"] = "EMERGENCY";
        alert["event"] = "FALL_DETECTED";
        alert["timestamp"] = millis();
        alert["severity"] = "HIGH";
        
        String alertMessage;
        serializeJson(alert, alertMessage);
        
        // Enviar por todos los canales disponibles
        ws.textAll(alertMessage);
        Serial.println("ALERTA DE EMERGENCIA: " + alertMessage);
        
        // LED de emergencia
        digitalWrite(2, HIGH);  // LED integrado
    }
};

DataProcessor processor;