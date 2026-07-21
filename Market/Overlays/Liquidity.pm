package Market::Overlays::Liquidity;

use strict;
use warnings;

sub new {
    my ($class, %args) = @_;

    my $self = {
        liq_result => $args{liq_result},
        show_bsl   => $args{show_bsl} // 0,
        show_ssl   => $args{show_ssl} // 0,
        show_eqh   => $args{show_eqh} // 0,
        show_eql   => $args{show_eql} // 0,
        show_liquidity_events => $args{show_liquidity_events} // 0,
                show_supply_demand =>
            $args{show_supply_demand} // 0,

        show_supply_demand_poi =>
            exists $args{show_supply_demand_poi}
                ? ($args{show_supply_demand_poi} ? 1 : 0)
                : 1,

        show_broken_supply_demand =>
            $args{show_broken_supply_demand} // 0,
    };

    return bless $self, $class;
}

sub set_result {
    my ($self, $liq_result) = @_;
    $self->{liq_result} = $liq_result;
}

sub draw {
    my (
        $self,
        $canvas,
        $start,
        $end,
        $x_of,
        $state,
        $price_panel
    ) = @_;

    return if !$self->{liq_result};
    return if !$canvas;
    return if !$state;
    return if !$price_panel;
    return if !$price_panel->{scale};

    return if !defined $state->{right};
    return if $state->{right} <= 0;

    my $scale = $price_panel->{scale};
    my $right_limit = $state->{right} - 5;

    # BSL y SSL son una capa independiente.
    if ($self->{show_bsl} || $self->{show_ssl}) {
        $self->_draw_bsl_ssl(
            $canvas,
            $start,
            $end,
            $x_of,
            $state,
            $scale,
            $right_limit,
        );
    }

    # EQH y EQL son una capa independiente.
    if ($self->{show_eqh} || $self->{show_eql}) {
        $self->_draw_eqh_eql(
            $canvas,
            $start,
            $end,
            $x_of,
            $state,
            $scale,
            $right_limit,
        );
    }

    # Sweep, Grab y Run son una capa independiente.
    if ($self->{show_liquidity_events}) {
        $self->_draw_liquidity_events(
            $canvas,
            $start,
            $end,
            $x_of,
            $state,
            $scale,
            $right_limit,
        );
    }

        if ($self->{show_supply_demand}) {
        $self->_draw_supply_demand(
            $canvas,
            $start,
            $end,
            $x_of,
            $state,
            $scale,
            $right_limit,
        );
    }



}

sub _draw_bsl_ssl {
    my (
        $self,
        $canvas,
        $start,
        $end,
        $x_of,
        $state,
        $scale,
        $right_limit
    ) = @_;

    my $levels = $self->{liq_result}->{liquidity} || [];

    return if ref($levels) ne 'ARRAY';

    for my $lvl (@$levels) {

        next if !$lvl;
        next if ref($lvl) ne 'HASH';

        my $type = $lvl->{type} // '';

        # Este método solo maneja BSL y SSL.
        next if $type ne 'BSL' && $type ne 'SSL';

        # Respetar estrictamente cada flag.
        next if $type eq 'BSL' && !$self->{show_bsl};
        next if $type eq 'SSL' && !$self->{show_ssl};

        next if !defined $lvl->{price};

        my $created_index =
            defined $lvl->{created_index}
                ? $lvl->{created_index}
                : $lvl->{index};

        next if !defined $created_index;

        my $resolved_index =
            defined $lvl->{resolved_index}
                ? $lvl->{resolved_index}
                : $end;

        # El segmento completo está fuera de la ventana visible.
        next if $resolved_index < $start;
        next if $created_index > $end;

        # Recorte visual; no alteramos los índices originales.
        my $draw_start_index = $created_index;
        my $draw_end_index   = $resolved_index;

        $draw_start_index = $start
            if $draw_start_index < $start;

        $draw_end_index = $end
            if $draw_end_index > $end;

        my $x1 = $x_of->($draw_start_index - $start);
        my $x2 = $x_of->($draw_end_index - $start);

        next if !defined $x1;
        next if !defined $x2;

        $x1 = $state->{left}
            if defined $state->{left}
            && $x1 < $state->{left};

        $x2 = $right_limit
            if $x2 > $right_limit;

        my $y = $scale->price_to_y(
            $lvl->{price},
            $state->{price_min},
            $state->{price_max},
            0,
            $state->{price_h},
        );

        next if !defined $y;

        my $color = $type eq 'BSL'
            ? '#f23645'
            : '#089981';

        $canvas->createLine(
            $x1,
            $y,
            $x2,
            $y,
            -fill  => $color,
            -dash  => [4, 4],
            -width => 1,
        );

        $canvas->createText(
            $x2 - 4,
            $y - 8,
            -text   => $type,
            -fill   => $color,
            -font   => ['Arial', 8, 'bold'],
            -anchor => 'e',
        );

        # IMPORTANTE:
        # Aquí no se dibujan Sweep, Grab ni Run.
        # Esos eventos pertenecen exclusivamente a
        # _draw_liquidity_events().
    }
}


sub _draw_liquidity_events {
    my (
        $self,
        $canvas,
        $start,
        $end,
        $x_of,
        $state,
        $scale,
        $right_limit
    ) = @_;

    # Seguridad adicional.
    return if !$self->{show_liquidity_events};

    my $levels = $self->{liq_result}->{liquidity} || [];

    return if ref($levels) ne 'ARRAY';

    my %slot_count;

    for my $lvl (@$levels) {

        next if !$lvl;
        next if ref($lvl) ne 'HASH';

        my $type = $lvl->{type} // '';

        # Los eventos de liquidez solo pertenecen a BSL/SSL.
        next if $type ne 'BSL' && $type ne 'SSL';

        next if !defined $lvl->{classification};
        next if !defined $lvl->{resolved_index};
        next if !defined $lvl->{price};

        my $classification = $lvl->{classification};

        next if $classification ne 'Sweep'
            && $classification ne 'Grab'
            && $classification ne 'Run';

        my $i = $lvl->{resolved_index};

        next if $i < $start;
        next if $i > $end;

        my $x = $x_of->($i - $start);

        next if !defined $x;
        next if defined $state->{left}
            && $x < $state->{left};

        next if $x > $right_limit;

        my $y = $scale->price_to_y(
            $lvl->{price},
            $state->{price_min},
            $state->{price_max},
            0,
            $state->{price_h},
        );

        next if !defined $y;

        my ($text, $color);

        if ($classification eq 'Sweep') {

            $text = $type eq 'BSL'
                ? 'SWEEP ↑'
                : 'SWEEP ↓';

            $color = $type eq 'BSL'
                ? '#f23645'
                : '#089981';
        }
        elsif ($classification eq 'Grab') {
            $text  = 'LQ GRAB';
            $color = '#ff9800';
        }
        elsif ($classification eq 'Run') {
            $text  = 'LQ RUN';
            $color = '#1565c0';
        }
        else {
            next;
        }

        my $slot_x = int($x / 55);
        my $slot_y = int($y / 22);

        my $slot_key = join(
            '|',
            $slot_x,
            $slot_y,
            $type,
        );

        my $stack = $slot_count{$slot_key}++;

        my $base_offset = 34;
        my $stack_gap   = 14;

        my $direction = $type eq 'BSL'
            ? -1
            : 1;

        my $label_y =
            $y
            + $direction
            * ($base_offset + ($stack * $stack_gap));

        $label_y = 18
            if $label_y < 18;

        $label_y = $state->{price_h} - 18
            if $label_y > $state->{price_h} - 18;

        $canvas->createLine(
            $x,
            $y,
            $x,
            $label_y,
            -fill  => $color,
            -dash  => '.',
            -width => 1,
        );

        $canvas->createText(
            $x,
            $label_y,
            -text   => $text,
            -fill   => $color,
            -font   => ['Arial', 8, 'bold'],
            -anchor => 'center',
        );
    }
}


sub _draw_eqh_eql {
    my (
        $self,
        $canvas,
        $start,
        $end,
        $x_of,
        $state,
        $scale,
        $right_limit
    ) = @_;

    my $equals = $self->{liq_result}->{equal_levels} || [];

    return if ref($equals) ne 'ARRAY';

    for my $eq (@$equals) {

        next if !$eq;
        next if ref($eq) ne 'HASH';

        my $type = $eq->{type} // '';

        # Este método solo acepta EQH o EQL.
        next if $type ne 'EQH' && $type ne 'EQL';

        next if $type eq 'EQH'
            && !$self->{show_eqh};

        next if $type eq 'EQL'
            && !$self->{show_eql};

        next if !defined $eq->{index1};
        next if !defined $eq->{index2};
        next if !defined $eq->{price};

        my $segment_start =
            $eq->{index1} < $eq->{index2}
                ? $eq->{index1}
                : $eq->{index2};

        my $segment_end =
            $eq->{index1} > $eq->{index2}
                ? $eq->{index1}
                : $eq->{index2};

        # El segmento completo está fuera de la ventana.
        next if $segment_end < $start;
        next if $segment_start > $end;

        my $draw_index1 = $eq->{index1};
        my $draw_index2 = $eq->{index2};

        $draw_index1 = $start
            if $draw_index1 < $start;

        $draw_index1 = $end
            if $draw_index1 > $end;

        $draw_index2 = $start
            if $draw_index2 < $start;

        $draw_index2 = $end
            if $draw_index2 > $end;

        my $x1 = $x_of->($draw_index1 - $start);
        my $x2 = $x_of->($draw_index2 - $start);

        next if !defined $x1;
        next if !defined $x2;

        $x1 = $state->{left}
            if defined $state->{left}
            && $x1 < $state->{left};

        $x2 = $right_limit
            if $x2 > $right_limit;

        my $y = $scale->price_to_y(
            $eq->{price},
            $state->{price_min},
            $state->{price_max},
            0,
            $state->{price_h},
        );

        next if !defined $y;

        my $color = $type eq 'EQH'
            ? '#d32f2f'
            : '#00796b';

        $canvas->createLine(
            $x1,
            $y,
            $x2,
            $y,
            -fill  => $color,
            -dash  => [2, 3],
            -width => 1,
        );

        my $label_x = ($x1 + $x2) / 2;

        my $label_y = $type eq 'EQH'
            ? $y - 10
            : $y + 10;

        $canvas->createText(
            $label_x,
            $label_y,
            -text   => $type,
            -fill   => $color,
            -font   => ['Arial', 8, 'bold'],
            -anchor => 'center',
        );
    }
}
sub draw_volume_pivots {
    my ($self, $c, $start, $end, $x_of, $state, $price_panel) = @_;

    my $result = $self->{liq_result};
    return if !$result;
    return if !$result->{volume_pivots};
    return if !$state->{y_of};

    for my $p (@{$result->{volume_pivots}}) {
        next if !defined $p->{index};
        next if !defined $p->{price};

        my $i = $p->{index};
        next if $i < $start || $i > $end;

        my $x = $x_of->($i - $start);
        my $y = $state->{y_of}->($p->{price});

        my $r = 5;

        $c->createOval(
            $x - $r, $y - $r,
            $x + $r, $y + $r,
            -fill    => '#8e24aa',
            -outline => '#4a148c',
            -width   => 1,
        );

        $c->createText(
            $x,
            $y - 12,
            -text => 'VOL',
            -fill => '#8e24aa',
            -font => ['Arial', 7, 'bold'],
        );
    }
}


sub _draw_supply_demand {
    my (
        $self,
        $canvas,
        $start,
        $end,
        $x_of,
        $state,
        $scale,
        $right_limit,
    ) = @_;

    return if !$self->{show_supply_demand};

    my $zones =
        $self->{liq_result}
            ->{supply_demand_zones}
        || [];

    return if ref($zones) ne 'ARRAY';

    for my $zone (@$zones) {

        next if !$zone;
        next if ref($zone) ne 'HASH';

        next if !defined $zone->{top};
        next if !defined $zone->{bottom};
        next if !defined $zone->{created_index};

        my $zone_state =
            $zone->{state} // 'ACTIVE';

        

        my $created_index =
            $zone->{created_index};

        my $resolved_index =
            defined $zone->{resolved_index}
                ? $zone->{resolved_index}
                : $end;

        next if $resolved_index < $start;
        next if $created_index > $end;

        my $draw_start_index =
            $created_index < $start
                ? $start
                : $created_index;

        my $draw_end_index =
            $resolved_index > $end
                ? $end
                : $resolved_index;

        my $x1 =
            $x_of->(
                $draw_start_index - $start
            );

        my $x2 =
            $x_of->(
                $draw_end_index - $start
            );

        next if !defined $x1;
        next if !defined $x2;

        $x1 = $state->{left}
            if defined $state->{left}
            && $x1 < $state->{left};

        $x2 = $right_limit
            if $x2 > $right_limit;

        next if $x2 <= $x1;

        my $y_top =
            $scale->price_to_y(
                $zone->{top},
                $state->{price_min},
                $state->{price_max},
                0,
                $state->{price_h},
            );

        my $y_bottom =
            $scale->price_to_y(
                $zone->{bottom},
                $state->{price_min},
                $state->{price_max},
                0,
                $state->{price_h},
            );

        next if !defined $y_top;
        next if !defined $y_bottom;

        my $type =
            $zone->{type} // '';

        my (
            $fill,
            $outline,
            $text_color,
        );

        if ($type eq 'SUPPLY') {
        $fill       = '#ededed';
        $outline    = '#ededed';
        $text_color = '#ffffff';
    }
    elsif ($type eq 'DEMAND') {
        $fill       = '#00ffff';
        $outline    = '#00ffff';
        $text_color = '#ffffff';
    }
        else {
            next;
        }

        my $stipple =
            $zone_state eq 'ACTIVE'
                ? 'gray50'
                : $zone_state eq 'MITIGATED'
                    ? 'gray50'
                    : 'gray25';

                # ======================================================
        # ZONA ROTA
        #
        # El DIY elimina la banda y conserva únicamente
        # una línea horizontal en el punto medio.
        # ======================================================
        if ($zone_state eq 'BROKEN') {

            next
                if !defined $zone->{poi};

            my $y_poi =
                $scale->price_to_y(
                    $zone->{poi},
                    $state->{price_min},
                    $state->{price_max},
                    0,
                    $state->{price_h},
                );

            next if !defined $y_poi;

            my $broken_color =
                $type eq 'DEMAND'
                    ? '#00cfd1'
                    : '#d8d8d8';

            $canvas->createLine(
                $x1,
                $y_poi,
                $x2,
                $y_poi,

                -fill  => $broken_color,
                -width => 1,
            );

            # Igual que el DIY:
            # la zona convertida a BOS no mantiene
            # las etiquetas SUPPLY, DEMAND ni POI.
            next;
        }
        $canvas->createRectangle(
            $x1,
            $y_top,
            $x2,
            $y_bottom,

            -fill    => $fill,
            -outline => $outline,
            -width   => 1,
            -stipple => $stipple,
        );

        if (
            $self->{show_supply_demand_poi}
            &&
            defined $zone->{poi}
        ) {
            my $y_poi =
                $scale->price_to_y(
                    $zone->{poi},
                    $state->{price_min},
                    $state->{price_max},
                    0,
                    $state->{price_h},
                );

            if (defined $y_poi) {
                $canvas->createLine(
                    $x1,
                    $y_poi,
                    $x2,
                    $y_poi,

                    -fill  => $outline,
                    -dash  => [3, 3],
                    -width => 1,
                );

                $canvas->createText(
                    $x1 + 4,
                 $y_poi - 6,

                    -text   => 'POI',
                    -fill   => $text_color,
                    -font   => ['Arial', 7, 'normal'],
                    -anchor => 'w',
                );
            }
        }

        my $label = $type;

        $label .= ' M'
            if $zone_state eq 'MITIGATED';

        $label .= ' X'
            if $zone_state eq 'BROKEN';

                $canvas->createText(
            ($x1 + $x2) / 2,
            $y_top + 7,

            -text   => $label,
            -fill   => $text_color,
            -font   => ['Arial', 7, 'bold'],
            -anchor => 'center',
        );
    }
}

1;