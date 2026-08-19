# Dataset V2 â selecciÃ³n controlada de features

Este proceso usa exclusivamente TRAIN y VALIDATION. **TEST no se lee.**

## Resumen

- TRAIN original: **259** filas
- TRAIN V2: **257** filas
- VALIDATION V2: **29** filas
- Duplicados eliminados de TRAIN: **2**
- Features numÃ©ricas: **15**
- Features categÃ³ricas: **2**

## Features numÃ©ricas

- `swing_size_atr`
- `distance_previous_pivot`
- `bars_previous_pivot`
- `distance_equal_level_atr`
- `bars_since_equal_level`
- `liquidity_imbalance_100`
- `active_bsl_count`
- `active_ssl_count`
- `active_fvg_count_50`
- `active_ob_count_50`
- `distance_fvg_atr`
- `fvg_size_atr`
- `distance_ob_atr`
- `distance_last_structure_event_atr`
- `bars_since_structure_event`

## Features categÃ³ricas

- `previous_pivot_type`
- `last_structure_event`

## Metadatos conservados solo para trazabilidad

- `source_file`
- `symbol`
- `timeframe`
- `pivot_id`
- `pivot_index`
- `confirmation_index`
- `pivot_timestamp`
- `confirmation_timestamp`
- `swept_index`
- `resolved_index`
- `target`

## Variables excluidas deliberadamente

- `confirmation_delay`
- `structure_mode`
- `liquidity_state`
- `pivot_open`
- `pivot_high`
- `pivot_low`
- `pivot_close`
- `pivot_price`
- `confirm_open`
- `confirm_high`
- `confirm_low`
- `confirm_close`
- `previous_pivot_price`
- `near_equal_level`
- `inside_fvg`
- `fvg_mitigated`
- `inside_order_block`
- `ob_invalidated`
- `bos_count_previous_20`
- `choch_count_previous_20`

## Candidatas no presentes

- `atr`
- `pivot_body_atr`
- `pivot_range_atr`
- `upper_wick_atr`
- `lower_wick_atr`
- `distance_previous_pivot_atr`
- `liquidity_imbalance_20`
- `liquidity_imbalance_50`
- `confirm_displacement_atr`
- `price_change_from_previous_atr`
- `rejection_ratio`
- `penetration_atr`
- `volume_zscore`
- `volatility_20`
- `return_1`
- `return_5`
- `slope_20`
- `pivot_type`
- `pivot_label`
- `previous_pivot_label`
- `nearest_liquidity_type`
- `liquidity_side`
- `trend_state`

## Control estadÃ­stico bÃ¡sico

| Feature | Tipo | No vacÃ­os | VacÃ­os | Ãnicos | Media | Desv. estÃ¡ndar | Min | Max |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| swing_size_atr | numeric | 257 | 0 | 257 | 20.417067 | 17.449791 | 4.305078 | 125.849889 |
| distance_previous_pivot | numeric | 257 | 0 | 239 | 261.205253 | 206.581738 | 30.000000 | 1477.750000 |
| bars_previous_pivot | numeric | 257 | 0 | 200 | 214.844358 | 170.404090 | 2.000000 | 929.000000 |
| distance_equal_level_atr | numeric | 257 | 0 | 245 | 2.213822 | 4.225665 | 0.000000 | 49.203741 |
| bars_since_equal_level | numeric | 257 | 0 | 240 | 3124.287938 | 5080.876047 | -1.000000 | 20762.000000 |
| liquidity_imbalance_100 | numeric | 257 | 0 | 61 | -0.290120 | 0.456873 | -0.913043 | 0.714286 |
| active_bsl_count | numeric | 257 | 0 | 8 | 3.147860 | 1.904334 | 1.000000 | 8.000000 |
| active_ssl_count | numeric | 257 | 0 | 22 | 7.859922 | 6.201360 | 1.000000 | 22.000000 |
| active_fvg_count_50 | numeric | 257 | 0 | 11 | 2.377432 | 1.790152 | 0.000000 | 10.000000 |
| active_ob_count_50 | numeric | 257 | 0 | 2 | 0.178988 | 0.384091 | 0.000000 | 1.000000 |
| distance_fvg_atr | numeric | 257 | 0 | 66 | 0.375982 | 0.838332 | 0.000000 | 4.452901 |
| fvg_size_atr | numeric | 257 | 0 | 257 | 1.906771 | 6.108745 | 0.015132 | 50.778995 |
| distance_ob_atr | numeric | 257 | 0 | 220 | 8.673073 | 17.903744 | 0.000000 | 150.844220 |
| distance_last_structure_event_atr | numeric | 257 | 0 | 257 | 14.905143 | 21.214549 | 0.018914 | 196.340784 |
| bars_since_structure_event | numeric | 257 | 0 | 212 | 328.840467 | 302.158113 | 1.000000 | 1346.000000 |
| previous_pivot_type | categorical | 257 | 0 | 2 |  |  |  |  |
| last_structure_event | categorical | 257 | 0 | 4 |  |  |  |  |

## InterpretaciÃ³n

El Dataset V2 reduce dimensionalidad y evita que precios absolutos, Ã­ndices, timestamps o variables constantes dominen las distancias y las distribuciones gaussianas. No cambia RUN/GRAB/SWEEP.
