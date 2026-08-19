# Reporte final de Machine Learning

## Contrato experimental

- TRAIN: abril, mayo y junio 2026 (433 eventos fantasma).
- TEST: 1-24 julio 2026 (107 eventos fantasma).
- Orden ejecutado: **t-SNE -> HMM -> GMM**.
- Unidad PIP configurada: **0.25**.
- El test no participa en scaler, t-SNE, HMM, GMM ni mapeos de targets.

## Definicion operacional del fantasma y rastro

El proyecto recibido no incluye el archivo fuente `Ghosts_in_swings.txt` citado por las indicaciones. Para dejar el pipeline ejecutable, el evento fantasma se operacionaliza como la **confirmacion de un swing externo** ya calculado por el motor ChartPrime/SMC del proyecto. Desde la vela siguiente se cuenta un rastro cada vez que aparece una nueva extension hacia afuera del maximo o minimo acumulado. Los conteos son acumulados a 3, 5, 10 y 15 minutos. Esta definicion es causal y auditable, pero debe sustituirse por la logica literal del indicador del docente si se incorpora ese archivo fuente.

## Evidencia de las tres etapas

- t-SNE: 90 anclas, perplexity 25, KL final 0.327720234092377.
- HMM: estados QUIET/ACTIVE/INTENSE, log-verosimilitud TRAIN -1713.12068011789.
- GMM: 7 componentes, BIC -47712.1738330744, convergencia 1, 39 features seleccionadas + embedding/posteriores.
- Features causales: 132.

## Metricas sobre TEST de julio

| Horizonte | MAE modelo | RMSE modelo | Exactitud exacta | Exactitud ±1 | MAE baseline | Mejora MAE |
|---|---:|---:|---:|---:|---:|---:|
| 3 min | 0.9182 | 1.0752 | 27.10% | 85.05% | 0.9260 | 0.84% |
| 5 min | 1.1427 | 1.4193 | 27.10% | 69.16% | 1.1698 | 2.32% |
| 10 min | 1.5758 | 1.9381 | 20.56% | 53.27% | 1.6479 | 4.38% |
| 15 min | 2.1674 | 2.7665 | 13.08% | 44.86% | 2.2697 | 4.51% |

## Artefactos

- `datasets/final_ml/train_ghost_features.csv`
- `datasets/final_ml/test_ghost_features.csv`
- `datasets/final_ml/test_predictions.csv`
- `models/final_ml/ghost_tsne_hmm_gmm.bin`
- `final_ml_demo.pl`
- `verify_final_ml.pl`

