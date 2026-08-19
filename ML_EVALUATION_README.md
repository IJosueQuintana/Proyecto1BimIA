# Evaluación temporal del dataset ML

## Método principal

El proyecto usa separación por sesiones completas y orden cronológico:

- Entrenamiento: `2026_03.csv`, `2026_06_29.csv`, `2026_07_06.csv`
- Validación: `2026_07_13.csv`
- Test final reservado: `2026_07_20.csv`

No se realiza un hold-out aleatorio 60/40, 70/30 u 80/20 porque mezclar filas de una serie financiera puede producir fuga temporal.

## Ejecución

```bash
perl ml_pipeline.pl
```

## Evaluaciones generadas

1. Baseline Zero Rule sobre TRAIN -> VALIDATION.
2. Baseline Random Prediction sobre TRAIN -> VALIDATION.
3. Walk-forward de desarrollo:
   - Marzo -> 29 de junio
   - Marzo + 29 de junio -> 6 de julio
   - Marzo + 29 de junio + 6 de julio -> 13 de julio
4. El 20 de julio no participa en ninguna selección de modelo.

## Verificación automática

Antes de evaluar, `Market::ML::TemporalSplit` comprueba que:

- Cada split esté ordenado.
- TRAIN termine antes de VALIDATION.
- VALIDATION termine antes de TEST.
- No exista solapamiento temporal entre los conjuntos.

## Corrección de snapshots acumulativos
Los archivos 2026_07_13.csv y 2026_07_20.csv contienen historial acumulado desde el 1 de julio. El pipeline usa todo ese historial para calcular indicadores, pero asigna filas ML por `confirmation_timestamp` real:
- TRAIN: hasta el último timestamp de 2026_07_06.csv.
- VALIDATION: únicamente timestamps posteriores al cierre de TRAIN.
- TEST: únicamente timestamps posteriores al cierre de VALIDATION.
Esto evita duplicados y solapamiento temporal sin perder contexto para ATR, pivotes, SMC, FVG y Order Blocks.

## Árbol de decisión supervisado

El pipeline incorpora `Market/ML/DecisionTreeClassifier.pm`, un árbol CART
multiclase con impureza Gini. Se prueban profundidades 2, 3, 4 y 5 mediante
walk-forward. La selección usa el Macro F1 acumulado de todos los folds para
que un fold pequeño no tenga el mismo peso que uno grande.

Se excluyen obligatoriamente del entrenamiento:

- metadata e identificadores;
- timestamps e índices de fila;
- `target`;
- `liquidity_state`, `swept_index` y `resolved_index`.

Las tres últimas columnas describen el desenlace de liquidez y utilizarlas como
entradas produciría fuga de información respecto a RUN, GRAB y SWEEP.

El conjunto `2026_07_20.csv` continúa reservado y no participa en selección de
profundidad ni en el reporte de desarrollo.

## k-Nearest Neighbors con escalamiento causal

Se incorporaron `Market/ML/StandardScaler.pm` y `Market/ML/KNNClassifier.pm`.
El escalador se ajusta exclusivamente con las filas de entrenamiento de cada fold.
Las variables numéricas se estandarizan con media y desviación del TRAIN.
Las variables categóricas se codifican one-hot usando únicamente categorías vistas en TRAIN.
Se prueban k = 3, 5, 7, 9 y 11 y se selecciona por Macro F1 acumulado walk-forward,
con desempate por accuracy acumulada y menor k. El TEST FINAL continúa reservado.

## t-SNE tensorial

La etapa exploratoria t-SNE se ejecuta aparte para no volver más lento el pipeline supervisado:

```bash
perl ml_pipeline.pl
perl tsne_pipeline.pl
```

Parámetros opcionales:

```bash
perl tsne_pipeline.pl PERPLEXITY ITERACIONES
perl tsne_pipeline.pl 30 750
```

Implementación:

- `Market/ML/TSNE.pm`: t-SNE exacto con `AI::MXNet::NDArray`.
- `Market/ML/TSNEPipeline.pm`: selección de variables, escalamiento, conversión tensorial y exportación.
- `tsne_pipeline.pl`: ejecuta t-SNE sobre TRAIN + VALIDATION.

Salida:

```text
datasets/ml_pipeline/tsne_development_projection.csv
```

El archivo contiene `tsne_x`, `tsne_y`, `target` y metadatos para graficar cada pivote.

Reglas metodológicas:

- `2026_07_20.csv` no participa.
- `target` se conserva únicamente para colorear/interpretar el gráfico; no entra en el tensor.
- t-SNE se usa para visualización exploratoria, no como clasificador.
- GMM y HMM deben entrenarse con las variables originales escaladas, no con las coordenadas t-SNE.
- El escalador se ajusta con el conjunto de desarrollo utilizado en esta visualización.

## t-SNE compatible con Perl 5.42 / MXNet 1.9.1

La implementación anterior dependía de operadores no disponibles o inestables en AI::MXNet 1.9.1 para Perl (`triu_indices`, conversiones booleanas con `asscalar`, `astype/copyto`).

La versión actual conserva el algoritmo t-SNE exacto y la separación temporal, pero usa módulos numéricos compatibles:

- `Market/ML/TSNE/DistanceEngine.pm`: distancias cuadráticas por pares.
- `Market/ML/TSNE/Perplexity.pm`: búsqueda binaria de beta para alcanzar la perplexity.
- `Market/ML/TSNE/ProbabilityMatrix.pm`: probabilidades conjuntas simétricas.
- `Market/ML/TSNE/Optimizer.pm`: KL, early exaggeration, momentum, ganancias adaptativas y descenso de gradiente.
- `Market/ML/TSNE/TSNE.pm`: coordinador del algoritmo.
- `Market/ML/TSNE.pm`: fachada compatible con los imports anteriores.

Ejecución normal:

```bash
perl tsne_pipeline.pl
```

Prueba rápida:

```bash
perl tsne_pipeline.pl 30 25
```

El archivo `2026_07_20.csv` continúa reservado como TEST FINAL y no participa en t-SNE.

## Semilla reproducible y visualización t-SNE

La inicialización de t-SNE es aleatoria. Para poder repetir exactamente un experimento se usa una semilla fija. La semilla predeterminada es `42` y puede indicarse como tercer argumento:

```bash
perl tsne_pipeline.pl 30 750 42
```

Orden de argumentos: `perplexity`, `iteraciones`, `semilla`.

La semilla, la perplexity y el número de iteraciones se guardan también en `tsne_development_projection.csv` para asegurar la trazabilidad del experimento.

Para generar el gráfico SVG sin dependencias externas:

```bash
perl plot_tsne.pl
```

Salida:

```text
datasets/ml_pipeline/tsne_development_projection.svg
```

La semilla controla la inicialización de t-SNE. Con los mismos datos, parámetros y semilla se obtiene la misma proyección. Cambiar la semilla permite comprobar si la estructura visual es estable y no producto de una inicialización particular.

## Visualizador web interactivo de t-SNE

Después de generar la proyección:

```bash
perl tsne_pipeline.pl 30 750 42
perl plot_tsne.pl
```

`plot_tsne.pl` genera:

```text
Visualization/tsne_interactive.html
```

y trata de abrirlo automáticamente con `wslview`, `xdg-open` o `gio`.

El visualizador utiliza Plotly desde CDN, por lo que necesita conexión a internet al abrir el HTML. Incluye:

- filtros por `RUN`, `GRAB` y `SWEEP`;
- filtro por archivo fuente;
- filtro por lado del pivote;
- filtro por sesión/dataset;
- búsqueda por `pivot_id`;
- zoom, desplazamiento y hover;
- control de tamaño y opacidad;
- exportación a PNG.

Para generar el HTML sin intentar abrir el navegador:

```bash
perl plot_tsne.pl --no-open
```

El gráfico SVG anterior se conserva en:

```bash
perl plot_tsne_svg.pl
```

## Visualizador t-SNE interactivo V2

Después de generar la proyección:

```bash
perl tsne_pipeline.pl 30 750 42
perl plot_tsne.pl
```

El visualizador permite colorear por target, archivo, pivote, estructura, liquidez,
FVG y Order Block; filtrar muestras; ocultar el panel lateral; descargar PNG; y
hacer clic en un punto para revisar sus variables estructurales. El archivo se
genera en `Visualization/tsne_interactive.html`.
