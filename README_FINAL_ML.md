# ML final — fantasmas 3/5/10/15 min

Este bloque completa el flujo demostrable de Machine Learning sobre los CSV oficiales adjuntos.

## Datos oficiales incluidos

- `data_final/2026_04.csv`
- `data_final/2026_05.csv`
- `data_final/2026_06.csv`
- `data_final/2026_Abril-Junio.csv` (copia consolidada de referencia)
- `data_final/2026_07_24.csv`

TRAIN usa abril+mayo+junio. TEST usa exclusivamente julio 1–24.

## Orden solicitado

El ejecutable final trabaja explícitamente en este orden:

1. **t-SNE**: reduce el espacio causal escalado a 2D sobre anclas de TRAIN. Como t-SNE no tiene `transform` nativo, los eventos no-ancla y TEST se proyectan por interpolación k-NN usando exclusivamente las anclas de TRAIN.
2. **HMM**: modela la secuencia temporal sobre el embedding t-SNE con estados `QUIET`, `ACTIVE`, `INTENSE` aprendidos de TRAIN.
3. **GMM**: recibe `[t-SNE x, t-SNE y, posterior HMM]`, selecciona número de componentes por BIC en TRAIN y produce la predicción final de rastros.

## Objetivo

Cada evento fantasma genera cuatro targets numéricos:

- `target_trace_3`
- `target_trace_5`
- `target_trace_10`
- `target_trace_15`

El conteo comienza en la vela siguiente al evento y es acumulativo.

## Features evidenciables

Además de SMC ya existente (BOS/CHoCH, EQH/EQL, FVG, Order Block, BSL/SSL, ATR y volumen), se agregan contextos causales 1m/10m/60m con:

- ATR en PIPs;
- volumen y EMA(9) de volumen;
- VWAP;
- perfil de volumen POC/VAH/VAL;
- Fibonacci 0.382/0.500/0.618;
- soporte/resistencia;
- tendencia/canal con bandera de 3 toques;
- soporte/resistencia 4h/diario/semanal;
- supply/demand;
- distancias a BSL/SSL, FVG, OB, EQH/EQL y BOS/CHoCH convertidas a PIPs.

## Ejecutar

La entrega ya incluye datasets derivados, modelo entrenado, predicciones y reporte. Para verificar sin reentrenar:

```bash
perl verify_final_ml.pl
perl final_ml_demo.pl --n 12
```

Para regenerar todo desde los CSV oficiales:

```bash
perl final_ml_pipeline.pl --rebuild
```

Prueba más rápida del entrenamiento t-SNE:

```bash
perl final_ml_pipeline.pl --rebuild --fast
```

## Evidencia para exposición

Abrir:

- `reports/final_ml/FINAL_ML_REPORT.md`
- `datasets/final_ml/test_predictions.csv`

Y ejecutar en terminal:

```bash
perl final_ml_demo.pl --n 12
```

La tabla muestra `predicho/real` para 3, 5, 10 y 15 minutos, además del estado HMM y cluster GMM.

## Importante sobre `Ghosts_in_swings.txt`

Las indicaciones finales citan un archivo fuente externo `Ghosts_in_swings.txt`, pero ese archivo **no está dentro del ZIP ni entre los adjuntos recibidos**. Por eso la entrega deja una definición operacional reproducible: cada confirmación del swing externo (`ChartPrimeHigh/Low`) es una aparición del fantasma y cada nueva extensión hacia afuera del máximo/mínimo acumulado, desde la vela siguiente, cuenta como rastro.

Esto hace que todo el ML sea funcional, causal, auditable y demostrable. Si se incorpora posteriormente el archivo literal del indicador del docente, solo debe sustituirse la función de aparición/rastro en `FinalGhostDatasetBuilder.pm`; el resto del pipeline queda intacto.

## Evidencia visual y técnica

```bash
perl final_ml_evidence.pl
```

Genera:

- `datasets/final_ml/tsne_hmm_gmm_embedding.csv`
- `reports/final_ml/tsne_hmm_gmm.svg`
- `reports/final_ml/MODEL_EVIDENCE.txt`

El SVG colorea el embedding t-SNE por estado HMM y diferencia TRAIN/TEST. El CSV conserva también el cluster GMM de cada evento.

## Flujo Git

Ver `GIT_ENTREGA_FINAL.md` para los comandos de rama, `git add`, commit, push y Pull Request.

## Dependencia de la interfaz gráfica original

El pipeline final de Machine Learning (`final_ml_pipeline.pl`, `verify_final_ml.pl`, `final_ml_demo.pl` y `final_ml_evidence.pl`) no depende de Tk. El archivo original `market.pl` sí requiere el módulo externo de Perl **Tk**. En el entorno de validación usado para preparar esta entrega Tk no está instalado, por lo que la GUI completa no se ejecutó aquí; antes de lanzar `perl market.pl` en WSL/Linux asegúrate de que `Tk` esté disponible.

