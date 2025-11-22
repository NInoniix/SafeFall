// communication.cpp

void setupWebSocket() {
    ws.onEvent(onWebSocketEvent);
    server.addHandler(&ws);
    server.begin();
}

void onWebSocketEvent(AsyncWebSocket *server, AsyncWebSocketClient *client,
                      AwsEventType type, void *arg, uint8_t *data, size_t len) {
    
    if (type == WS_EVT_CONNECT) {
        Serial.printf("Cliente conectado: %s\n", client->remoteIP().toString().c_str());
        
        // Enviar configuración inicial
        sendConfiguration(client);
        
    } else if (type == WS_EVT_DISCONNECT) {
        Serial.printf("Cliente desconectado\n");
        
    } else if (type == WS_EVT_DATA) {
        // Procesar comandos del computador
        handleCommand(data, len);
    }
}

void sendSensorData() {
    DynamicJsonDocument doc(2048);
    
    // Timestamp
    doc["timestamp"] = millis();
    doc["device_id"] = WiFi.macAddress();
    
    // Datos PPG (últimos 10 valores)
    JsonArray ppg_array = doc.createNestedArray("ppg");
    for (int i = 0; i < 10; i++) {
        int idx = (buffer_index - 10 + i + BUFFER_SIZE) % BUFFER_SIZE;
        ppg_array.add(ppg_buffer[idx]);
    }
    
    // Datos IMU (últimos 10 valores)
    JsonArray accel_array = doc.createNestedArray("accelerometer");
    JsonArray gyro_array = doc.createNestedArray("gyroscope");
    
    for (int i = 0; i < 10; i++) {
        int idx = (buffer_index - 10 + i + BUFFER_SIZE) % BUFFER_SIZE;
        
        JsonArray accel_sample = accel_array.createNestedArray();
        accel_sample.add(accel_buffer[idx][0]);
        accel_sample.add(accel_buffer[idx][1]);
        accel_sample.add(accel_buffer[idx][2]);
        
        JsonArray gyro_sample = gyro_array.createNestedArray();
        gyro_sample.add(gyro_buffer[idx][0]);
        gyro_sample.add(gyro_buffer[idx][1]);
        gyro_sample.add(gyro_buffer[idx][2]);
    }
    
    // Estado del dispositivo
    doc["battery_level"] = analogRead(A0) * 100 / 4095;  // Estimación
    doc["temperature"] = 25.0;  // Se puede leer del BMI160
    doc["signal_quality"] = calculateSignalQuality();
    
    String message;
    serializeJson(doc, message);
    ws.textAll(message);
}

float calculateSignalQuality() {
    // Cálculo simple de calidad basado en varianza
    float sum = 0, mean = 0, variance = 0;
    int samples = 50;
    
    for (int i = 0; i < samples; i++) {
        int idx = (buffer_index - samples + i + BUFFER_SIZE) % BUFFER_SIZE;
        sum += ppg_buffer[idx];
    }
    mean = sum / samples;
    
    for (int i = 0; i < samples; i++) {
        int idx = (buffer_index - samples + i + BUFFER_SIZE) % BUFFER_SIZE;
        variance += pow(ppg_buffer[idx] - mean, 2);
    }
    variance /= samples;
    
    // Calidad basada en SNR estimado
    return constrain(variance / 10000.0, 0.0, 1.0);
}