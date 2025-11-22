%% ================================================================
%  SISTEMA COMPLETO: CLASIFICADOR DE ACTIVIDADES + DETECTOR DE CAÍDAS
%  Optimizado para datos reales de acelerómetro + giroscopio
%  Arquitectura: CNN-LSTM para actividades + Detector basado en reglas
%  VERSIÓN CORREGIDA - Sin errores de dimensiones
%% ================================================================

clc; clear; close all;
rng(42);

%% === CONFIGURACIÓN ===
config = struct();
config.directorio_datos = 'C:\Users\Zseba\OneDrive\Documentos\U\Electromed\Movimiento';
config.frecuencia_muestreo = 50; % Hz
config.tamano_ventana = 100; % 2 segundos
config.solapamiento = 50; % 50 muestras (1 segundo)
config.ratio_train = 0.75;

% Categorías de actividades
config.actividades_normales = {'walk', 'run', 'sit', 'reposo'};
config.tipos_caidas = {'backward', 'forward', 'forwardw', 'lateral', 'lateralg'};

fprintf('========================================\n');
fprintf('  SISTEMA HÍBRIDO DE CLASIFICACIÓN  \n');
fprintf('========================================\n\n');

%% === 1. CARGAR Y SEPARAR DATOS ===
fprintf('📂 Cargando archivos desde: %s\n', config.directorio_datos);

archivos = dir(fullfile(config.directorio_datos, '*.xlsx'));
if isempty(archivos)
    error('No se encontraron archivos Excel');
end

fprintf('📄 Total de archivos: %d\n\n', length(archivos));

datos_actividades = struct();
datos_caidas = struct();
idx_act = 1;
idx_caida = 1;

for i = 1:length(archivos)
    nombre = archivos(i).name;
    fprintf('[%d/%d] %s\n', i, length(archivos), nombre);
    
    % Leer archivo
    try
        ruta = fullfile(config.directorio_datos, nombre);
        datos_raw = readmatrix(ruta);
        
        if size(datos_raw, 1) < config.tamano_ventana
            fprintf('  ⚠ Muy corto (%d filas), omitiendo\n', size(datos_raw, 1));
            continue;
        end
        
        % Extraer etiqueta
        etiqueta = extraer_etiqueta_mejorada(nombre);
        fprintf('  → Etiqueta: %s (%d muestras)\n', etiqueta, size(datos_raw, 1));
        
        % Validar columnas
        if size(datos_raw, 2) < 6
            fprintf('  ⚠ Se necesitan 6 columnas (Ax,Ay,Az,Gx,Gy,Gz)\n');
            continue;
        end
        
        % Extraer señales y limpiar
        ax = datos_raw(:, 1);
        ay = datos_raw(:, 2);
        az = datos_raw(:, 3);
        gx = datos_raw(:, 4);
        gy = datos_raw(:, 5);
        gz = datos_raw(:, 6);
        
        % Remover NaN/Inf
        valid = all(isfinite([ax, ay, az, gx, gy, gz]), 2);
        ax = ax(valid); ay = ay(valid); az = az(valid);
        gx = gx(valid); gy = gy(valid); gz = gz(valid);
        
        if length(ax) < config.tamano_ventana
            fprintf('  ⚠ Datos insuficientes después de limpieza\n');
            continue;
        end
        
        % Preprocesar (filtrado)
        ax = filtrar_senal(ax, config.frecuencia_muestreo);
        ay = filtrar_senal(ay, config.frecuencia_muestreo);
        az = filtrar_senal(az, config.frecuencia_muestreo);
        gx = filtrar_senal(gx, config.frecuencia_muestreo);
        gy = filtrar_senal(gy, config.frecuencia_muestreo);
        gz = filtrar_senal(gz, config.frecuencia_muestreo);
        
        % Separar según tipo
        es_caida = any(contains(etiqueta, config.tipos_caidas));
        
        if es_caida
            datos_caidas(idx_caida).nombre = nombre;
            datos_caidas(idx_caida).etiqueta = etiqueta;
            datos_caidas(idx_caida).datos = [ax, ay, az, gx, gy, gz];
            idx_caida = idx_caida + 1;
        else
            datos_actividades(idx_act).nombre = nombre;
            datos_actividades(idx_act).etiqueta = etiqueta;
            datos_actividades(idx_act).datos = [ax, ay, az, gx, gy, gz];
            idx_act = idx_act + 1;
        end
        
        fprintf('  ✓ Procesado correctamente\n');
        
    catch ME
        fprintf('  ❌ Error: %s\n', ME.message);
        continue;
    end
end

fprintf('\n✅ Actividades normales: %d archivos\n', length(datos_actividades));
fprintf('✅ Caídas detectadas: %d archivos\n\n', length(datos_caidas));

if isempty(datos_actividades)
    error('ERROR: No hay datos de actividades para entrenar');
end

%% === 2. CREAR VENTANAS PARA CNN-LSTM (SOLO ACTIVIDADES) ===
fprintf('========================================\n');
fprintf('  PREPARANDO DATOS PARA CNN-LSTM  \n');
fprintf('========================================\n\n');

X_actividades = []; % [6, 100, N_ventanas]
y_actividades = {}; % Etiquetas
sujeto_info = []; % Para división estratificada

for i = 1:length(datos_actividades)
    datos = datos_actividades(i).datos;
    etiqueta = datos_actividades(i).etiqueta;
    sujeto = extraer_numero_sujeto(datos_actividades(i).nombre);
    
    % Crear ventanas con solapamiento
    ventanas = crear_ventanas_cnn(datos, config.tamano_ventana, config.solapamiento);
    n_ventanas = size(ventanas, 3);
    
    X_actividades = cat(3, X_actividades, ventanas);
    y_actividades = [y_actividades; repmat({etiqueta}, n_ventanas, 1)];
    sujeto_info = [sujeto_info; repmat(sujeto, n_ventanas, 1)];
    
    fprintf('[%d/%d] %s: %d ventanas\n', i, length(datos_actividades), ...
            etiqueta, n_ventanas);
end

fprintf('\n📊 Total ventanas: %d\n', size(X_actividades, 3));
fprintf('📊 Dimensiones: [%d canales, %d muestras, %d ventanas]\n', ...
        size(X_actividades, 1), size(X_actividades, 2), size(X_actividades, 3));

%% === 3. DIVISIÓN ESTRATIFICADA (POR SUJETO) ===
fprintf('\n========================================\n');
fprintf('  DIVISIÓN TRAIN/TEST (POR SUJETO)  \n');
fprintf('========================================\n\n');

sujetos_unicos = unique(sujeto_info);
n_sujetos = length(sujetos_unicos);
n_train_sujetos = max(1, round(config.ratio_train * n_sujetos));

% Dividir sujetos
sujetos_perm = sujetos_unicos(randperm(n_sujetos));
sujetos_train = sujetos_perm(1:n_train_sujetos);
sujetos_test = sujetos_perm(n_train_sujetos+1:end);

% Índices de ventanas
train_idx = ismember(sujeto_info, sujetos_train);
test_idx = ismember(sujeto_info, sujetos_test);

X_train = X_actividades(:, :, train_idx);
X_test = X_actividades(:, :, test_idx);
y_train = y_actividades(train_idx);
y_test = y_actividades(test_idx);

fprintf('👥 Sujetos en train: %d → %d ventanas\n', length(sujetos_train), sum(train_idx));
fprintf('👥 Sujetos en test:  %d → %d ventanas\n', length(sujetos_test), sum(test_idx));

%% === 4. NORMALIZACIÓN (POR CANAL) ===
fprintf('\n🔧 Normalizando datos...\n');

% Calcular media y std por canal usando solo datos de train
mu = zeros(6, 1);
sigma = zeros(6, 1);

for canal = 1:6
    datos_canal = X_train(canal, :, :);
    datos_canal = datos_canal(:); % Vectorizar
    mu(canal) = mean(datos_canal);
    sigma(canal) = std(datos_canal);
end

% Normalizar train y test
X_train_norm = X_train;
X_test_norm = X_test;

for canal = 1:6
    X_train_norm(canal, :, :) = (X_train(canal, :, :) - mu(canal)) / (sigma(canal) + eps);
    X_test_norm(canal, :, :) = (X_test(canal, :, :) - mu(canal)) / (sigma(canal) + eps);
end

fprintf('✓ Normalización completada\n');
fprintf('  μ = [%.2f, %.2f, %.2f, %.2f, %.2f, %.2f]\n', mu);
fprintf('  σ = [%.2f, %.2f, %.2f, %.2f, %.2f, %.2f]\n', sigma);

%% === 5. ARQUITECTURA CNN-LSTM (CORREGIDA) ===
fprintf('\n========================================\n');
fprintf('  CONSTRUYENDO MODELO CNN-LSTM  \n');
fprintf('========================================\n\n');

clases_unicas = unique(y_train);
numClasses = length(clases_unicas);

fprintf('📋 Clases detectadas: %d\n', numClasses);
for i = 1:numClasses
    n = sum(strcmp(y_train, clases_unicas{i}));
    fprintf('  - %s: %d muestras (%.1f%%)\n', clases_unicas{i}, n, 100*n/length(y_train));
end

% Verificar Deep Learning Toolbox
if ~license('test', 'neural_network_toolbox')
    error('ERROR: Se requiere Deep Learning Toolbox para CNN-LSTM');
end

% ARQUITECTURA CORREGIDA - Sin problemas de dimensiones
layers = [
    sequenceInputLayer(6, 'Name', 'input', 'MinLength', config.tamano_ventana)
    
    % === BLOQUE CNN 1 ===
    convolution1dLayer(5, 64, 'Padding', 'same', 'Name', 'conv1')
    batchNormalizationLayer('Name', 'bn1')
    reluLayer('Name', 'relu1')
    dropoutLayer(0.2, 'Name', 'dropout1')
    
    % === BLOQUE CNN 2 ===
    convolution1dLayer(5, 128, 'Padding', 'same', 'Name', 'conv2')
    batchNormalizationLayer('Name', 'bn2')
    reluLayer('Name', 'relu2')
    dropoutLayer(0.3, 'Name', 'dropout2')
    
    % === BLOQUE LSTM ===
    lstmLayer(64, 'OutputMode', 'last', 'Name', 'lstm1')
    dropoutLayer(0.5, 'Name', 'dropout3')
    
    % === CLASIFICACIÓN ===
    fullyConnectedLayer(32, 'Name', 'fc1')
    reluLayer('Name', 'relu_fc')
    dropoutLayer(0.3, 'Name', 'dropout4')
    
    fullyConnectedLayer(numClasses, 'Name', 'fc_out')
    softmaxLayer('Name', 'softmax')
    classificationLayer('Name', 'output')
];

fprintf('\n📐 Arquitectura creada (OPTIMIZADA):\n');
fprintf('  - SequenceInput: 6 canales, MinLength=%d\n', config.tamano_ventana);
fprintf('  - Conv1D (64 filtros, kernel=5) + BN + ReLU + Dropout(0.2)\n');
fprintf('  - Conv1D (128 filtros, kernel=5) + BN + ReLU + Dropout(0.3)\n');
fprintf('  - LSTM (64 unidades, output=last) + Dropout(0.5)\n');
fprintf('  - FC (32 neuronas) + ReLU + Dropout(0.3)\n');
fprintf('  - FC (%d clases) + Softmax\n', numClasses);

%% === 6. CONVERTIR A FORMATO DE CELDAS ===
fprintf('\n🔄 Convirtiendo datos a formato de celdas...\n');

% Convertir train a celdas
X_train_cell = cell(size(X_train_norm, 3), 1);
for i = 1:size(X_train_norm, 3)
    X_train_cell{i} = X_train_norm(:, :, i); % [6, 100]
end

% Convertir test a celdas
X_test_cell = cell(size(X_test_norm, 3), 1);
for i = 1:size(X_test_norm, 3)
    X_test_cell{i} = X_test_norm(:, :, i); % [6, 100]
end

fprintf('✓ Conversión completada\n');
fprintf('  Train: %d secuencias de [6 × %d]\n', length(X_train_cell), size(X_train_cell{1}, 2));
fprintf('  Test:  %d secuencias de [6 × %d]\n', length(X_test_cell), size(X_test_cell{1}, 2));

%% === 7. ENTRENAMIENTO ===
fprintf('\n========================================\n');
fprintf('  ENTRENAMIENTO DEL MODELO  \n');
fprintf('========================================\n\n');

options = trainingOptions('adam', ...
    'MaxEpochs', 30, ...
    'MiniBatchSize', 64, ...
    'InitialLearnRate', 0.001, ...
    'LearnRateSchedule', 'piecewise', ...
    'LearnRateDropFactor', 0.5, ...
    'LearnRateDropPeriod', 10, ...
    'ValidationData', {X_test_cell, categorical(y_test)}, ...
    'ValidationFrequency', 30, ...
    'Shuffle', 'every-epoch', ...
    'Verbose', true, ...
    'Plots', 'training-progress', ...
    'ExecutionEnvironment', 'auto');

fprintf('⏳ Iniciando entrenamiento (esto puede tardar varios minutos)...\n\n');
tic;
net = trainNetwork(X_train_cell, categorical(y_train), layers, options);
tiempo_entrenamiento = toc;

fprintf('\n✅ Entrenamiento completado en %.1f minutos\n', tiempo_entrenamiento/60);

%% === 8. EVALUACIÓN ===
fprintf('\n========================================\n');
fprintf('  EVALUACIÓN EN TEST SET  \n');
fprintf('========================================\n\n');

[y_pred, scores] = classify(net, X_test_cell);
y_pred_str = cellstr(string(y_pred));

% Calcular métricas
acc = mean(strcmp(y_pred_str, y_test)) * 100;
fprintf('🎯 Accuracy: %.2f%%\n\n', acc);

% Matriz de confusión
figure('Position', [100 100 1200 500]);

subplot(1,2,1);
cm = confusionchart(categorical(y_test), y_pred);
cm.Title = sprintf('Matriz de Confusión (Test Accuracy: %.2f%%)', acc);
cm.RowSummary = 'row-normalized';
cm.ColumnSummary = 'column-normalized';

% Métricas por clase
subplot(1,2,2);
[precision, recall, f1] = calcular_metricas(y_test, y_pred_str, clases_unicas);
x_pos = 1:numClasses;
bar(x_pos, [precision, recall, f1], 'grouped');
set(gca, 'XTickLabel', clases_unicas, 'XTick', x_pos);
xtickangle(45);
ylabel('Score (%)');
title('Métricas por Clase');
legend('Precision', 'Recall', 'F1-Score', 'Location', 'best');
grid on;

% Reporte detallado
fprintf('%-15s | Precision | Recall | F1-Score | Support\n', 'Clase');
fprintf('----------------|-----------|--------|----------|--------\n');
for i = 1:numClasses
    support = sum(strcmp(y_test, clases_unicas{i}));
    fprintf('%-15s | %8.2f%% | %6.2f%% | %7.2f%% | %6d\n', ...
            clases_unicas{i}, precision(i), recall(i), f1(i), support);
end

%% === 9. DETECTOR DE CAÍDAS (BASADO EN REGLAS) ===
fprintf('\n========================================\n');
fprintf('  CREANDO DETECTOR DE CAÍDAS  \n');
fprintf('========================================\n\n');

if ~isempty(datos_caidas)
    detector_caidas = crear_detector_caidas(datos_caidas, config);
    fprintf('✅ Detector de caídas configurado\n');
    fprintf('  - Umbral de impacto: %.2f g\n', detector_caidas.umbral_impacto);
    fprintf('  - Umbral de quietud: %.2f g/s\n', detector_caidas.umbral_quietud);
else
    detector_caidas = [];
    fprintf('⚠ No hay datos de caídas, detector deshabilitado\n');
end

%% === 10. GUARDAR MODELO FINAL ===
fprintf('\n========================================\n');
fprintf('  GUARDANDO MODELO FINAL  \n');
fprintf('========================================\n\n');

modelo_final = struct();
modelo_final.red = net;
modelo_final.mu = mu;
modelo_final.sigma = sigma;
modelo_final.clases = clases_unicas;
modelo_final.config = config;
modelo_final.test_accuracy = acc;
modelo_final.metricas.precision = precision;
modelo_final.metricas.recall = recall;
modelo_final.metricas.f1 = f1;
modelo_final.detector_caidas = detector_caidas;
modelo_final.fecha_entrenamiento = datetime('now');

save('modelo_cnn_lstm_final.mat', 'modelo_final', '-v7.3');
fprintf('💾 Modelo guardado: modelo_cnn_lstm_final.mat\n');
fprintf('   Tamaño: %.2f MB\n', dir('modelo_cnn_lstm_final.mat').bytes/1e6);

%% === 11. FUNCIÓN DE INFERENCIA ===
fprintf('\n========================================\n');
fprintf('  PRUEBA DE INFERENCIA  \n');
fprintf('========================================\n\n');

% Ejemplo de uso
if length(X_test_cell) > 0
    ventana_prueba = X_test(:, :, 1); % Usar datos sin normalizar para la prueba completa
    resultado = inferir_actividad(ventana_prueba, modelo_final);
    
    fprintf('📊 Ejemplo de predicción:\n');
    fprintf('  - Actividad: %s (confianza: %.1f%%)\n', ...
            resultado.actividad, resultado.confianza*100);
    if resultado.es_caida
        fprintf('  - ⚠ CAÍDA DETECTADA (tipo: %s)\n', resultado.tipo_caida);
    end
end

fprintf('\n========================================\n');
fprintf('  ✅ PROCESO COMPLETADO  \n');
fprintf('========================================\n');

%% ================================================================
%% === FUNCIONES AUXILIARES ===
%% ================================================================

function etiqueta = extraer_etiqueta_mejorada(nombre_archivo)
    [~, nombre, ~] = fileparts(nombre_archivo);
    s = lower(nombre);
    
    % Priorizar detección específica
    if contains(s, 'forwardw')
        etiqueta = 'forwardw';
    elseif contains(s, 'forward')
        etiqueta = 'forward';
    elseif contains(s, 'lateralg')
        etiqueta = 'lateralg';
    elseif contains(s, 'lateral')
        etiqueta = 'lateral';
    elseif contains(s, 'backward')
        etiqueta = 'backward';
    elseif contains(s, 'run')
        etiqueta = 'run';
    elseif contains(s, 'walk')
        etiqueta = 'walk';
    elseif contains(s, 'sit')
        etiqueta = 'sit';
    else
        etiqueta = 'desconocido';
    end
end

function sujeto = extraer_numero_sujeto(nombre_archivo)
    % Extrae el número de sujeto (s10, s11, etc.)
    tokens = regexp(nombre_archivo, 's(\d+)', 'tokens');
    if ~isempty(tokens)
        sujeto = str2double(tokens{1}{1});
    else
        sujeto = 0;
    end
end

function senal = filtrar_senal(senal, fs)
    % Filtro Butterworth paso bajo
    if length(senal) > 30
        try
            fc = 20; % Hz
            [b, a] = butter(2, fc/(fs/2), 'low');
            senal = filtfilt(b, a, senal);
        catch
            % Continuar sin filtrar
        end
    end
end

function ventanas = crear_ventanas_cnn(datos, tam_ventana, solapamiento)
    % Crea ventanas en formato [6, tam_ventana, n_ventanas]
    n_muestras = size(datos, 1);
    paso = tam_ventana - solapamiento;
    ventanas = [];
    
    idx = 1;
    while (idx + tam_ventana - 1) <= n_muestras
        segmento = datos(idx:idx+tam_ventana-1, :); % [100, 6]
        ventanas = cat(3, ventanas, segmento'); % [6, 100]
        idx = idx + paso;
    end
end

function detector = crear_detector_caidas(datos_caidas, config)
    % Analiza datos de caídas para calibrar umbrales
    max_impactos = [];
    
    for i = 1:length(datos_caidas)
        datos = datos_caidas(i).datos;
        ax = datos(:, 1); ay = datos(:, 2); az = datos(:, 3);
        mag = sqrt(ax.^2 + ay.^2 + az.^2);
        max_impactos = [max_impactos; max(abs(diff(mag)))];
    end
    
    detector.umbral_impacto = mean(max_impactos) * 0.7; % 70% del promedio
    detector.umbral_quietud = 0.5; % g/s
    detector.ventana_analisis = 50; % 1 segundo
end

function [precision, recall, f1] = calcular_metricas(y_true, y_pred, clases)
    n = length(clases);
    precision = zeros(n, 1);
    recall = zeros(n, 1);
    f1 = zeros(n, 1);
    
    for i = 1:n
        TP = sum(strcmp(y_true, clases{i}) & strcmp(y_pred, clases{i}));
        FP = sum(~strcmp(y_true, clases{i}) & strcmp(y_pred, clases{i}));
        FN = sum(strcmp(y_true, clases{i}) & ~strcmp(y_pred, clases{i}));
        
        precision(i) = 100 * TP / (TP + FP + eps);
        recall(i) = 100 * TP / (TP + FN + eps);
        f1(i) = 2 * precision(i) * recall(i) / (precision(i) + recall(i) + eps);
    end
end

function resultado = inferir_actividad(ventana, modelo)
    % Función de inferencia completa
    % Input: ventana [6, 100] sin normalizar
    % Output: estructura con predicción
    
    % Normalizar
    ventana_norm = ventana;
    for canal = 1:6
        ventana_norm(canal, :) = (ventana(canal, :) - modelo.mu(canal)) / ...
                                 (modelo.sigma(canal) + eps);
    end
    
    % Detectar caída primero
    if ~isempty(modelo.detector_caidas)
        mag = sqrt(sum(ventana(1:3, :).^2, 1));
        max_cambio = max(abs(diff(mag)));
        
        if max_cambio > modelo.detector_caidas.umbral_impacto
            resultado.es_caida = true;
            resultado.actividad = 'CAIDA';
            resultado.tipo_caida = 'detectada';
            resultado.confianza = 0.95;
            return;
        end
    end
    
    % Clasificar actividad normal
    [pred, scores] = classify(modelo.red, ventana_norm);
    resultado.es_caida = false;
    resultado.actividad = char(pred);
    resultado.confianza = max(scores);
    resultado.tipo_caida = 'ninguna';
end
