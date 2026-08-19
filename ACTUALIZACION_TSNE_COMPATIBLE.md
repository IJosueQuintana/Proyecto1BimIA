# Actualización t-SNE compatible

## Archivos nuevos

- Market/ML/TSNE/DistanceEngine.pm
- Market/ML/TSNE/Perplexity.pm
- Market/ML/TSNE/ProbabilityMatrix.pm
- Market/ML/TSNE/Optimizer.pm
- Market/ML/TSNE/TSNE.pm

## Archivos reemplazados

- Market/ML/TSNE.pm
- Market/ML/TSNEPipeline.pm
- tsne_pipeline.pl
- ML_EVALUATION_README.md

## Verificación realizada

- Todos los módulos compilan con `perl -I. -c`.
- Flujo real probado con 288 muestras, perplexity 30 y 25 iteraciones.
- Se exportó correctamente `datasets/ml_pipeline/tsne_development_projection.csv`.
- No se utilizó el conjunto TEST FINAL.

## Ejecución

```bash
perl tsne_pipeline.pl
```
