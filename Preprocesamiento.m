
clear; clc;

%% --- CONFIGURACIÓN ---
carpeta_datos = 'C:\Users\marif\Downloads\125\CN';   
etiqueta_actual = 'CN';                  
prefijo_grabacion = 'N_pwm150_grab';
nombre_csv_salida = 'N_pwm150.csv';
n_ventanas = 4;
ventana_movmedian = 50;   
Fs = 1/0.00505;          

%% --- CARGA DE DATOS: lee TODOS los .csv de la carpeta ---
archivos = dir(fullfile(carpeta_datos, '*.csv'));
nFiles = numel(archivos);

if nFiles == 0
    error('No se encontró ningún archivo .csv en: %s', carpeta_datos);
end

tiempo_ms = cell(1, nFiles);
ax  = cell(1, nFiles);
ay  = cell(1, nFiles);
az  = cell(1, nFiles);
nombres_rep = cell(1, nFiles);

for i = 1:nFiles
    ruta_completa = fullfile(archivos(i).folder, archivos(i).name);
    T = readtable(ruta_completa);

    % Verificación de columnas esperadas - si falla aquí, tus encabezados
    % reales no coinciden con el supuesto (tiempo_ms, ax, ay, az)
    columnas_esperadas = {'tiempo_ms','ax','ay','az'};
    for c = 1:numel(columnas_esperadas)
        if ~ismember(columnas_esperadas{c}, T.Properties.VariableNames)
            error(['El archivo "%s" no tiene una columna llamada "%s". ', ...
                   'Revisa el encabezado real del CSV y ajusta el script.'], ...
                   archivos(i).name, columnas_esperadas{c});
        end
    end

    tiempo_ms{i} = T.tiempo_ms;
    ax{i} = T.ax;
    ay{i} = T.ay;
    az{i} = T.az;
    nombres_rep{i} = archivos(i).name;

    fprintf('Cargado (%d/%d): %s  (%d muestras)\n', i, nFiles, archivos(i).name, height(T));
end

% Conversión a segundos
tiempo_s = cell(1, nFiles);
for i = 1:nFiles
    tiempo_s{i} = tiempo_ms{i} / 1000;
end

colores = {'r','b','g','c','m','y','k', [0.5 0.2 0.8], [0.9 0.5 0.1], [0.1 0.6 0.6]};


%% --- GRÁFICA 1: comparación cruda de todas las repeticiones ---
figure('Name','Comparación de repeticiones - misma configuración','NumberTitle','off');

ejes = {ax, ay, az};
nombres_ejes = {'Aceleración en X','Aceleración en Y','Aceleración en Z'};
ylabels = {'ax','ay','az'};

for e = 1:3
    subplot(3,1,e)
    hold on
    h = gobjects(1, nFiles);
    for i = 1:nFiles
        color_idx = mod(i-1, numel(colores)) + 1;
        h(i) = plot(tiempo_s{i}, ejes{e}{i}, 'Color', colores{color_idx}, 'LineWidth', 1);
    end
    hold off
    title(nombres_ejes{e})
    xlabel('Tiempo (s)')
    ylabel(ylabels{e})
    lgd = legend(h, nombres_rep, 'Interpreter', 'none');
    lgd.ItemHitFcn = @toggleVisibility;
    grid on
end
sgtitle('Comparación de repeticiones - Carga Nominal PWM 150')

%% --- RECORTE: descarta el transitorio inicial (t < 3 s) ---
tiempo_s_recortado = cell(1, nFiles);
ax_recortado = cell(1, nFiles);
ay_recortado = cell(1, nFiles);
az_recortado = cell(1, nFiles);

for i = 1:nFiles
    idx = tiempo_s{i} >= 3;
    tiempo_s_recortado{i} = tiempo_s{i}(idx);
    ax_recortado{i} = ax{i}(idx);
    ay_recortado{i} = ay{i}(idx);
    az_recortado{i} = az{i}(idx);
end

%% --- LIMPIEZA DE OUTLIERS Y SATURACIÓN ---
limite_max = 32767;
limite_min = -32768;

tiempo_s_limpio = cell(1, nFiles);
ax_limpio = cell(1, nFiles);
ay_limpio = cell(1, nFiles);
az_limpio = cell(1, nFiles);

for i = 1:nFiles
    saturado = (ax_recortado{i} >= limite_max) | (ax_recortado{i} <= limite_min) | ...
               (ay_recortado{i} >= limite_max) | (ay_recortado{i} <= limite_min) | ...
               (az_recortado{i} >= limite_max) | (az_recortado{i} <= limite_min);

    outlier_ax = isoutlier(ax_recortado{i}, 'movmedian', ventana_movmedian);
    outlier_ay = isoutlier(ay_recortado{i}, 'movmedian', ventana_movmedian);
    outlier_az = isoutlier(az_recortado{i}, 'movmedian', ventana_movmedian);

    descartar = saturado | outlier_ax | outlier_ay | outlier_az;

    tiempo_s_limpio{i} = tiempo_s_recortado{i}(~descartar);
    ax_limpio{i} = ax_recortado{i}(~descartar);
    ay_limpio{i} = ay_recortado{i}(~descartar);
    az_limpio{i} = az_recortado{i}(~descartar);

    fprintf('%s - puntos descartados: %d de %d\n', nombres_rep{i}, sum(descartar), numel(descartar));
end

%% --- GRÁFICA 2: comparación de datos depurados ---
figure('Name','Comparación de repeticiones - datos depurados','NumberTitle','off');

ejes_limpios = {ax_limpio, ay_limpio, az_limpio};

for e = 1:3
    subplot(3,1,e)
    hold on
    h = gobjects(1, nFiles);
    for i = 1:nFiles
        color_idx = mod(i-1, numel(colores)) + 1;
        h(i) = plot(tiempo_s_limpio{i}, ejes_limpios{e}{i}, 'Color', colores{color_idx}, 'LineWidth', 1);
    end
    hold off
    title(nombres_ejes{e})
    xlabel('Tiempo (s)')
    ylabel(ylabels{e})
    lgd = legend(h, nombres_rep, 'Interpreter', 'none');
    lgd.ItemHitFcn = @toggleVisibility;
    grid on
end
sgtitle('Comparación de repeticiones (depuradas) - [PWM 150 CN]')

%% --- FFT: frecuencia dominante por repetición (usando eje ax) ---
senales = ax_limpio;

frecuencias_dominantes = zeros(1, nFiles);

figure('Name','Espectros FFT - comparación de frecuencia dominante','NumberTitle','off');

for i = 1:nFiles
    senal = senales{i};
    senal = senal - mean(senal); % remover componente DC

    N = length(senal);
    Y = fft(senal);
    P2 = abs(Y/N);
    P1 = P2(1:floor(N/2)+1);
    P1(2:end-1) = 2*P1(2:end-1);
    f = Fs*(0:floor(N/2))/N;

    [~, idx_max] = max(P1(2:end)); % se excluye el bin 0 (DC)
    frecuencias_dominantes(i) = f(idx_max + 1);

    subplot(nFiles, 1, i)
    plot(f, P1)
    title([nombres_rep{i}, ' - Frecuencia dominante: ', num2str(frecuencias_dominantes(i)), ' Hz'], ...
          'Interpreter', 'none')
    xlabel('Frecuencia (Hz)')
    ylabel('|Amplitud|')
    xlim([0, Fs/2])
    grid on
end
sgtitle('Comparación de espectros FFT entre repeticiones')

disp('Frecuencias dominantes por repetición:')
disp(table(nombres_rep', frecuencias_dominantes', 'VariableNames', {'Repeticion', 'Frecuencia_Hz'}))

%% --- FRAGMENTACIÓN EN VENTANAS + EXPORTACIÓN A CSV ---
T_total = table();

for i = 1:nFiles
    t = tiempo_s_limpio{i};
    ax_i = ax_limpio{i};
    ay_i = ay_limpio{i};
    az_i = az_limpio{i};

    grabacion_id_str = [prefijo_grabacion, num2str(i)];

    t_inicio = t(1);
    t_fin = t(end);
    duracion = t_fin - t_inicio;
    duracion_ventana = duracion / n_ventanas;

    fprintf('%s - duración total: %.3f s, duración por ventana: %.3f s\n', ...
            nombres_rep{i}, duracion, duracion_ventana);

    for w = 1:n_ventanas
        t_ini_ventana = t_inicio + (w-1) * duracion_ventana;
        t_fin_ventana = t_inicio + w * duracion_ventana;

        if w == n_ventanas
            idx_ventana = t >= t_ini_ventana & t <= t_fin_ventana;
        else
            idx_ventana = t >= t_ini_ventana & t < t_fin_ventana;
        end

        n_muestras = sum(idx_ventana);
        if n_muestras == 0
            warning('Ventana vacía: %s, ventana %d', nombres_rep{i}, w);
            continue
        end

        muestra_id_num = w - 1;

        tiempo_ms_col = t(idx_ventana) * 1000;
        ax_col = ax_i(idx_ventana);
        ay_col = ay_i(idx_ventana);
        az_col = az_i(idx_ventana);

        etiqueta = repmat({etiqueta_actual}, n_muestras, 1);
        muestra_id = repmat(muestra_id_num, n_muestras, 1);
        grabacion_id = repmat({grabacion_id_str}, n_muestras, 1);

        T_w = table(tiempo_ms_col, ax_col, ay_col, az_col, etiqueta, muestra_id, grabacion_id, ...
            'VariableNames', {'tiempo_ms', 'ax', 'ay', 'az', 'etiqueta', 'muestra_id', 'grabacion_id'});

        T_total = [T_total; T_w];
    end
end

writetable(T_total, nombre_csv_salida)
fprintf('Archivo exportado "%s" con %d filas totales, %d ventanas en total\n', ...
        nombre_csv_salida, height(T_total), nFiles * n_ventanas);

%% --- Función local para alternar visibilidad ---
function toggleVisibility(~, event)
    if strcmp(event.Peer.Visible, 'on')
        event.Peer.Visible = 'off';
    else
        event.Peer.Visible = 'on';
    end
end