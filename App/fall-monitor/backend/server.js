const express = require('express');
const { createServer } = require('http');
const { Server } = require('socket.io');
const mqtt = require('mqtt');
const cors = require('cors');

const app = express();
const httpServer = createServer(app);
const io = new Server(httpServer, {
  cors: {
    origin: "*",
    methods: ["GET", "POST"]
  }
});

app.use(cors());
app.use(express.json());

// CONFIGURACIÓN MQTT
const MQTT_CONFIG = {
  host: 'broker.hivemq.com',
  port: 1883,
  protocol: 'mqtt'
};

// Topics actualizados con control manual
const TOPICS = {
  ESP32_IMU: 'esp32/imu',
  ESP32_BIO: 'esp32/bio',
  MANUAL_BPM: 'fallmonitor/manual/bpm',
  MANUAL_SPO2: 'fallmonitor/manual/spo2',
  MANUAL_ESTADO: 'fallmonitor/manual/estado',      // NUEVO
  MANUAL_CAIDAS: 'fallmonitor/manual/caidas',      // NUEVO
  MATLAB_ACTIVITY: 'fallmonitor/matlab/activity',
  MATLAB_FALL: 'fallmonitor/matlab/fall',
  MATLAB_HEALTH: 'fallmonitor/esp32/health'
};

console.log('╔════════════════════════════════════════════════╗');
console.log('║     🚀 SERVIDOR BACKEND - FALL MONITOR        ║');
console.log('╚════════════════════════════════════════════════╝');
console.log('\n🔌 Conectando a MQTT...');
console.log('   Broker:', MQTT_CONFIG.host);
console.log('   Puerto:', MQTT_CONFIG.port);

// Conectar a MQTT
const mqttClient = mqtt.connect(MQTT_CONFIG);

mqttClient.on('connect', () => {
  console.log('\n✅ Conectado a MQTT broker');
  console.log('\n📡 Suscribiéndose a topics...\n');
  
  Object.entries(TOPICS).forEach(([key, topic]) => {
    mqttClient.subscribe(topic, (err) => {
      if (!err) {
        console.log(`   ✅ ${topic}`);
      } else {
        console.error(`   ❌ Error en ${topic}:`, err.message);
      }
    });
  });
  
  console.log('\n════════════════════════════════════════════════');
  console.log('✅ Sistema listo para recibir datos');
  console.log('════════════════════════════════════════════════\n');
});

mqttClient.on('error', (err) => {
  console.error('❌ Error MQTT:', err.message);
});

mqttClient.on('offline', () => {
  console.log('⚠️  MQTT offline, reintentando...');
});

mqttClient.on('reconnect', () => {
  console.log('🔄 Reconectando a MQTT...');
});

// Manejar mensajes MQTT
mqttClient.on('message', (topic, message) => {
  try {
    const data = JSON.parse(message.toString());
    
    // Log selectivo (no IMU)
    if (topic !== TOPICS.ESP32_IMU) {
      const emoji = getTopicEmoji(topic);
      console.log(`${emoji} [${new Date().toLocaleTimeString()}] ${topic}:`, data);
    }
    
    // Log especial para controles manuales
    if (topic === TOPICS.MANUAL_ESTADO) {
      const estados = { 1: 'QUIETO', 2: 'CAMINANDO', 3: 'CORRIENDO' };
      const valor = data.value || data.estado || data;
      console.log(`🎮 CONTROL MANUAL ESTADO → ${estados[valor] || valor}`);
    }
    
    if (topic === TOPICS.MANUAL_CAIDAS) {
      const valor = data.value || data.caida || data;
      if (valor === 1) {
        console.log('\n╔════════════════════════════════════════════════╗');
        console.log('║   🚨 CAÍDA MANUAL REGISTRADA 🚨                ║');
        console.log('╚════════════════════════════════════════════════╝\n');
      }
    }
    
    // Alerta de caída automática
    if (topic === TOPICS.MATLAB_FALL && data.fall_detected) {
      console.log('\n╔════════════════════════════════════════════════╗');
      console.log('║   🚨🚨🚨 ALERTA DE CAÍDA DETECTADA 🚨🚨🚨     ║');
      console.log('╚════════════════════════════════════════════════╝');
      console.log(`   Contador: ${data.fall_count}`);
      console.log(`   Hora: ${data.timestamp}`);
      console.log('════════════════════════════════════════════════\n');
    }
    
    // Enviar a WebSocket
    io.emit('mqtt-data', {
      topic,
      data,
      timestamp: new Date().toISOString()
    });
  } catch (err) {
    // Intentar como número
    try {
      const numValue = parseFloat(message.toString());
      if (!isNaN(numValue)) {
        console.log(`📊 ${topic}: ${numValue}`);
        io.emit('mqtt-data', {
          topic,
          data: { value: numValue },
          timestamp: new Date().toISOString()
        });
      }
    } catch (parseErr) {
      console.error(`❌ Error parseando ${topic}:`, message.toString());
    }
  }
});

// Helper
function getTopicEmoji(topic) {
  if (topic.includes('health')) return '❤️';
  if (topic.includes('activity')) return '🚶';
  if (topic.includes('fall')) return '🚨';
  if (topic.includes('estado')) return '🎮';
  if (topic.includes('caidas')) return '⚠️';
  if (topic.includes('bpm')) return '💓';
  if (topic.includes('spo2')) return '🫁';
  if (topic.includes('bio')) return '🩺';
  if (topic.includes('imu')) return '📊';
  return '📨';
}

// WebSocket
io.on('connection', (socket) => {
  console.log('👤 Cliente conectado:', socket.id);
  
  socket.emit('mqtt-status', {
    connected: mqttClient.connected,
    topics: Object.keys(TOPICS).length
  });
  
  socket.on('disconnect', () => {
    console.log('👋 Cliente desconectado:', socket.id);
  });
});

// Endpoints
app.get('/health', (req, res) => {
  res.json({
    status: 'online',
    mqtt: mqttClient.connected ? 'connected' : 'disconnected',
    timestamp: new Date().toISOString(),
    topics: TOPICS
  });
});

app.post('/alert', (req, res) => {
  const { contact, message } = req.body;
  console.log(`🚨 ALERTA DE EMERGENCIA para ${contact}: ${message}`);
  
  io.emit('emergency-alert', {
    contact,
    message,
    timestamp: new Date().toISOString()
  });
  
  res.json({ success: true, message: 'Alerta enviada' });
});

app.post('/publish', (req, res) => {
  const { topic, data } = req.body;
  
  if (!topic || !data) {
    return res.status(400).json({ error: 'Topic y data requeridos' });
  }
  
  const payload = JSON.stringify(data);
  mqttClient.publish(topic, payload, (err) => {
    if (err) {
      console.error(`❌ Error publicando en ${topic}:`, err);
      res.status(500).json({ error: err.message });
    } else {
      console.log(`📤 Publicado en ${topic}:`, data);
      res.json({ success: true, topic, data });
    }
  });
});

// Iniciar servidor
const PORT = process.env.PORT || 3001;
httpServer.listen(PORT, () => {
  console.log('\n╔════════════════════════════════════════════════╗');
  console.log(`║  🚀 Servidor en http://localhost:${PORT}           ║`);
  console.log('╚════════════════════════════════════════════════╝');
  console.log('\n📡 Topics configurados:\n');
  Object.entries(TOPICS).forEach(([key, topic]) => {
    console.log(`   ${getTopicEmoji(topic)} ${key.padEnd(20)} → ${topic}`);
  });
  console.log('\n📍 Endpoints:');
  console.log(`   GET  /health`);
  console.log(`   POST /alert`);
  console.log(`   POST /publish\n`);
  console.log('💡 Controles manuales:');
  console.log('   - fallmonitor/manual/estado → 1=quieto, 2=caminar, 3=correr');
  console.log('   - fallmonitor/manual/caidas → 1=registrar caída');
  console.log('   - fallmonitor/manual/bpm → valor BPM');
  console.log('   - fallmonitor/manual/spo2 → valor SpO2\n');
});