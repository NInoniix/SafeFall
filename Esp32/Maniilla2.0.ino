// main loop
void loop() {
    static unsigned long last_transmission = 0;
    static unsigned long last_sensor_read = 0;
    
    unsigned long current_time = millis();
    
    // Leer sensores a 100 Hz
    if (current_time - last_sensor_read >= 10) {  // 10ms = 100Hz
        processor.processData();
        last_sensor_read = current_time;
    }
    
    // Transmitir datos cada segundo
    if (current_time - last_transmission >= config.transmission_interval) {
        sendSensorData();
        last_transmission = current_time;
    }
    
    // Mantener conexión WebSocket
    ws.cleanupClients();
    
    delay(1);  // Pequeña pausa para watchdog
}