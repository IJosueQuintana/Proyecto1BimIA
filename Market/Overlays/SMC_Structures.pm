package Market::Overlays::SMC_Structures;

use strict;
use warnings;

sub new {
    my ($class, %args) = @_;

    my $self = {
        smc_result  => $args{smc_result},
        show_zigzag => $args{show_zigzag} // 1,
        show_labels => $args{show_labels} // 1,
    };

    return bless $self, $class;
}

sub set_result {
    my ($self, $smc_result) = @_;
    $self->{smc_result} = $smc_result;
}

sub draw {
    my ($self, $canvas, $start, $end, $x_of, $state, $price_panel, %args) = @_;
   my $show_zigzag = $args{show_zigzag} // $self->{show_zigzag};
    my $show_labels = $args{show_labels} // $self->{show_labels};
    my $result      = $args{result}      // $self->{smc_result};
    my $style       = $args{style}       // 'external';

    return if !$result;
    return if !$result->{structure};

    my $structure = $result->{structure};
    my $scale     = $price_panel->{scale};

    return if !defined $state->{right};
    return if $state->{right} <= 0;

    my $right_limit = $state->{right} - 5;

    my @pivots_to_draw;
    my $prev_pivot;
    my $next_pivot;

    for my $p (@$structure) {
        if ($p->{index} < $start) {
            $prev_pivot = $p;
            next;
        }

        if ($p->{index} > $end) {
            $next_pivot = $p;
            last;
        }

        push @pivots_to_draw, $p;
    }

    unshift @pivots_to_draw, $prev_pivot if defined $prev_pivot;
    push @pivots_to_draw, $next_pivot if defined $next_pivot;

    my @visible_points;

    for my $p (@pivots_to_draw) {
        my $local_i = $p->{index} - $start;
        my $x = $x_of->($local_i);

        next if !defined $x;

        my $y = $scale->price_to_y(
            $p->{price},
            $state->{price_min},
            $state->{price_max},
            0,
            $state->{price_h}
        );

        next if !defined $y;

        push @visible_points, {
            x     => $x,
            y     => $y,
            label => $p->{label},
            type  => $p->{type},
            price => $p->{price},
            index => $p->{index},
        };
    }

    return if @visible_points < 2;

    for my $i (1 .. $#visible_points) {
        my $a = $visible_points[$i - 1];
        my $b = $visible_points[$i];

        my ($x1, $y1) = ($a->{x}, $a->{y});
        my ($x2, $y2) = ($b->{x}, $b->{y});

        next if $x1 > $right_limit && $x2 > $right_limit;

        if ($x2 > $right_limit && $x2 != $x1) {
            my $t = ($right_limit - $x1) / ($x2 - $x1);
            $x2 = $right_limit;
            $y2 = $y1 + $t * ($y2 - $y1);
        }

        if ($x1 > $right_limit && $x1 != $x2) {
            my $t = ($right_limit - $x2) / ($x1 - $x2);
            $x1 = $right_limit;
            $y1 = $y2 + $t * ($y1 - $y2);
        }
                my $line_color;

        if ($style eq 'internal') {
            $line_color = ($b->{price} > $a->{price})
                ? '#00C853'   # Verde: tramo alcista
                : '#D50000';  # Rojo: tramo bajista
        }
        else {
            $line_color = '#2962ff'; # Externo azul
        }

        $canvas->createLine(
            $x1, $y1,
            $x2, $y2,
            -fill  => $line_color,
            -width => 2
        );
    }

    for my $p (@visible_points) {
        next if $p->{x} > $right_limit;

        my $r = 3;

        $canvas->createOval(
            $p->{x} - $r, $p->{y} - $r,
            $p->{x} + $r, $p->{y} + $r,
            -fill    => ($style eq 'internal' ? '#00a676' : '#2962ff'),
            -outline => ($style eq 'internal' ? '#00a676' : '#2962ff'),
        );

        next if !$show_labels;
        next if !defined $p->{label};
        next if $p->{label} eq 'H';
        next if $p->{label} eq 'L';

        my $dy = $p->{type} eq 'HIGH' ? -14 : 14;

        $canvas->createText(
            $p->{x},
            $p->{y} + $dy,
            -text   => $p->{label},
            -fill   => '#111111',
            -font   => ['Arial', 8, 'bold'],
            -anchor => 'center'
        );
    }
}

sub draw_events {
    my (
        $self,
        $c,
        $start,
        $end,
        $x_of,
        $state,
        $price_panel,
        $events,
        %args
    ) = @_;

    return if !$events || ref($events) ne 'ARRAY';
    return if !$state || ref($state) ne 'HASH';
    return if !$state->{y_of};

    my $style = $args{style} // 'external';

    # Si por algún motivo no llegan estos argumentos,
    # se muestran por defecto para no ocultar todos los eventos.
    my $show_bos = exists $args{show_bos}
        ? $args{show_bos}
        : 1;

    my $show_choch = exists $args{show_choch}
        ? $args{show_choch}
        : 1;

    my $total_events   = 0;
    my $visible_events = 0;
    my $drawn_events   = 0;

    for my $e (@$events) {

        next if !$e || ref($e) ne 'HASH';

        my $type = $e->{raw_type} // $e->{type} // '';

        next if !$type;
        next if $type !~ /BOS|CHoCH/;

        next if $type =~ /BOS/
            && !$show_bos;

        next if $type =~ /CHoCH/
            && !$show_choch;

        $total_events++;

        my $event_i = defined $e->{break_index}
            ? $e->{break_index}
            : $e->{index};

        my $from_i = defined $e->{pivot_index}
            ? $e->{pivot_index}
            : $event_i;

        my $price = defined $e->{pivot_price}
            ? $e->{pivot_price}
            : $e->{price};

        next if !defined $event_i;
        next if !defined $from_i;
        next if !defined $price;

        my $seg_start = $from_i < $event_i
            ? $from_i
            : $event_i;

        my $seg_end = $from_i > $event_i
            ? $from_i
            : $event_i;

        # El segmento completo está fuera de la ventana visible.
        next if $seg_end < $start;
        next if $seg_start > $end;

        $visible_events++;

        # Conservamos los índices originales del evento
        # y usamos copias solamente para recortar el dibujo.
        my $draw_from_i  = $from_i;
        my $draw_event_i = $event_i;

        $draw_from_i = $start
            if $draw_from_i < $start;

        $draw_from_i = $end
            if $draw_from_i > $end;

        $draw_event_i = $start
            if $draw_event_i < $start;

        $draw_event_i = $end
            if $draw_event_i > $end;

        my $x1 = $x_of->($draw_from_i - $start);
        my $x2 = $x_of->($draw_event_i - $start);
        my $y  = $state->{y_of}->($price);

        next if !defined $x1;
        next if !defined $x2;
        next if !defined $y;

        my ($label, $color);

        if ($type =~ /CHoCH/) {

            $label = $style eq 'internal'
                ? 'iCHoCH'
                : 'CHoCH';

            $color = $style eq 'internal'
                ? '#ff9800'
                : '#f23645';
        }
        elsif ($type =~ /BOS/) {

            $label = $style eq 'internal'
                ? 'iBOS'
                : 'BOS';

            $color = $style eq 'internal'
                ? '#00a676'
                : '#089981';
        }
        else {
            next;
        }

        my $line_width = $style eq 'internal'
            ? 1
            : 2;

        my $font_size = $style eq 'internal'
            ? 7
            : 8;

        # ==========================================================
        # INTERNO:
        # iBOS / iCHoCH con línea entrecortada.
        #
        # EXTERNO:
        # BOS / CHoCH con línea continua.
        # ==========================================================
        if ($style eq 'internal') {

            $c->createLine(
                $x1,
                $y,
                $x2,
                $y,
                -fill  => $color,
                -width => $line_width,
                -dash  => [6, 4],
            );
        }
        else {

            $c->createLine(
                $x1,
                $y,
                $x2,
                $y,
                -fill  => $color,
                -width => $line_width,
            );
        }

        $c->createText(
            ($x1 + $x2) / 2,
            $y - 8,
            -text   => $label,
            -fill   => $color,
            -font   => ['Arial', $font_size, 'bold'],
            -anchor => 'center',
        );

        $drawn_events++;
    }

    return {
        style   => $style,
        total   => $total_events,
        visible => $visible_events,
        drawn   => $drawn_events,
    };
}

# ==============================================================
# FIBONACCI DEL ZIGZAG EXTERNO
#
# Dibuja exclusivamente el Fibonacci actual calculado por
# Market::Indicators::Liquidity.
#
# No realiza cálculos estructurales.
# ==============================================================
sub draw_external_fibonacci {
    my (
        $self,
        $canvas,
        $start,
        $end,
        $x_of,
        $state,
        $price_panel,
        $fibonacci,
    ) = @_;

    return if !$canvas;
    return if !$state;
    return if !$price_panel;
    return if !$x_of;

    return
        if !$fibonacci
        || ref($fibonacci) ne 'HASH';

    my $levels =
        $fibonacci->{levels};

    return
        if !$levels
        || ref($levels) ne 'ARRAY'
        || !@{$levels};

    my $to_index =
        $fibonacci->{to_index};

    return
        if !defined $to_index;

    # El último pivote todavía no pertenece a la ventana visible.
    return
        if $to_index > $end;

    my $scale =
        $price_panel->{scale};

    return if !$scale;

    my $right_limit =
        ($state->{right} // 0) - 5;

    return
        if $right_limit <= 0;

    # Las líneas comienzan en el último pivote del impulso.
    #
    # Si dicho pivote quedó fuera a la izquierda, empiezan en
    # el borde izquierdo visible.
    my $draw_start_index =
        $to_index;

    $draw_start_index = $start
        if $draw_start_index < $start;

    my $x1 =
        $x_of->(
            $draw_start_index
            -
            $start
        );

    return if !defined $x1;

    $x1 = $state->{left}
        if defined $state->{left}
        && $x1 < $state->{left};

    my $x2 =
        $right_limit;

    return
        if $x2 <= $x1;

    for my $level (@{$levels}) {
        next if !$level;
        next if ref($level) ne 'HASH';
        next if !defined $level->{ratio};
        next if !defined $level->{price};

        my $ratio =
            $level->{ratio};

        my $price =
            $level->{price};

        my $color =
            $level->{color}
            //
            '#2962ff';

        my $y =
            $scale->price_to_y(
                $price,
                $state->{price_min},
                $state->{price_max},
                0,
                $state->{price_h},
            );

        next if !defined $y;

        # No dibujar niveles fuera del panel de precios.
        next if $y < 0;
        next if $y > $state->{price_h};

        $canvas->createLine(
            $x1,
            $y,
            $x2,
            $y,

            -fill  => $color,
            -width => 1,
            -dash  => [4, 3],
        );

        my $label =
            sprintf(
                '%.3f  %.2f',
                $ratio,
                $price,
            );

        # Fondo pequeño para que el precio se lea sobre las velas.
        my $label_x =
            $x2 - 4;

        my $label_width = 112;

        $canvas->createRectangle(
            $label_x - $label_width,
            $y - 9,
            $label_x,
            $y + 9,

            -fill    => 'white',
            -outline => $color,
        );

        $canvas->createText(
            $label_x - 4,
            $y,

            -text   => $label,
            -fill   => $color,
            -font   => [
                'Arial',
                8,
                'bold',
            ],
            -anchor => 'e',
        );
    }

    # Etiqueta pequeña para distinguir la dirección del tramo.
    my $direction =
        $fibonacci->{direction}
        //
        '';

    if ($direction ne '') {
        my $direction_text =
            $direction eq 'UP'
                ? 'FIB EXT ↑'
                : 'FIB EXT ↓';

        $canvas->createText(
            $x1 + 5,
            48,

            -text   => $direction_text,
            -fill   => '#455a64',
            -font   => [
                'Arial',
                8,
                'bold',
            ],
            -anchor => 'w',
        );
    }
}

sub draw_fvg {
    my (
        $self,
        $c,
        $start,
        $end,
        $x_of,
        $state,
        $price_panel,
        $items,
        %args
    ) = @_;

    return if !$items;
    return if ref($items) ne 'ARRAY';
    return if !$state;
    return if !$state->{y_of};

    my $right_limit = $state->{right} - 5;

    my $replay_mode = $args{replay_mode} // 0;

    # Fuera de Replay se muestran los 3 FVG más recientes.
    my $history_limit = defined $args{history_limit}
        ? $args{history_limit}
        : 3;

    $history_limit = 1 if $history_limit < 1;

    my @fvg_to_draw;

    if ($replay_mode) {

        # ======================================================
        # REPLAY
        #
        # Mostrar únicamente los FVG todavía activos
        # hasta el replay_index.
        # ======================================================
        @fvg_to_draw = grep {
            my $fvg = $_;

            $fvg
            && ref($fvg) eq 'HASH'
            && !$fvg->{mitigated}
            && (
                !defined $fvg->{active}
                || $fvg->{active}
            )
        } @$items;
    }
    else {

        # ======================================================
        # MODO NORMAL
        #
        # Se dibujan solamente los FVG que todavía están activos.
        # Cuando una vela o una mecha toca la banda, el detector
        # marca el FVG como mitigado y deja de mostrarse.
        # ======================================================
        @fvg_to_draw = grep {
            my $fvg = $_;

            $fvg
            && ref($fvg) eq 'HASH'

            # No mostrar FVG mitigados.
            && !$fvg->{mitigated}

            # Compatibilidad con FVG antiguos que quizá no tengan
            # todavía definida la propiedad active.
            && (
                !defined $fvg->{active}
                || $fvg->{active}
            )

            && (
                ($fvg->{type} // '') eq 'BULLISH_FVG'
                || ($fvg->{type} // '') eq 'BEARISH_FVG'
            )
        } @$items;
    }

    # Orden cronológico.
    @fvg_to_draw = sort {
        ($a->{index} // 0) <=> ($b->{index} // 0)
    } @fvg_to_draw;

    # En modo normal conservar únicamente los últimos 3.
    if (!$replay_mode && @fvg_to_draw > $history_limit) {

        my $from = @fvg_to_draw - $history_limit;

        @fvg_to_draw =
            @fvg_to_draw[$from .. $#fvg_to_draw];
    }

    for my $fvg (@fvg_to_draw) {

        my $type = $fvg->{type} // '';

        next if $type ne 'BULLISH_FVG'
            && $type ne 'BEARISH_FVG';

        next if !defined $fvg->{left_index};
        next if !defined $fvg->{top};
        next if !defined $fvg->{bottom};

        my $right_index;

        if ($replay_mode) {

            # En Replay, un FVG activo se extiende hasta la
            # última vela visible del Replay.
            $right_index = $end;
        }
        else {

            # Fuera de Replay:
            #
            # Si fue mitigado, la banda termina exactamente
            # en la vela que la tocó.
            #
            # Si sigue activo, llega hasta la última vela actual.
            $right_index =
                defined $fvg->{mitigated_index}
                    ? $fvg->{mitigated_index}
                    : (
                        defined $fvg->{right_index}
                            ? $fvg->{right_index}
                            : $end
                    );
        }

        next if $right_index < $start;
        next if $fvg->{left_index} > $end;

        my $draw_left  = $fvg->{left_index};
        my $draw_right = $right_index;

        $draw_left = $start
            if $draw_left < $start;

        $draw_right = $end
            if $draw_right > $end;

        my $x1 = $x_of->($draw_left - $start);
        my $x2 = $x_of->($draw_right - $start);

        next if !defined $x1;
        next if !defined $x2;

        $x1 = $state->{left}
            if defined $state->{left}
            && $x1 < $state->{left};

        $x2 = $right_limit
            if $x2 > $right_limit;

        my $y_top =
            $state->{y_of}->($fvg->{top});

        my $y_bottom =
            $state->{y_of}->($fvg->{bottom});

        next if !defined $y_top;
        next if !defined $y_bottom;

        my $is_mitigated = $fvg->{mitigated} ? 1 : 0;

        my ($fill, $outline, $label);

        if ($is_mitigated && !$replay_mode) {

            # FVG histórico ya mitigado.
            $fill    = '#bdbdbd';
            $outline = '#757575';
            $label   = 'FVG mitigado';
        }
        elsif ($type eq 'BULLISH_FVG') {

            $fill    = '#81c784';
            $outline = '#388e3c';
            $label   = 'FVG';
        }
        else {

            $fill    = '#ef9a9a';
            $outline = '#d32f2f';
            $label   = 'FVG';
        }

        $c->createRectangle(
            $x1,
            $y_top,
            $x2,
            $y_bottom,
            -fill    => $fill,
            -outline => $outline,
            -width   => 1,
            -stipple => 'gray50',
        );

        $c->createText(
            ($x1 + $x2) / 2,
            ($y_top + $y_bottom) / 2,
            -text   => $label,
            -fill   => '#ffffff',
            -font   => ['Arial', 7, 'bold'],
            -anchor => 'center',
        );
    }
}

sub draw_order_blocks {
    my ($self, $c, $start, $end, $x_of, $state, $price_panel, $items) = @_;

    return if !$items || ref($items) ne 'ARRAY';

    my $scale       = $price_panel->{scale};
    my $right_limit = $state->{right} - 5;

    for my $ob (@$items) {

        next if !$ob;
        next if ref($ob) ne 'HASH';

        # ======================================================
        # SOLO ORDER BLOCKS ACTIVOS
        #
        # Cuando el precio atraviesa completamente el extremo
        # contrario del OB, deja de mostrarse.
        # ======================================================
        

        next if !defined $ob->{index};
        next if !defined $ob->{break_index};
        next if !defined $ob->{top};
        next if !defined $ob->{bottom};

        # El evento debe existir dentro o antes del rango visible.
        next if $ob->{break_index} < $start;
        next if $ob->{index} > $end;

        my $right_index = defined $ob->{right_index}
            ? $ob->{right_index}
            : $ob->{break_index};

        my $x1 = $x_of->(
            $ob->{index} - $start
        );

        my $x2 = $x_of->(
            $right_index - $start
        );

        $x1 = $state->{left}
            if $x1 < $state->{left};

        $x2 = $right_limit
            if $x2 > $right_limit;

        $x2 = $x1 + 25
            if $x2 <= $x1;

        my $y_top = $scale->price_to_y(
            $ob->{top},
            $state->{price_min},
            $state->{price_max},
            0,
            $state->{price_h}
        );

        my $y_bottom = $scale->price_to_y(
            $ob->{bottom},
            $state->{price_min},
            $state->{price_max},
            0,
            $state->{price_h}
        );

        my ($color, $txt);

        if (($ob->{type} // '') eq 'BULLISH_OB') {
            $color = '#2962ff';
            $txt   = 'Bull OB';
        }
        elsif (($ob->{type} // '') eq 'BEARISH_OB') {
            $color = '#f23645';
            $txt   = 'Bear OB';
        }
        else {
            next;
        }

        # Banda principal del Order Block.
        $c->createRectangle(
            $x1,
            $y_top,
            $x2,
            $y_bottom,
            -outline => $color,
            -width   => 1,
        );

        # Línea media de la zona.
        $c->createLine(
            $x1,
            ($y_top + $y_bottom) / 2,
            $x2,
            ($y_top + $y_bottom) / 2,
            -fill  => $color,
            -width => 2,
        );

        $c->createText(
            $x1 + 6,
            ($y_top + $y_bottom) / 2 - 8,
            -text   => $txt,
            -fill   => $color,
            -font   => ['Arial', 8, 'bold'],
            -anchor => 'w',
        );
    }
}

1;