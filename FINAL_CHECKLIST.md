# Checklist final — Machine Learning

## Verificación obligatoria

1. Ejecutar `perl verify_final_ml.pl`. Debe terminar con `FINAL ML VERIFICATION: PASS`.
2. Ejecutar `perl final_ml_demo.pl --n 12`. La tabla muestra `predicho/real` para 3, 5, 10 y 15 minutos usando el modelo cargado desde disco.
3. Ejecutar `perl final_ml_evidence.pl`. Regenera el embedding y la evidencia visual sin volver a entrenar.
4. Revisar `reports/final_ml/FINAL_ML_REPORT.md` y `reports/final_ml/tsne_hmm_gmm.svg`.
5. Para reconstruir datasets y volver a entrenar desde los CSV oficiales: `perl final_ml_pipeline.pl --rebuild --fast`.

## Evidencia que debe mostrarse en la exposición

- Datos: TRAIN abril-junio; TEST 1-24 de julio.
- Orden del pipeline: **t-SNE -> HMM -> GMM**.
- Separación TRAIN/TEST y normalizador ajustado solo en TRAIN.
- Modelo binario guardado y luego cargado para la demo.
- Predicciones de cantidad de rastros a 3/5/10/15 minutos versus valor real.
- Métricas MAE/RMSE y baseline de media de TRAIN.
- `tsne_hmm_gmm.svg` como evidencia visual; `tsne_hmm_gmm_embedding.csv` contiene estado HMM y cluster GMM por evento.

## Limitación conocida y documentada

El enunciado hace referencia a `Ghosts_in_swings.txt`, pero ese código fuente no venía en el ZIP ni entre los archivos adjuntos. La entrega utiliza una definición operacional causal basada en la confirmación de swing externo del motor existente y cuenta extensiones futuras del rango. Si se obtiene el indicador literal, basta sustituir la función de detección/etiquetado conservando el pipeline ML.
