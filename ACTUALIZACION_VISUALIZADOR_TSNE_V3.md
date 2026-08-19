# Visualizador t-SNE interactivo V3

## Cambios

- Tamaño predeterminado de puntos: 6.
- Opacidad predeterminada: 0.60.
- Filtro temporal por `confirmation_timestamp` (o `pivot_timestamp` como respaldo).
- Capa opcional de contornos de densidad por grupo visible.
- Selección persistente de un punto mediante clic.
- Resaltado opcional de los `k` vecinos más cercanos en el espacio t-SNE.
- `k` configurable entre 3 y 30.
- Botón **Ajustar vista a datos**.
- El panel de detalle permanece abierto para el punto seleccionado.

## Ejecución

```bash
perl plot_tsne.pl
```

No es necesario volver a ejecutar t-SNE si ya existe:

```text
datasets/ml_pipeline/tsne_development_projection.csv
```

Para regenerar las coordenadas:

```bash
perl tsne_pipeline.pl 30 750 42
perl plot_tsne.pl
```

## Nota metodológica

Los vecinos se calculan en las coordenadas bidimensionales de t-SNE y sirven únicamente para exploración visual. No sustituyen las distancias sobre las variables originales escaladas que deberán usar GMM y HMM.
