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

        $canvas->createLine(
            $x1, $y1,
            $x2, $y2,
            -fill  => '#2962ff',
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
    my ($self, $c, $start, $end, $x_of, $state, $price_panel, $events, %args) = @_;

    return if !$events || ref($events) ne 'ARRAY';
    return if !$state->{y_of};

    my $style = $args{style} // 'external';

    my $total_events   = 0;
    my $visible_events = 0;
    my $drawn_events   = 0;

    for my $e (@$events) {

        my $type = $e->{raw_type} // $e->{type} // '';
        next if !$type;

        next if $type =~ /BOS/   && !$args{show_bos};
        next if $type =~ /CHoCH/ && !$args{show_choch};
        next if $type !~ /BOS|CHoCH/;

        $total_events++;

        my $event_i = $e->{break_index} // $e->{index};
        my $from_i  = $e->{pivot_index} // $event_i;
        my $price   = $e->{pivot_price} // $e->{price};

        next if !defined $event_i;
        next if !defined $from_i;
        next if !defined $price;

        my $seg_start = $from_i < $event_i ? $from_i : $event_i;
        my $seg_end   = $from_i > $event_i ? $from_i : $event_i;

       
        #$style, $type, $from_i, $event_i, $start, $end, $price;

        next if $seg_end < $start;
        next if $seg_start > $end;

        $visible_events++;

        $from_i  = $start if $from_i < $start;
        $from_i  = $end   if $from_i > $end;

        $event_i = $start if $event_i < $start;
        $event_i = $end   if $event_i > $end;

        my $x1 = $x_of->($from_i - $start);
        my $x2 = $x_of->($event_i - $start);
        my $y  = $state->{y_of}->($price);

        next if !defined $x1 || !defined $x2 || !defined $y;

        my ($label, $color);

        if ($type =~ /CHoCH/) {
            $label = $style eq 'internal' ? 'iCHoCH' : 'CHoCH';
            $color = $style eq 'internal' ? '#ff9800' : '#f23645';
        }
        elsif ($type =~ /BOS/) {
            $label = $style eq 'internal' ? 'iBOS' : 'BOS';
            $color = $style eq 'internal' ? '#00a676' : '#089981';
        }
        else {
            next;
        }

        my $line_width = $style eq 'internal' ? 1 : 2;
        my $font_size  = $style eq 'internal' ? 7 : 8;  

        $c->createLine(
            $x1, $y,
            $x2, $y,
            -fill  => $color,
            -width => $line_width,
        );

        $c->createText(
            ($x1 + $x2) / 2,
            $y - 8,
            -text => $label,
            -fill => $color,
            -font => ['Arial', $font_size, 'bold']
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

sub draw_fvg {
    my ($self, $c, $start, $end, $x_of, $state, $price_panel, $items) = @_;

    return if !$items || ref($items) ne 'ARRAY';

    my $scale = $price_panel->{scale};
    my $right_limit = $state->{right} - 5;

    for my $fvg (@$items) {

        next if !defined $fvg->{left_index};
        next if !defined $fvg->{right_index};
        next if !defined $fvg->{top};
        next if !defined $fvg->{bottom};

        # Mostrar solo FVG activos, no mitigados
        next if $fvg->{mitigated};

        next if $fvg->{right_index} < $start;
        next if $fvg->{left_index} > $end;

        my $x1 = $x_of->($fvg->{left_index} - $start);
        my $x2 = $right_limit; # extender hasta la derecha como TradingView

        $x1 = $state->{left} if $x1 < $state->{left};
        $x2 = $right_limit if $x2 > $right_limit;
        $x2 = $x1 + 25 if $x2 <= $x1;

        my $y_top = $scale->price_to_y(
            $fvg->{top},
            $state->{price_min},
            $state->{price_max},
            0,
            $state->{price_h}
        );

        my $y_bottom = $scale->price_to_y(
            $fvg->{bottom},
            $state->{price_min},
            $state->{price_max},
            0,
            $state->{price_h}
        );

        my $color = $fvg->{type} eq 'BULLISH_FVG'
            ? '#089981'
            : '#f23645';

        $c->createRectangle(
            $x1, $y_top,
            $x2, $y_bottom,
            -outline => $color,
            -width   => 1,
        );

        $c->createLine(
            $x1,
            ($y_top + $y_bottom) / 2,
            $x2,
            ($y_top + $y_bottom) / 2,
            -fill  => $color,
            -width => 2,
        );

        $c->createText(
            ($x1 + $x2) / 2,
            ($y_top + $y_bottom) / 2 - 8,
            -text   => 'FVG',
            -fill   => $color,
            -font   => ['Arial', 8, 'bold'],
        );
    }
}

sub draw_order_blocks {
    my ($self, $c, $start, $end, $x_of, $state, $price_panel, $items) = @_;

    return if !$items || ref($items) ne 'ARRAY';

    my $scale = $price_panel->{scale};
    my $right_limit = $state->{right} - 5;

    for my $ob (@$items) {

        next if !defined $ob->{index};
        next if !defined $ob->{break_index};
        next if !defined $ob->{top};
        next if !defined $ob->{bottom};

        next if $ob->{break_index} < $start;
        next if $ob->{index} > $end;

        my $x1 = $x_of->($ob->{index} - $start);
        my $x2 = $x_of->($ob->{break_index} - $start);

        $x1 = $state->{left} if $x1 < $state->{left};
        $x2 = $right_limit if $x2 > $right_limit;
        $x2 = $x1 + 25 if $x2 <= $x1;

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

        if ($ob->{invalidated}) {
            $color = '#808080';
        }
        elsif ($ob->{type} eq 'BULLISH_OB') {
            $color = '#2962ff';
        }
        else {
            $color = '#f23645';
        }

        $txt = $ob->{type} eq 'BULLISH_OB' ? 'Bull OB' : 'Bear OB';

        # Caja limpia
        $c->createRectangle(
            $x1, $y_top,
            $x2, $y_bottom,
            -outline => $color,
            -width   => 1,
        );

        # Línea central
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