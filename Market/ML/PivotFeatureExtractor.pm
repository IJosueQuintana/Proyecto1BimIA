package Market::ML::PivotFeatureExtractor;

use strict;
use warnings;

use List::Util qw(min max sum);

sub new {
    my ($class, %args) = @_;

    my $self = {
        volume_lookback => $args{volume_lookback} // 20,
        default_symbol  => $args{symbol}          // 'UNKNOWN',
        default_tf      => $args{timeframe}       // 1,
    };

    return bless $self, $class;
}

# ================================================================
# EXTRACCIÓN PRINCIPAL
#
# Una fila representa un pivote confirmado.
#
# Argumentos:
#
# candles   => arreglo de velas
# pivots    => arreglo de pivotes o estructura SMC etiquetada
# atr       => arreglo de valores ATR
# liquidity => niveles de liquidez con Run/Grab/Sweep
# symbol    => nombre del activo
# timeframe => timeframe actual
#
# Retorna:
#
# [
#     { columna => valor, ... },
#     { columna => valor, ... },
# ]
# ================================================================
sub extract {
    my ($self, %args) = @_;

    my $candles   = $args{candles}   // [];
    my $pivots    = $args{pivots}    // [];
    my $atr       = $args{atr}       // [];
    my $liquidity = $args{liquidity} // [];

    my $structure_events =
    $args{structure_events}
    // [];

    my $equal_levels =
        $args{equal_levels}
        // [];

    my $fvg_levels =
        $args{fvg_levels}
        // [];

    my $order_blocks =
        $args{order_blocks}
        // [];

    my $symbol =
        $args{symbol}
        // $self->{default_symbol};

    my $timeframe =
        $args{timeframe}
        // $self->{default_tf};

    die "candles debe ser una referencia ARRAY\n"
        if ref($candles) ne 'ARRAY';

    die "pivots debe ser una referencia ARRAY\n"
        if ref($pivots) ne 'ARRAY';

    die "atr debe ser una referencia ARRAY\n"
        if ref($atr) ne 'ARRAY';

    die "liquidity debe ser una referencia ARRAY\n"
        if ref($liquidity) ne 'ARRAY';

    die "structure_events debe ser una referencia ARRAY\n"
        if ref($structure_events) ne 'ARRAY';

    die "equal_levels debe ser una referencia ARRAY\n"
        if ref($equal_levels) ne 'ARRAY';

    die "fvg_levels debe ser una referencia ARRAY\n"
        if ref($fvg_levels) ne 'ARRAY';

    die "order_blocks debe ser una referencia ARRAY\n"
        if ref($order_blocks) ne 'ARRAY';

    # ------------------------------------------------------------
# EVENTOS ESTRUCTURALES ORDENADOS
# ------------------------------------------------------------
my @ordered_structure_events =
    sort {
        ($a->{index} // -1)
        <=>
        ($b->{index} // -1)
    }
    grep {
        ref($_) eq 'HASH'
        &&
        defined $_->{index}
    } @$structure_events;

# ------------------------------------------------------------
# NIVELES EQH / EQL ORDENADOS
#
# index2 es el momento en el cual queda formado el nivel igual.
# ------------------------------------------------------------
my @ordered_equal_levels =
    sort {
        ($a->{index2} // -1)
        <=>
        ($b->{index2} // -1)
    }
    grep {
        ref($_) eq 'HASH'
        &&
        defined $_->{index2}
    } @$equal_levels;

# ------------------------------------------------------------
# FAIR VALUE GAPS ORDENADOS
#
# index es la vela en la cual el FVG queda confirmado.
# ------------------------------------------------------------
my @ordered_fvg_levels =
    sort {
        ($a->{index} // -1)
        <=>
        ($b->{index} // -1)
    }
    grep {
        ref($_) eq 'HASH'
        &&
        defined $_->{index}
        &&
        defined $_->{top}
        &&
        defined $_->{bottom}
    } @$fvg_levels;


# ------------------------------------------------------------
# ORDER BLOCKS EXTERNOS ORDENADOS
#
# break_index es el momento causal en el que el OB queda
# confirmado por el BOS o CHoCH. index/left_index representan
# la vela histórica que originó la zona y no deben utilizarse
# como instante de creación para ML.
# ------------------------------------------------------------
my @ordered_order_blocks =
    sort {
        ($a->{break_index} // -1)
        <=>
        ($b->{break_index} // -1)
    }
    grep {
        ref($_) eq 'HASH'
        &&
        ($_->{tier} // $_->{mode} // '') eq 'external'
        &&
        defined $_->{break_index}
        &&
        defined $_->{top}
        &&
        defined $_->{bottom}
    } @$order_blocks;


# ------------------------------------------------------------
# NIVELES DE LIQUIDEZ CON INSTANTE CAUSAL DE CREACIÓN
#
# created_index/index representan el extremo histórico. Para ML,
# el nivel solo puede utilizarse cuando el pivote correspondiente
# ya quedó confirmado. Se deriva ese instante desde @ordered.
# ------------------------------------------------------------
my %pivot_confirmation_by_liquidity_key;

for my $pivot (@$pivots) {
    next if ref($pivot) ne 'HASH';

    my $occurrence_index =
        _pivot_occurrence_index($pivot);

    my $confirmed_index =
        _pivot_confirmation_index($pivot);

    next if !defined $occurrence_index;
    next if !defined $confirmed_index;
    next if !defined $pivot->{price};

    my $liquidity_type =
        uc($pivot->{type} // '') eq 'HIGH'
        ? 'BSL'
        : uc($pivot->{type} // '') eq 'LOW'
            ? 'SSL'
            : '';

    next if !$liquidity_type;

    my $key = join('|',
        $occurrence_index,
        $liquidity_type,
        sprintf('%.10f', _num($pivot->{price})),
    );

    $pivot_confirmation_by_liquidity_key{$key} =
        $confirmed_index;
}

my @causal_liquidity_levels =
    map {
        my $level = $_;

        my $occurrence_index =
            defined $level->{pivot_index}
            ? $level->{pivot_index}
            : defined $level->{index}
                ? $level->{index}
                : $level->{created_index};

        my $key = join('|',
            defined $occurrence_index ? $occurrence_index : -1,
            uc($level->{type} // ''),
            sprintf('%.10f', _num($level->{price})),
        );

        my $causal_creation_index =
            exists $pivot_confirmation_by_liquidity_key{$key}
            ? $pivot_confirmation_by_liquidity_key{$key}
            : $level->{confirmed_index};

        $causal_creation_index =
            $level->{created_index} // $level->{index}
            if !defined $causal_creation_index;

        +{
            %$level,
            _ml_created_index => $causal_creation_index,
        };
    }
    grep {
        ref($_) eq 'HASH'
        &&
        (($_->{type} // '') eq 'BSL' || ($_->{type} // '') eq 'SSL')
        &&
        defined $_->{price}
    } @$liquidity;

my @ordered_liquidity_levels =
    sort {
        ($a->{_ml_created_index} // -1)
        <=>
        ($b->{_ml_created_index} // -1)
    } @causal_liquidity_levels;

    # Ordenamos según la vela donde realmente ocurrió el extremo.
    my @ordered = sort {
        _pivot_occurrence_index($a)
            <=>
        _pivot_occurrence_index($b)

            ||

        _pivot_confirmation_index($a)
            <=>
        _pivot_confirmation_index($b)

    } grep {
        $_
            &&
        defined _pivot_occurrence_index($_)
            &&
        defined $_->{price}
            &&
        defined $_->{type}
    } @$pivots;

    # Índice auxiliar para asociar un pivote con su nivel de liquidez.
    my %liquidity_by_key =
        _index_liquidity($liquidity);

    my @rows;

    my $previous;
    my $pivot_id = 0;

    for my $pivot (@ordered) {

        my $pivot_index =
            _pivot_occurrence_index($pivot);

        my $confirmation_index =
            _pivot_confirmation_index($pivot);

        next if !defined $pivot_index;
        next if !defined $confirmation_index;

        next if $pivot_index < 0;
        next if $pivot_index > $#$candles;

        next if $confirmation_index < 0;
        next if $confirmation_index > $#$candles;

        my $pivot_bar =
            $candles->[$pivot_index];

        my $confirm_bar =
            $candles->[$confirmation_index];

        next if !$pivot_bar;
        next if !$confirm_bar;

        # ------------------------------------------------------------
        # DATOS DE LA VELA DEL PIVOTE
        # ------------------------------------------------------------
        my $open =
            _num($pivot_bar->{open});

        my $high =
            _num($pivot_bar->{high});

        my $low =
            _num($pivot_bar->{low});

        my $close =
            _num($pivot_bar->{close});

        my $volume =
            _num($pivot_bar->{volume});

        my $price =
            _num($pivot->{price});

        my $range =
            $high - $low;

        my $body =
            abs($close - $open);

        my $upper_wick =
            $high - max($open, $close);

        my $lower_wick =
            min($open, $close) - $low;

        # Posición del cierre dentro de la vela:
        #
        # 0 = cerca del mínimo
        # 1 = cerca del máximo
        my $close_position =
            $range > 0
            ? ($close - $low) / $range
            : 0;

        my $candle_direction =
            $close > $open
            ? 1
            : $close < $open
                ? -1
                : 0;

        # ------------------------------------------------------------
        # ATR
        #
        # Se toma en confirmation_index porque ese es el instante
        # desde el cual el pivote ya puede utilizarse.
        # ------------------------------------------------------------
        my $atr_value =
            defined $atr->[$confirmation_index]
            ? _num($atr->[$confirmation_index])
            : 0;

        # ------------------------------------------------------------
        # VOLUMEN
        #
        # El promedio utiliza únicamente velas anteriores a la vela
        # de confirmación, evitando información futura.
        # ------------------------------------------------------------
        my ($volume_mean, $volume_std) =
            $self->_rolling_volume_stats(
                $candles,
                $confirmation_index,
                $self->{volume_lookback},
            );

        my $volume_ratio =
            $volume_mean > 0
            ? $volume / $volume_mean
            : 0;

        my $volume_zscore =
            $volume_std > 0
            ? ($volume - $volume_mean) / $volume_std
            : 0;

        # ------------------------------------------------------------
        # RELACIÓN CON EL PIVOTE ANTERIOR
        # ------------------------------------------------------------
        my $distance_previous = 0;
        my $bars_previous     = 0;
        my $swing_size_atr    = 0;

        my $previous_type  = 'NONE';
        my $previous_price = 0;

        if ($previous) {

            $previous_type =
                $previous->{type}
                // 'NONE';

            $previous_price =
                _num($previous->{price});

            $distance_previous =
                abs(
                    $price
                    -
                    $previous_price
                );

            $bars_previous =
                $pivot_index
                -
                _pivot_occurrence_index($previous);

            $swing_size_atr =
                $atr_value > 0
                ? $distance_previous / $atr_value
                : 0;
        }

        # ------------------------------------------------------------
        # ASOCIACIÓN CON RUN / GRAB / SWEEP
        # ------------------------------------------------------------
        my $liq =
            _find_liquidity_for_pivot(
                \%liquidity_by_key,
                $pivot_index,
                $pivot->{type},
                $price,
            );
# ------------------------------------------------------------
# CONTEXTO BOS / CHoCH
#
# Solo utiliza eventos conocidos hasta confirmation_index.
# ------------------------------------------------------------
my $structure_context =
    _structure_event_context(
        events =>
            \@ordered_structure_events,

        confirmation_index =>
            $confirmation_index,

        pivot_price =>
            $price,

        atr =>
            $atr_value,

        lookback =>
            20,
    );

# ------------------------------------------------------------
# CONTEXTO EQH / EQL
#
# Solo utiliza niveles formados hasta confirmation_index.
# ------------------------------------------------------------
my $equal_level_context =
    _equal_level_context(
        equal_levels =>
            \@ordered_equal_levels,

        confirmation_index =>
            $confirmation_index,

        pivot_price =>
            $price,

        atr =>
            $atr_value,
    );

# ------------------------------------------------------------
# CONTEXTO FVG
#
# El estado de mitigación se evalúa como era en confirmation_index.
# No se utiliza información posterior a la confirmación del pivote.
# ------------------------------------------------------------
my $fvg_context =
    _fvg_context(
        fvg_levels =>
            \@ordered_fvg_levels,

        confirmation_index =>
            $confirmation_index,

        pivot_price =>
            $price,

        atr =>
            $atr_value,

        active_lookback =>
            50,
    );


# ------------------------------------------------------------
# CONTEXTO ORDER BLOCK EXTERNO
#
# El OB solo existe desde break_index. Su invalidación se evalúa
# como era en confirmation_index para impedir fuga de información.
# ------------------------------------------------------------
my $order_block_context =
    _order_block_context(
        order_blocks =>
            \@ordered_order_blocks,

        confirmation_index =>
            $confirmation_index,

        pivot_price =>
            $price,

        atr =>
            $atr_value,

        active_lookback =>
            50,
    );


# ------------------------------------------------------------
# DENSIDAD DE LIQUIDEZ
#
# Conteos, distancias e imbalance se reconstruyen exactamente
# como eran en confirmation_index.
# ------------------------------------------------------------
my $liquidity_density_context =
    _liquidity_density_context(
        liquidity_levels =>
            \@ordered_liquidity_levels,

        equal_levels =>
            \@ordered_equal_levels,

        confirmation_index =>
            $confirmation_index,

        pivot_price =>
            $price,

        atr =>
            $atr_value,

        lookback =>
            100,
    );
        $pivot_id++;

        push @rows, {

            # ========================================================
            # IDENTIFICACIÓN
            # ========================================================
            pivot_id =>
                $pivot_id,

            symbol =>
                $symbol,

            timeframe =>
                $timeframe,

            pivot_index =>
                $pivot_index,

            confirmation_index =>
                $confirmation_index,

            confirmation_delay =>
                $confirmation_index - $pivot_index,

            pivot_timestamp =>
                $pivot_bar->{time}
                // $pivot->{timestamp}
                // '',

            confirmation_timestamp =>
                $confirm_bar->{time}
                // '',

            # ========================================================
            # TIPO Y ESTRUCTURA
            # ========================================================
            pivot_side =>
                uc(
                    $pivot->{type}
                    // 'UNKNOWN'
                ),

            structure_type =>
                _structure_label($pivot),

            structure_mode =>
                $pivot->{structure_mode}
                // $pivot->{mode}
                // $pivot->{tier}
                // 'UNKNOWN',

            source =>
                $pivot->{source}
                // 'UNKNOWN',

            # ========================================================
            # VELA DEL PIVOTE
            # ========================================================
            pivot_open =>
                $open,

            pivot_high =>
                $high,

            pivot_low =>
                $low,

            pivot_close =>
                $close,

            pivot_price =>
                $price,

            pivot_volume =>
                $volume,

            pivot_range =>
                $range,

            pivot_body =>
                $body,

            upper_wick =>
                $upper_wick,

            lower_wick =>
                $lower_wick,

            candle_direction =>
                $candle_direction,

            close_position =>
                $close_position,

            # ========================================================
            # VELA DE CONFIRMACIÓN
            # ========================================================
            confirm_open =>
                _num($confirm_bar->{open}),

            confirm_high =>
                _num($confirm_bar->{high}),

            confirm_low =>
                _num($confirm_bar->{low}),

            confirm_close =>
                _num($confirm_bar->{close}),

            confirm_volume =>
                _num($confirm_bar->{volume}),

            # ========================================================
            # ATR Y NORMALIZACIÓN
            # ========================================================
            atr_14 =>
                $atr_value,

            range_atr_ratio =>
                $atr_value > 0
                ? $range / $atr_value
                : 0,

            body_atr_ratio =>
                $atr_value > 0
                ? $body / $atr_value
                : 0,

            price_to_confirm_close =>
                $atr_value > 0
                ? (
                    $price
                    -
                    _num($confirm_bar->{close})
                ) / $atr_value
                : 0,

            # ========================================================
            # VOLUMEN RELATIVO
            # ========================================================
            volume_mean_20 =>
                $volume_mean,

            volume_std_20 =>
                $volume_std,

            volume_ratio_20 =>
                $volume_ratio,

            volume_zscore_20 =>
                $volume_zscore,

            # ========================================================
            # GEOMETRÍA DEL SWING
            # ========================================================
            previous_pivot_type =>
                $previous_type,

            previous_pivot_price =>
                $previous_price,

            distance_previous_pivot =>
                $distance_previous,

            bars_previous_pivot =>
                $bars_previous,

            swing_size_atr =>
                $swing_size_atr,

            # ========================================================
            # LIQUIDEZ Y VARIABLE OBJETIVO
            # ========================================================
            liquidity_type =>
                $liq
                ? ($liq->{type} // 'NONE')
                : 'NONE',

            liquidity_state =>
                $liq
                ? ($liq->{state} // 'NONE')
                : 'NONE',

            swept_index =>
                $liq
                    &&
                defined $liq->{swept_index}
                ? $liq->{swept_index}
                : -1,

            resolved_index =>
                $liq
                    &&
                defined $liq->{resolved_index}
                ? $liq->{resolved_index}
                : -1,

                            # ========================================================
            # CONTEXTO BOS / CHoCH
            # ========================================================
            last_structure_event =>
                $structure_context->{last_structure_event},

            last_structure_event_direction =>
                $structure_context->{last_structure_event_direction},

            bars_since_structure_event =>
                $structure_context->{bars_since_structure_event},

            distance_last_structure_event_atr =>
                $structure_context->{distance_last_structure_event_atr},

            bos_count_previous_20 =>
                $structure_context->{bos_count_previous_20},

            choch_count_previous_20 =>
                $structure_context->{choch_count_previous_20},

            # ========================================================
            # CONTEXTO EQH / EQL
            # ========================================================
            near_equal_level =>
                $equal_level_context->{near_equal_level},

            equal_level_type =>
                $equal_level_context->{equal_level_type},

            distance_equal_level_atr =>
                $equal_level_context->{distance_equal_level_atr},

            bars_since_equal_level =>
                $equal_level_context->{bars_since_equal_level},

            # ========================================================
            # CONTEXTO FVG
            # ========================================================
            inside_fvg =>
                $fvg_context->{inside_fvg},

            nearest_fvg_type =>
                $fvg_context->{nearest_fvg_type},

            distance_fvg_atr =>
                $fvg_context->{distance_fvg_atr},

            fvg_size_atr =>
                $fvg_context->{fvg_size_atr},

            bars_since_fvg =>
                $fvg_context->{bars_since_fvg},

            fvg_mitigated =>
                $fvg_context->{fvg_mitigated},

            active_fvg_count_50 =>
                $fvg_context->{active_fvg_count_50},

            # ========================================================
            # CONTEXTO ORDER BLOCK EXTERNO
            # ========================================================
            inside_order_block =>
                $order_block_context->{inside_order_block},

            nearest_ob_type =>
                $order_block_context->{nearest_ob_type},

            distance_ob_atr =>
                $order_block_context->{distance_ob_atr},

            ob_size_atr =>
                $order_block_context->{ob_size_atr},

            bars_since_ob =>
                $order_block_context->{bars_since_ob},

            ob_invalidated =>
                $order_block_context->{ob_invalidated},

            active_ob_count_50 =>
                $order_block_context->{active_ob_count_50},

            # ========================================================
            # DENSIDAD DE LIQUIDEZ
            # ========================================================
            bsl_count_previous_100 =>
                $liquidity_density_context->{bsl_count_previous_100},

            ssl_count_previous_100 =>
                $liquidity_density_context->{ssl_count_previous_100},

            active_bsl_count =>
                $liquidity_density_context->{active_bsl_count},

            active_ssl_count =>
                $liquidity_density_context->{active_ssl_count},

            distance_nearest_bsl_atr =>
                $liquidity_density_context->{distance_nearest_bsl_atr},

            distance_nearest_ssl_atr =>
                $liquidity_density_context->{distance_nearest_ssl_atr},

            equal_levels_previous_100 =>
                $liquidity_density_context->{equal_levels_previous_100},

            liquidity_imbalance_100 =>
                $liquidity_density_context->{liquidity_imbalance_100},

            target =>
                $liq
                    &&
                defined $liq->{classification}
                ? uc($liq->{classification})
                : 'NONE',
        };

        $previous = $pivot;
    }

    return \@rows;
}

# ================================================================
# NOMBRES Y ORDEN DE LAS COLUMNAS
#
# Este orden se utilizará posteriormente para exportar el CSV.
# ================================================================
sub feature_names {
    return [
        qw(
            pivot_id
            symbol
            timeframe
            pivot_index
            confirmation_index
            confirmation_delay
            pivot_timestamp
            confirmation_timestamp
            pivot_side
            structure_type
            structure_mode
            source
            pivot_open
            pivot_high
            pivot_low
            pivot_close
            pivot_price
            pivot_volume
            pivot_range
            pivot_body
            upper_wick
            lower_wick
            candle_direction
            close_position
            confirm_open
            confirm_high
            confirm_low
            confirm_close
            confirm_volume
            atr_14
            range_atr_ratio
            body_atr_ratio
            price_to_confirm_close
            volume_mean_20
            volume_std_20
            volume_ratio_20
            volume_zscore_20
            previous_pivot_type
            previous_pivot_price
            distance_previous_pivot
            bars_previous_pivot
            swing_size_atr
            liquidity_type
            liquidity_state
            swept_index
            resolved_index
            last_structure_event
            last_structure_event_direction
            bars_since_structure_event
            distance_last_structure_event_atr
            bos_count_previous_20
            choch_count_previous_20
            near_equal_level
            equal_level_type
            distance_equal_level_atr
            bars_since_equal_level
            inside_fvg
            nearest_fvg_type
            distance_fvg_atr
            fvg_size_atr
            bars_since_fvg
            fvg_mitigated
            active_fvg_count_50
            inside_order_block
            nearest_ob_type
            distance_ob_atr
            ob_size_atr
            bars_since_ob
            ob_invalidated
            active_ob_count_50
            bsl_count_previous_100
            ssl_count_previous_100
            active_bsl_count
            active_ssl_count
            distance_nearest_bsl_atr
            distance_nearest_ssl_atr
            equal_levels_previous_100
            liquidity_imbalance_100
            target
        )
    ];
}

# ================================================================
# MEDIA Y DESVIACIÓN ESTÁNDAR DEL VOLUMEN
#
# Solo utiliza barras anteriores al índice recibido.
# ================================================================
sub _rolling_volume_stats {
    my ($self, $candles, $index, $lookback) = @_;

    my $from =
        $index - $lookback;

    $from = 0
        if $from < 0;

    my $to =
        $index - 1;

    return (0, 0)
        if $to < $from;

    my @values;

    for my $i ($from .. $to) {

        next if !$candles->[$i];

        push @values,
            _num(
                $candles->[$i]{volume}
            );
    }

    return (0, 0)
        if !@values;

    my $mean =
        sum(@values)
        /
        scalar(@values);

    my $variance =
        sum(
            map {
                ($_ - $mean) ** 2
            } @values
        )
        /
        scalar(@values);

    my $std =
        sqrt($variance);

    return ($mean, $std);
}

# ================================================================
# ÍNDICE REAL DEL EXTREMO
#
# Pivotes internos:
#   display_index = vela real del extremo
#   index         = vela de confirmación
#
# Pivotes externos actuales:
#   index = vela del extremo
# ================================================================
sub _pivot_occurrence_index {
    my ($pivot) = @_;

    return undef
        if !$pivot;

    return $pivot->{display_index}
        if defined $pivot->{display_index};

    return $pivot->{pivot_index}
        if defined $pivot->{pivot_index};

    return $pivot->{index};
}

# ================================================================
# ÍNDICE DE CONFIRMACIÓN
# ================================================================
sub _pivot_confirmation_index {
    my ($pivot) = @_;

    return undef
        if !$pivot;

    return $pivot->{confirmed_index}
        if defined $pivot->{confirmed_index};

    return $pivot->{confirmation_index}
        if defined $pivot->{confirmation_index};

    return $pivot->{index};
}

# ================================================================
# ETIQUETA HH, HL, LH O LL
# ================================================================
sub _structure_label {
    my ($pivot) = @_;

    my $label =
        $pivot->{raw_label}
        // $pivot->{label}
        // 'UNKNOWN';

    # Las etiquetas internas del proyecto pueden aparecer como:
    #
    # iHH, iHL, iLH, iLL
    #
    # Para el dataset dejamos:
    #
    # HH, HL, LH, LL
    $label =~ s/^i//;

    return $label;
}

# ================================================================
# ORGANIZA LOS NIVELES DE LIQUIDEZ POR ÍNDICE
# ================================================================
sub _index_liquidity {
    my ($liquidity) = @_;

    my %index;

    return %index
        if ref($liquidity) ne 'ARRAY';

    for my $level (@$liquidity) {

        next if !$level;

        my $i =
            defined $level->{pivot_index}
            ? $level->{pivot_index}
            : defined $level->{index}
                ? $level->{index}
                : $level->{created_index};

        next if !defined $i;

        push @{$index{$i}}, $level;
    }

    return %index;
}

# ================================================================
# BUSCA EL NIVEL DE LIQUIDEZ CORRESPONDIENTE AL PIVOTE
#
# HIGH -> BSL
# LOW  -> SSL
# ================================================================
sub _find_liquidity_for_pivot {
    my (
        $index,
        $pivot_index,
        $pivot_type,
        $pivot_price,
    ) = @_;

    my $levels =
        $index->{$pivot_index}
        // [];

    my $wanted =
        uc($pivot_type // '') eq 'HIGH'
        ? 'BSL'
        : 'SSL';

    my @matches = grep {

        ($_->{type} // '') eq $wanted

            &&

        abs(
            _num($_->{price})
            -
            $pivot_price
        ) < 1e-9

    } @$levels;

    return $matches[0]
        if @matches;

    return undef;
}

# ================================================================
# CONTEXTO DEL ÚLTIMO BOS / CHoCH
#
# Solo considera eventos cuyo índice sea menor o igual al índice
# de confirmación del pivote.
# ================================================================
sub _structure_event_context {
    my (%args) = @_;

    my $events =
        $args{events}
        // [];

    my $confirmation_index =
        $args{confirmation_index};

    my $pivot_price =
        _num(
            $args{pivot_price}
        );

    my $atr =
        _num(
            $args{atr}
        );

    my $lookback =
        $args{lookback}
        // 20;

    my %result = (
        last_structure_event =>
            'NONE',

        last_structure_event_direction =>
            'NONE',

        bars_since_structure_event =>
            -1,

        distance_last_structure_event_atr =>
            0,

        bos_count_previous_20 =>
            0,

        choch_count_previous_20 =>
            0,
    );

    return \%result
        if ref($events) ne 'ARRAY';

    return \%result
        if !defined $confirmation_index;

    my $window_start =
        $confirmation_index
        -
        $lookback
        +
        1;

    $window_start = 0
        if $window_start < 0;

    my $last_event;

    for my $event (@$events) {

        next
            if ref($event) ne 'HASH';

        my $event_index =
            $event->{index};

        next
            if !defined $event_index;

        # Como están ordenados, al llegar a un evento futuro
        # podemos terminar el recorrido.
        last
            if $event_index > $confirmation_index;

        my $event_type =
            uc(
                $event->{type}
                // 'NONE'
            );

        $last_event =
            $event;

        next
            if $event_index < $window_start;

        if ($event_type =~ /^BOS_/) {
            $result{bos_count_previous_20}++;
        }
        elsif ($event_type =~ /^CHOCH_/) {
            $result{choch_count_previous_20}++;
        }
    }

    return \%result
        if !$last_event;

    my $event_type =
        uc(
            $last_event->{type}
            // 'NONE'
        );

    my $direction =
        $event_type =~ /_UP$/
        ? 'UP'
        : $event_type =~ /_DOWN$/
            ? 'DOWN'
            : 'NONE';

    my $event_index =
        $last_event->{index};

    my $event_price =
        _num(
            $last_event->{price}
        );

    my $distance =
        abs(
            $pivot_price
            -
            $event_price
        );

    $result{last_structure_event} =
        $event_type;

    $result{last_structure_event_direction} =
        $direction;

    $result{bars_since_structure_event} =
        $confirmation_index
        -
        $event_index;

    $result{distance_last_structure_event_atr} =
        $atr > 0
        ? $distance / $atr
        : 0;

    return \%result;
}

# ================================================================
# CONTEXTO DEL EQH / EQL MÁS CERCANO
#
# Solo considera niveles cuyo index2 ya haya ocurrido antes o en
# la confirmación del pivote.
# ================================================================
sub _equal_level_context {
    my (%args) = @_;

    my $equal_levels =
        $args{equal_levels}
        // [];

    my $confirmation_index =
        $args{confirmation_index};

    my $pivot_price =
        _num(
            $args{pivot_price}
        );

    my $atr =
        _num(
            $args{atr}
        );

    my %result = (
        near_equal_level =>
            0,

        equal_level_type =>
            'NONE',

        distance_equal_level_atr =>
            0,

        bars_since_equal_level =>
            -1,
    );

    return \%result
        if ref($equal_levels) ne 'ARRAY';

    return \%result
        if !defined $confirmation_index;

    my $nearest;
    my $nearest_distance;

    for my $level (@$equal_levels) {

        next
            if ref($level) ne 'HASH';

        my $level_index =
            $level->{index2};

        next
            if !defined $level_index;

        # Los niveles están ordenados por index2.
        last
            if $level_index > $confirmation_index;

        my $level_price =
            _num(
                $level->{price}
            );

        my $distance =
            abs(
                $pivot_price
                -
                $level_price
            );

        if (
            !defined $nearest_distance
            ||
            $distance < $nearest_distance
        ) {
            $nearest =
                $level;

            $nearest_distance =
                $distance;
        }
    }

    return \%result
        if !$nearest;

    my $level_type =
        uc(
            $nearest->{type}
            // 'NONE'
        );

    my $level_index =
        $nearest->{index2};

    my $distance_atr =
        $atr > 0
        ? $nearest_distance / $atr
        : 0;

    $result{equal_level_type} =
        $level_type;

    $result{distance_equal_level_atr} =
        $distance_atr;

    $result{bars_since_equal_level} =
        $confirmation_index
        -
        $level_index;

    # Se considera cercano si el nivel está dentro de un ATR.
    $result{near_equal_level} =
        $atr > 0
        &&
        $distance_atr <= 1
        ? 1
        : 0;

    return \%result;
}

# ================================================================
# CONTEXTO DEL FAIR VALUE GAP MÁS CERCANO
#
# Reglas causales:
#   - El FVG solo existe desde fvg->{index}.
#   - Un FVG se considera mitigado únicamente cuando
#     mitigated_index <= confirmation_index.
#   - Si la mitigación ocurrió después, en ese momento todavía estaba activo.
# ================================================================
sub _fvg_context {
    my (%args) = @_;

    my $fvg_levels =
        $args{fvg_levels}
        // [];

    my $order_blocks =
        $args{order_blocks}
        // [];

    my $confirmation_index =
        $args{confirmation_index};

    my $pivot_price =
        _num(
            $args{pivot_price}
        );

    my $atr =
        _num(
            $args{atr}
        );

    my $active_lookback =
        $args{active_lookback}
        // 50;

    my %result = (
        inside_fvg =>
            0,

        nearest_fvg_type =>
            'NONE',

        distance_fvg_atr =>
            0,

        fvg_size_atr =>
            0,

        bars_since_fvg =>
            -1,

        fvg_mitigated =>
            0,

        active_fvg_count_50 =>
            0,
    );

    return \%result
        if ref($fvg_levels) ne 'ARRAY';

    return \%result
        if !defined $confirmation_index;

    my $window_start =
        $confirmation_index
        -
        $active_lookback
        +
        1;

    $window_start = 0
        if $window_start < 0;

    my $nearest;
    my $nearest_distance;
    my $nearest_mitigated = 0;

    for my $fvg (@$fvg_levels) {

        next
            if ref($fvg) ne 'HASH';

        my $creation_index =
            $fvg->{index};

        next
            if !defined $creation_index;

        # Los FVG están ordenados por creación.
        last
            if $creation_index > $confirmation_index;

        next
            if !defined $fvg->{top};

        next
            if !defined $fvg->{bottom};

        my $top =
            _num(
                $fvg->{top}
            );

        my $bottom =
            _num(
                $fvg->{bottom}
            );

        # Protección ante datos invertidos.
        if ($bottom > $top) {
            my $tmp = $top;
            $top = $bottom;
            $bottom = $tmp;
        }

        my $mitigated_as_of_confirmation =
            defined $fvg->{mitigated_index}
            &&
            $fvg->{mitigated_index} <= $confirmation_index
            ? 1
            : 0;

        # Cuenta únicamente FVG creados en las 50 velas previas
        # que seguían activos en el instante de confirmación.
        if (
            $creation_index >= $window_start
            &&
            !$mitigated_as_of_confirmation
        ) {
            $result{active_fvg_count_50}++;
        }

        my $distance =
            $pivot_price < $bottom
            ? $bottom - $pivot_price
            : $pivot_price > $top
                ? $pivot_price - $top
                : 0;

        if (
            !defined $nearest_distance
            ||
            $distance < $nearest_distance
            ||
            (
                $distance == $nearest_distance
                &&
                $creation_index > ($nearest->{index} // -1)
            )
        ) {
            $nearest =
                $fvg;

            $nearest_distance =
                $distance;

            $nearest_mitigated =
                $mitigated_as_of_confirmation;
        }
    }

    return \%result
        if !$nearest;

    my $top =
        _num(
            $nearest->{top}
        );

    my $bottom =
        _num(
            $nearest->{bottom}
        );

    if ($bottom > $top) {
        my $tmp = $top;
        $top = $bottom;
        $bottom = $tmp;
    }

    my $size =
        $top - $bottom;

    my $creation_index =
        $nearest->{index};

    $result{inside_fvg} =
        $nearest_distance == 0
        ? 1
        : 0;

    $result{nearest_fvg_type} =
        uc(
            $nearest->{type}
            // 'NONE'
        );

    $result{distance_fvg_atr} =
        $atr > 0
        ? $nearest_distance / $atr
        : 0;

    $result{fvg_size_atr} =
        $atr > 0
        ? $size / $atr
        : 0;

    $result{bars_since_fvg} =
        $confirmation_index
        -
        $creation_index;

    $result{fvg_mitigated} =
        $nearest_mitigated;

    return \%result;
}


# ================================================================
# DENSIDAD DE LIQUIDEZ BSL / SSL
#
# Reglas causales:
#   - El nivel existe desde _ml_created_index, derivado de la
#     confirmación real de su pivote estructural.
#   - Se considera activo cuando resolved_index todavía no ocurrió
#     en confirmation_index.
#   - Las distancias se calculan únicamente contra niveles activos.
#   - Los conteos previous_100 incluyen niveles creados en las 100
#     velas previas, aunque después se hayan resuelto.
# ================================================================
sub _liquidity_density_context {
    my (%args) = @_;

    my $liquidity_levels =
        $args{liquidity_levels}
        // [];

    my $equal_levels =
        $args{equal_levels}
        // [];

    my $confirmation_index =
        $args{confirmation_index};

    my $pivot_price =
        _num($args{pivot_price});

    my $atr =
        _num($args{atr});

    my $lookback =
        $args{lookback}
        // 100;

    my %result = (
        bsl_count_previous_100      => 0,
        ssl_count_previous_100      => 0,
        active_bsl_count            => 0,
        active_ssl_count            => 0,
        distance_nearest_bsl_atr    => 0,
        distance_nearest_ssl_atr    => 0,
        equal_levels_previous_100   => 0,
        liquidity_imbalance_100     => 0,
    );

    return \%result
        if ref($liquidity_levels) ne 'ARRAY';

    return \%result
        if !defined $confirmation_index;

    my $window_start =
        $confirmation_index - $lookback + 1;

    $window_start = 0
        if $window_start < 0;

    my $nearest_bsl_distance;
    my $nearest_ssl_distance;

    for my $level (@$liquidity_levels) {
        next if ref($level) ne 'HASH';

        my $creation_index =
            $level->{_ml_created_index};

        next if !defined $creation_index;

        # Los niveles están ordenados por su creación causal.
        last if $creation_index > $confirmation_index;

        my $type =
            uc($level->{type} // '');

        next if $type ne 'BSL' && $type ne 'SSL';

        if ($creation_index >= $window_start) {
            if ($type eq 'BSL') {
                $result{bsl_count_previous_100}++;
            }
            else {
                $result{ssl_count_previous_100}++;
            }
        }

        my $resolved_as_of_confirmation =
            defined $level->{resolved_index}
            &&
            $level->{resolved_index} <= $confirmation_index
            ? 1
            : 0;

        next if $resolved_as_of_confirmation;

        my $distance =
            abs($pivot_price - _num($level->{price}));

        if ($type eq 'BSL') {
            $result{active_bsl_count}++;

            $nearest_bsl_distance = $distance
                if !defined $nearest_bsl_distance
                || $distance < $nearest_bsl_distance;
        }
        else {
            $result{active_ssl_count}++;

            $nearest_ssl_distance = $distance
                if !defined $nearest_ssl_distance
                || $distance < $nearest_ssl_distance;
        }
    }

    if (ref($equal_levels) eq 'ARRAY') {
        for my $level (@$equal_levels) {
            next if ref($level) ne 'HASH';

            my $formed_index =
                $level->{index2};

            next if !defined $formed_index;
            last if $formed_index > $confirmation_index;
            next if $formed_index < $window_start;

            $result{equal_levels_previous_100}++;
        }
    }

    $result{distance_nearest_bsl_atr} =
        defined $nearest_bsl_distance && $atr > 0
        ? $nearest_bsl_distance / $atr
        : 0;

    $result{distance_nearest_ssl_atr} =
        defined $nearest_ssl_distance && $atr > 0
        ? $nearest_ssl_distance / $atr
        : 0;

    my $active_total =
        $result{active_bsl_count}
        +
        $result{active_ssl_count};

    $result{liquidity_imbalance_100} =
        $active_total > 0
        ? (
            $result{active_bsl_count}
            -
            $result{active_ssl_count}
        ) / $active_total
        : 0;

    return \%result;
}

# ================================================================
# CONVERSIÓN NUMÉRICA SEGURA
# ================================================================
sub _num {
    my ($value) = @_;

    return defined $value
        ? 0 + $value
        : 0;
}


# ================================================================
# CONTEXTO DEL ORDER BLOCK EXTERNO MÁS CERCANO
#
# Reglas causales:
#   - El OB solo existe desde break_index, cuando ocurre el evento
#     BOS/CHoCH que confirma la zona.
#   - index/left_index señalan la vela histórica de origen, pero no
#     el instante desde el cual el modelo puede conocer el OB.
#   - Un OB se considera invalidado únicamente cuando
#     invalidated_index <= confirmation_index.
# ================================================================
sub _order_block_context {
    my (%args) = @_;

    my $order_blocks =
        $args{order_blocks}
        // [];

    my $confirmation_index =
        $args{confirmation_index};

    my $pivot_price =
        _num(
            $args{pivot_price}
        );

    my $atr =
        _num(
            $args{atr}
        );

    my $active_lookback =
        $args{active_lookback}
        // 50;

    my %result = (
        inside_order_block => 0,
        nearest_ob_type    => 'NONE',
        distance_ob_atr    => 0,
        ob_size_atr        => 0,
        bars_since_ob      => -1,
        ob_invalidated     => 0,
        active_ob_count_50 => 0,
    );

    return \%result
        if ref($order_blocks) ne 'ARRAY';

    return \%result
        if !defined $confirmation_index;

    my $window_start =
        $confirmation_index
        -
        $active_lookback
        +
        1;

    $window_start = 0
        if $window_start < 0;

    my $nearest;
    my $nearest_distance;
    my $nearest_invalidated = 0;

    for my $ob (@$order_blocks) {

        next
            if ref($ob) ne 'HASH';

        my $creation_index =
            $ob->{break_index};

        next
            if !defined $creation_index;

        # Los OB están ordenados por break_index.
        last
            if $creation_index > $confirmation_index;

        next
            if !defined $ob->{top};

        next
            if !defined $ob->{bottom};

        my $top =
            _num(
                $ob->{top}
            );

        my $bottom =
            _num(
                $ob->{bottom}
            );

        if ($bottom > $top) {
            my $tmp = $top;
            $top = $bottom;
            $bottom = $tmp;
        }

        my $invalidated_as_of_confirmation =
            defined $ob->{invalidated_index}
            &&
            $ob->{invalidated_index} <= $confirmation_index
            ? 1
            : 0;

        if (
            $creation_index >= $window_start
            &&
            !$invalidated_as_of_confirmation
        ) {
            $result{active_ob_count_50}++;
        }

        my $distance =
            $pivot_price < $bottom
            ? $bottom - $pivot_price
            : $pivot_price > $top
                ? $pivot_price - $top
                : 0;

        if (
            !defined $nearest_distance
            ||
            $distance < $nearest_distance
            ||
            (
                $distance == $nearest_distance
                &&
                $creation_index > ($nearest->{break_index} // -1)
            )
        ) {
            $nearest =
                $ob;

            $nearest_distance =
                $distance;

            $nearest_invalidated =
                $invalidated_as_of_confirmation;
        }
    }

    return \%result
        if !$nearest;

    my $top =
        _num(
            $nearest->{top}
        );

    my $bottom =
        _num(
            $nearest->{bottom}
        );

    if ($bottom > $top) {
        my $tmp = $top;
        $top = $bottom;
        $bottom = $tmp;
    }

    my $size =
        $top - $bottom;

    my $creation_index =
        $nearest->{break_index};

    $result{inside_order_block} =
        $nearest_distance == 0
        ? 1
        : 0;

    $result{nearest_ob_type} =
        uc(
            $nearest->{type}
            // 'NONE'
        );

    $result{distance_ob_atr} =
        $atr > 0
        ? $nearest_distance / $atr
        : 0;

    $result{ob_size_atr} =
        $atr > 0
        ? $size / $atr
        : 0;

    $result{bars_since_ob} =
        $confirmation_index
        -
        $creation_index;

    $result{ob_invalidated} =
        $nearest_invalidated;

    return \%result;
}

1;