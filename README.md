# Diagnóstico de Fallos en Motor DC Mediante Análisis de Vibración con IA

## Descripción del proyecto

Sistema de mantenimiento predictivo basado en aprendizaje automático que clasifica el estado operativo de un motor DC a partir de su señal de vibración tri-axial. El modelo identifica tres condiciones: **desequilibrio de masa (CD)**, **carga nominal (CN)** y **operación en vacío (SC)**, con robustez demostrada ante variaciones de velocidad y magnitud de desequilibrio.

El proyecto cubre el pipeline completo: diseño y construcción del banco de pruebas físico, captura del dataset, preprocesamiento, selección de representación de señal, búsqueda de hiperparámetros y validación en tiempo real.

---

## Hardware utilizado

| Componente | Descripción |
|---|---|
| Microcontrolador | Arduino Uno |
| Acelerómetro | MPU-6050 (±4g, I2C a 400 kHz) |
| Motor | Motor DC (controlado por PWM en pin D9) |
| Driver de potencia | MOSFET 30N06L + diodo flyback |
| Estructura | Base de madera en dos niveles; soporte del motor impreso en 3D |

El sensor se montó a 8 mm del cuerpo del motor con orientación fija en todas las capturas. La frecuencia de muestreo real obtenida fue de **197.8 Hz**.

---

## Condiciones operativas

| Etiqueta | Descripción |
|---|---|
| `SC` | Sin carga (operación en vacío) |
| `CN` | Carga nominal — dos tornillos M5 de 5 g dispuestos simétricamente |
| `CD` | Desequilibrio de masa — incluye dos severidades (D1: +3 g, D2: +5 g) |

Las condiciones se inducen mediante un fixture intercambiable que se presiona sobre el eje del motor. Las cuatro velocidades de operación se controlan por PWM: valores 100, 125, 150 y 175 durante el entrenamiento.

---

## Dataset

- **80 grabaciones** en total (16 combinaciones condición × velocidad PWM, 5 repeticiones cada una)
- **Duración por grabación:** 22 s (19 s útiles tras descartar los primeros 3 s de transitorio)
- **Fragmentación:** 4 ventanas por grabación → **320 ventanas** totales
- **Muestras por ventana:** variable (720–962); resampleadas a **900 puntos** uniformes
- **Partición:** 51 grabaciones entrenamiento / 13 validación / 16 prueba (estratificada por etiqueta × PWM)

---

## Preprocesamiento

El preprocesamiento se divide entre dos entornos:

**MATLAB** (`matlab/preprocessing.m`):
1. Recorte de los primeros 3 s (transitorio de arranque y kick-start)
2. Eliminación de saturaciones del sensor (límites ±32767 en escala cruda de 16 bits)
3. Detección y eliminación de outliers con `isoutlier` (método `movmedian`, ventana de 50 muestras)
4. Fragmentación en 4 ventanas por duración temporal y exportación a CSV

**Python** (`python/pipeline.ipynb`):
1. Resampleo a 900 puntos por ventana (interpolación lineal sobre tiempo real, no sobre índice)
2. Normalización z-score (media y desviación estándar calculadas solo en entrenamiento)
3. Codificación one-hot de etiquetas con `LabelEncoder` + `to_categorical`

---

## Modelo

**Arquitectura:** Red neuronal convolucional 1D

```
Input (900, 3)
  → Conv1D [16 filtros, kernel 15, ReLU]
  → Conv1D [16 filtros, kernel 15, ReLU]
  → Conv1D [16 filtros, kernel 15, ReLU]
  → GlobalAveragePooling1D
  → Dense [3, Softmax]
```

**Hiperparámetros finales:**

| Parámetro | Valor |
|---|---|
| Capas convolucionales | 3 |
| Filtros por capa | 16 |
| Tamaño de kernel | 15 muestras |
| Tasa de aprendizaje | 0.0005 |
| Optimizador | Adam |
| Función de pérdida | Categorical crossentropy |
| Tamaño de lote | 16 |
| Épocas máximas | 100 (parada temprana activada en época 25) |

La configuración óptima se seleccionó mediante búsqueda exhaustiva en malla sobre 36 combinaciones, con verificación multi-semilla (3 semillas) del top 10 para separar desempeño estructural de variabilidad por inicialización aleatoria.

---

## Resultados

### Conjunto de prueba (evaluación estática)

| Clase | Precisión | Recall | F1 | Ventanas |
|---|---|---|---|---|
| CD | 1.00 | 1.00 | 1.00 | 32 |
| CN | 1.00 | 1.00 | 1.00 | 16 |
| SC | 1.00 | 1.00 | 1.00 | 16 |
| **Global** | **1.00** | **1.00** | **1.00** | **64** |

### Validación en tiempo real (60 ventanas, 3 velocidades PWM)

| PWM | CN (%) | SC (%) | CD1 (%) | CD2 (%) | Global (%) |
|---|---|---|---|---|---|
| 200 | 96.79 | 99.99 | 99.91 | 95.81 | 98.13 |
| 175 | 99.98 | 99.29 | 99.86 | 99.76 | 99.72 |
| 150 | 96.23 | 97.96 | 99.88 | 99.80 | 98.47 |
| **Promedio** | **97.67** | **99.08** | **99.88** | **98.46** | **98.77** |

El modelo clasificó correctamente las 60 ventanas, incluyendo PWM = 200, velocidad fuera del rango de entrenamiento. El modelo también distinguió correctamente CD1 de CD2 pese a haberlas entrenado bajo una sola etiqueta.

---

## Instalación y uso

### Requisitos

```
python >= 3.9
tensorflow >= 2.x
numpy
pandas
scipy
scikit-learn
pyserial       # solo para inferencia en tiempo real
```

```bash
pip install tensorflow numpy pandas scipy scikit-learn pyserial
```

### Inferencia en tiempo real

```bash
python python/inference_realtime.py --port COM3 --baudrate 115200
```

El script acumula ~4.5 s de señal en un buffer deslizante, aplica el mismo pipeline de preprocesamiento del entrenamiento (resampleo a 900 puntos + z-score con estadísticos del entrenamiento) y emite la clase predicha junto con el nivel de confianza.

### Reentrenar el modelo

Abrir y ejecutar `RedProyecto.ipynb` en Google Colab o localmente. El notebook cubre desde la carga del dataset hasta la exportación del modelo entrenado.

---

## Recursos adicionales

- [Video de funcionamiento en tiempo real]([https://youtube.com](https://www.youtube.com/watch?v=mS4_wGf423M)) 
