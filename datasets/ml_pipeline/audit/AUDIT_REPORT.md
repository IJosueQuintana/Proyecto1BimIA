# AuditorÃ­a profunda del dataset ML

La auditorÃ­a utiliza **TRAIN + VALIDATION**. El conjunto **TEST permanece reservado y no fue leÃ­do**.

## Resumen

- Filas auditadas: **288**
- Variables numÃ©ricas: **62**
- Variables categÃ³ricas: **18**
- Grupos duplicados: **2**
- Filas/alertas sospechosas: **0**
- Variables constantes: **5**
- Variables casi constantes: **8**
- Pares con |r| >= 0.9: **57**

## RelaciÃ³n observaciones/dimensionalidad

Se auditan 288 filas frente a 62 variables numÃ©ricas. Una relaciÃ³n baja implica estimaciones de medias, varianzas, GMM y emisiones HMM potencialmente inestables.

## Variables constantes

- `timeframe`
- `confirmation_delay`
- `symbol`
- `structure_mode`
- `liquidity_state`

## Variables casi constantes

- `bos_count_previous_20`
- `choch_count_previous_20`
- `near_equal_level`
- `inside_fvg`
- `fvg_mitigated`
- `inside_order_block`
- `ob_invalidated`
- `active_ob_count_50`

## Correlaciones altas

- `pivot_id` â `pivot_index`: r=0.9959
- `pivot_id` â `confirmation_index`: r=0.9959
- `pivot_id` â `swept_index`: r=0.9775
- `pivot_id` â `resolved_index`: r=0.9775
- `pivot_index` â `confirmation_index`: r=1.0000
- `pivot_index` â `swept_index`: r=0.9815
- `pivot_index` â `resolved_index`: r=0.9815
- `confirmation_index` â `swept_index`: r=0.9815
- `confirmation_index` â `resolved_index`: r=0.9815
- `pivot_open` â `pivot_high`: r=1.0000
- `pivot_open` â `pivot_low`: r=1.0000
- `pivot_open` â `pivot_close`: r=1.0000
- `pivot_open` â `pivot_price`: r=0.9999
- `pivot_open` â `confirm_open`: r=1.0000
- `pivot_open` â `confirm_high`: r=1.0000
- `pivot_open` â `confirm_low`: r=1.0000
- `pivot_open` â `confirm_close`: r=1.0000
- `pivot_open` â `previous_pivot_price`: r=0.9900
- `pivot_high` â `pivot_low`: r=0.9999
- `pivot_high` â `pivot_close`: r=1.0000

## Variables con mayor informaciÃ³n mutua respecto al target

- `pivot_timestamp` (categorical): MI=1.043129
- `confirmation_timestamp` (categorical): MI=1.043129
- `distance_equal_level_atr` (numeric): MI=0.026018, etaÂ²=0.015662
- `bars_previous_pivot` (numeric): MI=0.025726, etaÂ²=0.017683
- `liquidity_imbalance_100` (numeric): MI=0.023578, etaÂ²=0.000600
- `distance_previous_pivot` (numeric): MI=0.022970, etaÂ²=0.033826
- `swing_size_atr` (numeric): MI=0.019262, etaÂ²=0.015933
- `active_bsl_count` (numeric): MI=0.017108, etaÂ²=0.004236
- `fvg_size_atr` (numeric): MI=0.016692, etaÂ²=0.000613
- `distance_ob_atr` (numeric): MI=0.016610, etaÂ²=0.002442
- `active_fvg_count_50` (numeric): MI=0.015911, etaÂ²=0.012211
- `pivot_body` (numeric): MI=0.015779, etaÂ²=0.014416
- `bars_since_structure_event` (numeric): MI=0.015546, etaÂ²=0.000369
- `distance_last_structure_event_atr` (numeric): MI=0.014936, etaÂ²=0.001324
- `price_to_confirm_close` (numeric): MI=0.013680, etaÂ²=0.000100

## InterpretaciÃ³n requerida

1. Verificar manualmente en el grÃ¡fico las filas de `suspicious_rows.csv` y una muestra de cada etiqueta.
2. Revisar si las variables con mayor seÃ±al se calculan completamente en `confirmation_index` o si describen un evento ya resuelto.
3. Revisar `label_transitions.csv`: transiciones casi uniformes indican que RUN/GRAB/SWEEP no forman buenos estados Markovianos.
4. Revisar `session_distribution.csv`: diferencias fuertes por sesiÃ³n indican cambio de rÃ©gimen o sesgo por fecha.
5. No eliminar variables ni cambiar etiquetas hasta revisar estos reportes.
