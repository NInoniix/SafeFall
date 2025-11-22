clc; clear; close all;

fprintf('Sistema de Monitoreo ESP32\n');
fprintf('Detector de Caidas + Actividad + Biometricos\n\n');

% Configuracion MQTT
BROKER = 'tcp://broker.hivemq.com';
PORT = 1883;

% Topics de entrada (ESP32)
TOPIC_IMU = 'esp32/imu';
TOPIC_BIO = 'esp32/bio';

% Topics de salida (App)
TOPIC_ACTIVITY = 'fallmonitor/matlab/activity';
TOPIC_FALL = 'fallmonitor/matlab/fall';
TOPIC_HEALTH = 'fallmonitor/esp32/health';

% Ruta del modelo
MODELO_PATH = 'C:\Users\Zseba\OneDrive\Documentos\U\Electromed\archive (1)\modelo.mat';

% Parametros
VENTANA_IMU = 100;
VENTANA_CAIDAS = 50;
REPORTE_ACTIVIDAD_SEG = 5;     % Reportar actividad cada 5 segundos
REPORTE_SALUD_SEG = 60;        % Reportar salud cada 60 segundos (1 minuto)

% Cargar modelo
fprintf('Cargando modelo CNN-LSTM...\n');
try
    datos = load(MODELO_PATH);
    if isfield(datos, 'modelo_final')
        modelo = datos.modelo_final;
        net = modelo.red;
        mu = modelo.mu;
        sigma = modelo.sigma;
        clases = modelo.clases;
        if isfield(modelo, 'detector_caidas')
            detector_caidas = modelo.detector_caidas;
        else
            detector_caidas = [];
        end
    elseif isfield(datos, 'net')
        net = datos.net;
        mu = datos.mu;
        sigma = datos.sigma;
        clases = datos.clases;
        detector_caidas = [];
    else
        error('Formato de modelo no reconocido');
    end
    fprintf('Modelo cargado correctamente\n');
    fprintf('Clases: %s\n\n', strjoin(string(clases), ', '));
catch ME
    error('Error cargando modelo: %s', ME.message);
end

% Variables globales
global g_buffer g_buffer_caidas g_predicciones g_ultimo_reporte
global g_net g_mu g_sigma g_detector_caidas
global g_hr g_spo2 g_finger g_contador
global g_mqttClient g_fall_count g_primera_senal
global g_ultimo_envio_salud g_historial_hr g_historial_spo2

g_buffer = [];
g_buffer_caidas = [];
g_predicciones = {};
g_ultimo_reporte = tic;
g_ultimo_envio_salud = tic;    % Timer para envio de salud
g_historial_hr = [];           % Historial de HR del ultimo minuto
g_historial_spo2 = [];         % Historial de SpO2 del ultimo minuto
g_contador = 0;
g_fall_count = 0;
g_primera_senal = false;

g_net = net;
g_mu = mu;
g_sigma = sigma;
g_detector_caidas = detector_caidas;

g_hr = 0;
g_spo2 = 0;
g_finger = false;

% Conectar MQTT
fprintf('Conectando a MQTT broker...\n');
try
    g_mqttClient = mqttclient(BROKER, 'Port', PORT, 'ClientID', 'MATLAB_Monitor');
    fprintf('Conectado: %s:%d\n\n', BROKER, PORT);
catch ME
    error('Error MQTT: %s', ME.message);
end

% Suscribirse a topics
try
    subscribe(g_mqttClient, TOPIC_IMU, 'Callback', @callbackIMU);
    fprintf('Suscrito a IMU: %s\n', TOPIC_IMU);
    subscribe(g_mqttClient, TOPIC_BIO, 'Callback', @callbackBio);
    fprintf('Suscrito a BIO: %s\n', TOPIC_BIO);
catch ME
    error('Error suscripcion: %s', ME.message);
end

fprintf('\nSISTEMA ACTIVO - Esperando datos del ESP32...\n');
fprintf('Escuchando: %s (IMU)\n', TOPIC_IMU);
fprintf('Escuchando: %s (Biometricos)\n', TOPIC_BIO);
fprintf('Enviando a: %s (Actividad)\n', TOPIC_ACTIVITY);
fprintf('Enviando a: %s (Caidas)\n', TOPIC_FALL);
fprintf('Enviando a: %s (Salud)\n\n', TOPIC_HEALTH);
fprintf('Esperando primera senal del ESP32...\n\n');

% Loop principal
while true
    pause(0.1);
end

% Callback biometricos
function callbackBio(~, msg)
    global g_hr g_spo2 g_finger g_mqttClient g_ultimo_envio_salud
    try
        if ischar(msg) || isstring(msg)
            jsonData = char(msg);
        elseif isstruct(msg) && isfield(msg, 'Data')
            jsonData = char(msg.Data);
        else
            jsonData = char(msg);
        end
        datos = jsondecode(jsonData);
        
        if isfield(datos, 'hr') && isfield(datos, 'spo2') && isfield(datos, 'finger')
            g_hr = datos.hr;
            g_spo2 = datos.spo2;
            g_finger = datos.finger;
            
            % Mostrar en consola siempre
            if g_finger && g_hr > 0
                fprintf('HR: %3d bpm | SpO2: %3d%% | IR: %d | %s\n', ...
                        g_hr, g_spo2, datos.ir, datestr(now, 'HH:MM:SS'));
            else
                fprintf('Sin dedo detectado | %s\n', datestr(now, 'HH:MM:SS'));
            end
            
            % Enviar a la app solo cada 60 segundos
            tiempo_desde_ultimo_envio = toc(g_ultimo_envio_salud);
            if tiempo_desde_ultimo_envio >= 60
                enviarDatosSalud(g_mqttClient, g_hr, g_spo2);
                g_ultimo_envio_salud = tic;
            end
        end
    catch ME
        warning('Error en callback Bio: %s', ME.message);
    end
end

% Callback IMU
function callbackIMU(~, msg)
    global g_buffer g_buffer_caidas g_predicciones g_ultimo_reporte
    global g_net g_mu g_sigma g_detector_caidas
    global g_hr g_spo2 g_finger g_contador g_mqttClient g_fall_count
    global g_primera_senal
    
    try
        if ~g_primera_senal
            fprintf('Primera senal recibida del ESP32!\n\n');
            g_primera_senal = true;
        end
        
        if ischar(msg) || isstring(msg)
            jsonData = char(msg);
        elseif isstruct(msg) && isfield(msg, 'Data')
            jsonData = char(msg.Data);
        else
            jsonData = char(msg);
        end
        
        datos = jsondecode(jsonData);
        g_contador = g_contador + 1;
        
        if ~(isfield(datos, 'ax') && isfield(datos, 'ay') && ...
             isfield(datos, 'az') && isfield(datos, 'gx') && ...
             isfield(datos, 'gy') && isfield(datos, 'gz'))
            return;
        end
        
        fila = [datos.ax, datos.ay, datos.az, datos.gx, datos.gy, datos.gz];
        g_buffer = [g_buffer; fila];
        g_buffer_caidas = [g_buffer_caidas; fila];
        if size(g_buffer, 1) > 200
            g_buffer = g_buffer(end-199:end, :);
        end
        if size(g_buffer_caidas, 1) > 100
            g_buffer_caidas = g_buffer_caidas(end-99:end, :);
        end
        
        if mod(g_contador, 50) == 0
            % Punto cada 50 mensajes (reducir spam en consola)
        end
        
        if size(g_buffer, 1) >= 100
            X = g_buffer(end-99:end, :);
            X_norm = X';
            for canal = 1:6
                X_norm(canal, :) = (X_norm(canal, :) - g_mu(canal)) / (g_sigma(canal) + eps);
            end
            [pred, scores] = classify(g_net, {X_norm});
            actividad = char(pred);
            confianza = max(scores) * 100;
            g_predicciones{end+1} = struct('actividad', actividad, 'confianza', confianza, 'timestamp', now);
        else
            actividad = '';
            confianza = 0;
        end

        if size(g_buffer_caidas, 1) >= 50 && ~isempty(g_detector_caidas)
            if ~isempty(actividad) && ~strcmpi(actividad, 'run')
                X_caida = g_buffer_caidas(end-49:end, :);
                ax = X_caida(:, 1); ay = X_caida(:, 2); az = X_caida(:, 3);
                gx = X_caida(:, 4); gy = X_caida(:, 5); gz = X_caida(:, 6);
                mag_accel = sqrt(ax.^2 + ay.^2 + az.^2);
                max_mag = max(mag_accel);
                jerk = abs(diff(mag_accel));
                max_jerk = max(jerk);
                mag_gyro = sqrt(gx.^2 + gy.^2 + gz.^2);
                max_gyro = max(mag_gyro);
                es_caida = (max_mag > g_detector_caidas.umbral_magnitud) && ...
                           (max_jerk > g_detector_caidas.umbral_jerk) && ...
                           (max_gyro > g_detector_caidas.umbral_gyro);
                if es_caida
                    g_fall_count = g_fall_count + 1;
                    fprintf('\n\nCAIDA DETECTADA\n');
                    fprintf('Actividad previa: %s (%.1f%%)\n', upper(actividad), confianza);
                    fprintf('Magnitud accel: %.2f g\n', max_mag);
                    fprintf('Jerk maximo: %.2f g/s\n', max_jerk);
                    fprintf('Gyro maximo: %.0f deg/s\n', max_gyro);
                    fprintf('HR: %d bpm | SpO2: %d%%\n', g_hr, g_spo2);
                    fprintf('Hora: %s\n', datestr(now, 'HH:MM:SS'));
                    fprintf('Total caidas: %d\n\n', g_fall_count);
                    beep; pause(0.1); beep;

                    enviarAlertaCaida(g_mqttClient, true, g_fall_count);
                    fprintf('>>> ALERTA DE CAIDA enviada a la app\n\n');
                    
                    try
                        token = '8186040582:AAFiwSj0mrgociN674jWmNzaaMz-FG0_3Sg';
                        chat_id = '5278383604';
                        mensaje = sprintf('ALERTA DE CAIDA DETECTADA\nHora: %s\nActividad: %s\nHR: %d SpO2: %d', ...
                                           datestr(now, 'HH:MM:SS'), upper(actividad), g_hr, g_spo2);
                        mensaje = urlencode(mensaje);
                        url = sprintf('https://api.telegram.org/bot%s/sendMessage?chat_id=%s&text=%s', token, chat_id, mensaje);
                        webread(url);
                    catch
                    end

                    g_predicciones = {};
                    g_ultimo_reporte = tic;
                    g_buffer_caidas = [];
                    return;
                else
                    enviarAlertaCaida(g_mqttClient, false, g_fall_count);
                end
            end
        end
        
        % === REPORTE PERIÓDICO DE ACTIVIDAD (cada 5 segundos) ===
        tiempo_transcurrido = toc(g_ultimo_reporte);
        if tiempo_transcurrido >= 5 && ~isempty(g_predicciones)
            actividades = cellfun(@(x) x.actividad, g_predicciones, 'UniformOutput', false);
            confianzas = cellfun(@(x) x.confianza, g_predicciones);
            [unicas, ~, idx] = unique(actividades);
            conteos = accumarray(idx, 1);
            [~, idx_max] = max(conteos);
            actividad_dom = unicas{idx_max};
            indices = strcmp(actividades, actividad_dom);
            conf_prom = mean(confianzas(indices));
            porcentaje = 100 * conteos(idx_max) / length(actividades);
            
            fprintf('\n\nREPORTE DE ACTIVIDAD (cada 5 seg)\n');
            fprintf('ACTIVIDAD: %s\n', upper(actividad_dom));
            fprintf('Confianza: %.1f%%\n', conf_prom);
            fprintf('Frecuencia: %.1f%% del tiempo\n', porcentaje);
            fprintf('HR: %d bpm | SpO2: %d%%', g_hr, g_spo2);
            if g_finger
                fprintf(' OK\n');
            else
                fprintf(' (sin dedo)\n');
            end
            fprintf('Hora: %s\n', datestr(now, 'HH:MM:SS'));
            for i = 1:length(unicas)
                pct = 100 * conteos(i) / length(actividades);
                fprintf('  %s: %.1f%%\n', unicas{i}, pct);
            end
            fprintf('\n');
            
            % Enviar a la app
            enviarActividad(g_mqttClient, actividad_dom);
            fprintf('>>> Actividad enviada a la app\n\n');
            
            g_predicciones = {};
            g_ultimo_reporte = tic;
        end
    catch ME
        warning('Error en callback IMU: %s', ME.message);
    end
end

% Funciones de envio MQTT
function enviarActividad(mqttClient, actividad)
    try
        activityMap = containers.Map(...
            {'walk', 'walking', 'run', 'running', 'idle', 'standing', 'sitting'}, ...
            {'walking', 'walking', 'running', 'running', 'idle', 'idle', 'idle'});
        
        if isKey(activityMap, lower(actividad))
            actividadNormalizada = activityMap(lower(actividad));
        else
            actividadNormalizada = lower(actividad);
        end
        
        timestamp = char(datetime('now', 'Format', 'yyyy-MM-dd''T''HH:mm:ss''Z'''));
        activityData = struct('activity', actividadNormalizada, 'timestamp', timestamp);
        activityJSON = jsonencode(activityData);
        write(mqttClient, 'fallmonitor/matlab/activity', activityJSON);
    catch ME
        warning('Error enviando actividad: %s', ME.message);
    end
end

function enviarAlertaCaida(mqttClient, caida_detectada, contador_caidas)
    try
        timestamp = char(datetime('now', 'Format', 'yyyy-MM-dd''T''HH:mm:ss''Z'''));
        fallData = struct('fall_detected', caida_detectada, 'fall_count', contador_caidas, 'timestamp', timestamp);
        fallJSON = jsonencode(fallData);
        write(mqttClient, 'fallmonitor/matlab/fall', fallJSON);
    catch ME
        warning('Error enviando alerta de caida: %s', ME.message);
    end
end

function enviarDatosSalud(mqttClient, bpm, spo2)
    try
        timestamp = char(datetime('now', 'Format', 'yyyy-MM-dd''T''HH:mm:ss''Z'''));
        healthData = struct('bpm', bpm, 'spo2', spo2, 'timestamp', timestamp);
        healthJSON = jsonencode(healthData);
        write(mqttClient, 'fallmonitor/esp32/health', healthJSON);
        fprintf('>>> Datos de salud enviados a la app (HR: %d, SpO2: %d)\n', bpm, spo2);
    catch ME
        warning('Error enviando datos de salud: %s', ME.message);
    end
end