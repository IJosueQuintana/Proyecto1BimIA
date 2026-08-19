# ComparaciÃ³n Dataset V1 vs V2

**TEST permanece reservado y no se lee.**

## V1

- TRAIN: **259**
- VALIDATION: **29**
- Features originales: **67**

| Componentes | Dimensiones | Accuracy | Macro-F1 | BIC | DistribuciÃ³n TRAIN |
|---:|---:|---:|---:|---:|---|
| 2 | 81 | 0.5862 | 0.2464 | 45058.72 | 258 / 1 |
| 3 | 81 | 0.5862 | 0.2464 | 44929.16 | 257 / 1 / 1 |
| 4 | 81 | 0.5862 | 0.2464 | 41892.73 | 239 / 1 / 1 / 18 |
| 5 | 81 | 0.5862 | 0.2464 | 29916.56 | 139 / 1 / 1 / 18 / 100 |

**Mejor configuraciÃ³n:** 5 componentes, accuracy 0.5862, Macro-F1 0.2464.

## V2

- TRAIN: **257**
- VALIDATION: **29**
- Features originales: **17**

| Componentes | Dimensiones | Accuracy | Macro-F1 | BIC | DistribuciÃ³n TRAIN |
|---:|---:|---:|---:|---:|---|
| 2 | 21 | 0.5862 | 0.2464 | 12848.10 | 256 / 1 |
| 3 | 21 | 0.5862 | 0.2464 | 9724.63 | 188 / 1 / 68 |
| 4 | 21 | 0.5862 | 0.2464 | 9741.99 | 188 / 1 / 1 / 67 |
| 5 | 21 | 0.4483 | 0.2063 | 7883.70 | 157 / 1 / 1 / 58 / 40 |

**Mejor configuraciÃ³n:** 3 componentes, accuracy 0.5862, Macro-F1 0.2464.

## ComparaciÃ³n final

- Cambio Macro-F1 V2 - V1: **+0.0000**
- Cambio accuracy V2 - V1: **+0.0000**
- t-SNE V1: `/home/Josue/Proyecto1.1BimIA/datasets/ml_pipeline/comparison_v1_v2/tsne_v1.csv` (81 dimensiones, KL=0.533907)
- t-SNE V2: `/home/Josue/Proyecto1.1BimIA/datasets/ml_pipeline/comparison_v1_v2/tsne_v2.csv` (21 dimensiones, KL=0.618668)

## Criterio

V2 se considera superior si mejora Macro-F1 o si mantiene mÃ©tricas similares con componentes menos colapsados y mucha menor dimensionalidad. Si ambos datasets siguen mapeando casi todo a SWEEP, la evidencia apunta a que el problema principal estÃ¡ en la definiciÃ³n de las observaciones y etiquetas, no solo en la selecciÃ³n de features.
