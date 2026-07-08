package Market::Overlays::Liquidity;

use strict;
use warnings;

sub new {
    my ($class, %args) = @_;

    my $self = {
        liq_result => $args{liq_result},
        show_bsl   => $args{show_bsl} // 1,
        show_ssl   => $args{show_ssl} // 1,
        show_eqh   => $args{show_eqh} // 1,
        show_eql   => $args{show_eql} // 1,
        show_liquidity_events => $args{show_liquidity_events} // 1,
    };

    return bless $self, $class;
}

sub set_result {
    my ($self, $liq_result) = @_;
    $self->{liq_result} = $liq_result;
}

sub draw {
    my ($self, $canvas, $start, $end, $x_of, $state, $price_panel) = @_;

    return if !$self->{liq_result};

    my $scale = $price_panel->{scale};

    return if !defined $state->{right};
    return if $state->{right} <= 0;

    my $right_limit = $state->{right} - 5;

    $self->_draw_bsl_ssl($canvas, $start, $end, $x_of, $state, $scale, $right_limit)
    if $self->{show_bsl} || $self->{show_ssl};

$self->_draw_eqh_eql($canvas, $start, $end, $x_of, $state, $scale, $right_limit)
    if $self->{show_eqh} || $self->{show_eql};

$self->_draw_liquidity_events($canvas, $start, $end, $x_of, $state, $scale, $right_limit)
    if $self->{show_liquidity_events};
}

sub _draw_bsl_ssl {
    my ($self, $canvas, $start, $end, $x_of, $state, $scale, $right_limit) = @_;

    my $levels = $self->{liq_result}->{liquidity} || [];

    for my $lvl (@$levels) {
        my $created_index  = $lvl->{created_index} // $lvl->{index};
        my $resolved_index = $lvl->{resolved_index} // $end;

        next if $resolved_index < $start;
        next if $created_index > $end;

        next if $lvl->{type} eq 'BSL' && !$self->{show_bsl};
        next if $lvl->{type} eq 'SSL' && !$self->{show_ssl};

        my $local_i = $lvl->{index} - $start;
        my $x1 = $x_of->($local_i);
        my $end_index = defined $lvl->{resolved_index}
            ? $lvl->{resolved_index}
            : $end;

        my $x2 = $x_of->($end_index - $start);
        $x2 = $right_limit if $x2 > $right_limit;

        my $y = $scale->price_to_y(
            $lvl->{price},
            $state->{price_min},
            $state->{price_max},
            0,
            $state->{price_h}
        );

        my $color = $lvl->{type} eq 'BSL' ? '#f23645' : '#089981';

        $canvas->createLine(
            $x1, $y,
            $x2, $y,
            -fill  => $color,
            -dash  => [4, 4],
            -width => 1
        );

        $canvas->createText(
            $x2 - 4,
            $y - 8,
            -text   => $lvl->{type},
            -fill   => $color,
            -font   => ['Arial', 8, 'bold'],
            -anchor => 'e'
        );

                if (defined $lvl->{classification} && defined $lvl->{resolved_index}) {

            my $event_x = $x_of->($lvl->{resolved_index} - $start);
            next if $event_x < $state->{left};
            next if $event_x > $right_limit;

            my $txt = '';
            my $event_color = $color;

            if ($lvl->{classification} eq 'Sweep') {
                $txt = $lvl->{type} eq 'BSL' ? 'SWEEP' : 'SWEEP';
                $event_color = $color;
            }
            elsif ($lvl->{classification} eq 'Grab') {
                $txt = 'LQ GRAB';
                $event_color = '#ff9800';
            }
            elsif ($lvl->{classification} eq 'Run') {
                $txt = 'LQ RUN';
                $event_color = '#1565c0';
            }

            if ($txt ne '') {
                $canvas->createText(
                    $event_x,
                    $y + ($lvl->{type} eq 'BSL' ? -22 : 22),
                    -text   => $txt,
                    -fill   => $event_color,
                    -font   => ['Arial', 8, 'bold'],
                    -anchor => 'center'
                );
            }
        }
        
    }
}

sub _draw_liquidity_events {
    my ($self, $canvas, $start, $end, $x_of, $state, $scale, $right_limit) = @_;

    my $levels = $self->{liq_result}->{liquidity} || [];

    my %slot_count;

    for my $lvl (@$levels) {

        next if !defined $lvl->{classification};
        next if !defined $lvl->{resolved_index};
        next if !defined $lvl->{price};

        my $i = $lvl->{resolved_index};

        next if $i < $start;
        next if $i > $end;

        my $x = $x_of->($i - $start);
        next if $x < $state->{left};
        next if $x > $right_limit;

        my $y = $scale->price_to_y(
            $lvl->{price},
            $state->{price_min},
            $state->{price_max},
            0,
            $state->{price_h}
        );

        my $txt = '';
        my $color = '#000000';

        if ($lvl->{classification} eq 'Sweep') {
            $txt   = $lvl->{type} eq 'BSL' ? 'SWEEP ↑' : 'SWEEP ↓';
            $color = $lvl->{type} eq 'BSL' ? '#f23645' : '#089981';
        }
        elsif ($lvl->{classification} eq 'Grab') {
            $txt   = 'LQ GRAB';
            $color = '#ff9800';
        }
        elsif ($lvl->{classification} eq 'Run') {
            $txt   = 'LQ RUN';
            $color = '#1565c0';
        }

        next if $txt eq '';

        my $slot_x = int($x / 55);
        my $slot_y = int($y / 22);
        my $slot_key = join('|', $slot_x, $slot_y, $lvl->{type});

        my $stack = $slot_count{$slot_key}++;

        my $base_offset = 34;
        my $stack_gap   = 14;

        my $direction = $lvl->{type} eq 'BSL' ? -1 : 1;

        my $label_y = $y + $direction * ($base_offset + ($stack * $stack_gap));

        $label_y = 18 if $label_y < 18;
        $label_y = $state->{price_h} - 18 if $label_y > $state->{price_h} - 18;

        $canvas->createLine(
            $x,
            $y,
            $x,
            $label_y,
            -fill => $color,
            -dash => '.',
            -width => 1
        );

        $canvas->createText(
            $x,
            $label_y,
            -text   => $txt,
            -fill   => $color,
            -font   => ['Arial', 8, 'bold'],
            -anchor => 'center'
        );
    }
}




sub _draw_eqh_eql {
    my ($self, $canvas, $start, $end, $x_of, $state, $scale, $right_limit) = @_;

    my $equals = $self->{liq_result}->{equal_levels} || [];

    for my $eq (@$equals) {
        next if $eq->{index2} < $start;
        next if $eq->{index1} > $end;

        next if $eq->{type} eq 'EQH' && !$self->{show_eqh};
        next if $eq->{type} eq 'EQL' && !$self->{show_eql};

        my $x1 = $x_of->($eq->{index1} - $start);
        my $x2 = $x_of->($eq->{index2} - $start);

        $x1 = $state->{left} if $x1 < $state->{left};
        $x2 = $right_limit if $x2 > $right_limit;

        my $y = $scale->price_to_y(
            $eq->{price},
            $state->{price_min},
            $state->{price_max},
            0,
            $state->{price_h}
        );

        my $color = $eq->{type} eq 'EQH' ? '#d32f2f' : '#00796b';

        $canvas->createLine(
            $x1, $y,
            $x2, $y,
            -fill  => $color,
            -dash  => [2, 3],
            -width => 1
        );

        my $label_x = ($x1 + $x2) / 2;

        $canvas->createText(
            $label_x,
            $y + ($eq->{type} eq 'EQH' ? -10 : 10),
            -text   => $eq->{type},
            -fill   => $color,
            -font   => ['Arial', 8, 'bold'],
            -anchor => 'center'
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


1;