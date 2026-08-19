# Validación objetiva del embedding t-SNE

Ejecutar después de `perl ml_pipeline.pl`:

```bash
perl evaluate_embedding.pl 30 750 42 7 123
```

El script no utiliza el conjunto TEST final y no modifica la proyección principal.
Evalúa Trustworthiness, Continuity, conservación de vecindarios y similitud Procrustes.
