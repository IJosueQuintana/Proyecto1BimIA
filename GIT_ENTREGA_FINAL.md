# Git — entrega ML final

## Rama recomendada

```bash
git checkout -b feature/final-ml-ghost-prediction
```

## Verificar antes de agregar

```bash
perl verify_final_ml.pl
perl final_ml_demo.pl --n 12
perl final_ml_evidence.pl
```

El verificador debe terminar en:

```text
FINAL ML VERIFICATION: PASS
```

## Archivos principales a versionar

```bash
git add \
  Market/ML/FinalGhostFeatureSchema.pm \
  Market/ML/FinalGhostDatasetBuilder.pm \
  Market/ML/FinalGhostIO.pm \
  Market/ML/FinalGhostModel.pm \
  Market/ML/HiddenMarkovModel.pm \
  final_ml_pipeline.pl \
  final_ml_demo.pl \
  final_ml_evidence.pl \
  verify_final_ml.pl \
  README_FINAL_ML.md \
  GIT_ENTREGA_FINAL.md \
  data_final/ \
  datasets/final_ml/train_ghost_features.csv \
  datasets/final_ml/test_ghost_features.csv \
  datasets/final_ml/test_predictions.csv \
  datasets/final_ml/tsne_hmm_gmm_embedding.csv \
  models/final_ml/ghost_tsne_hmm_gmm.bin \
  reports/final_ml/
```

Los `part_2026_*.csv` fueron archivos temporales usados para validar por mes y **no son necesarios para el commit final**.

## Commit sugerido

```bash
git commit -m "feat(ml): complete ghost trace prediction pipeline with t-SNE HMM GMM"
```

## Push

```bash
git push -u origin feature/final-ml-ghost-prediction
```

Luego abre el Pull Request hacia la rama que el equipo esté usando como integración (`main` si esa sigue siendo la rama acordada).

## Qué debe verse en el PR

- TRAIN oficial abril–junio y TEST oficial julio 1–24.
- Targets de rastros futuros a 3/5/10/15 min.
- Features causales y distancias en PIPs.
- Normalización persistida dentro del modelo.
- Ejecución explícita `t-SNE -> HMM -> GMM`.
- Modelo `.bin` cargable.
- Predicciones de TEST y reporte de métricas.
- Auditoría `PASS`.
