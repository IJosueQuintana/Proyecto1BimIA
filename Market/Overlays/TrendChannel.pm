package Market::Overlays::TrendChannel;

use strict;
use warnings;

sub new {
    my ($class, %args) = @_;

    my $self = {
        result => $args{result} || {
            trendlines => [],
            channels   => [],
        },

        show_touches => $args{show_touches} // 1,
        show_labels  => $args{show_labels}  // 1,
    };

    return bless $self, $class;
}

sub set_result {
    my ($self, $result) = @_;

    $self->{result} = $result || {
        trendlines => [],
        channels   => [],
    };
}

sub draw_trendlines {
    my (
        $self,
        $canvas,
        $start,
        $end,
        $x_of,
        $state,
        $price_panel,
        %args
    ) = @_;

    return if !$canvas;
    return if !$x_of;
    return if !$state;
    return if !$price_panel;

    my $result =
        $args{result}
        || $self->{result}
        || {};

    my $trendlines =
        $result->{trendlines}
        || [];

    return if ref($trendlines) ne 'ARRAY';
    return if !@$trendlines;

    my $scale = $price_panel->{scale};

    return if !$scale;
    return if !defined $state->{price_min};
    return if !defined $state->{price_max};

    for my $line (@$trendlines) {
        next if !$line;

        $self->_draw_single_trendline(
            canvas      => $canvas,
            line        => $line,
            start       => $start,
            end         => $end,
            x_of        => $x_of,
            state       => $state,
            scale       => $scale,
            show_touches => (
                defined $args{show_touches}
                ? $args{show_touches}
                : $self->{show_touches}
            ),
            show_labels => (
                defined $args{show_labels}
                ? $args{show_labels}
                : $self->{show_labels}
            ),
        );
    }
}

sub _draw_single_trendline {
    my ($self, %args) = @_;

    my $canvas = $args{canvas};
    my $line   = $args{line};
    my $start  = $args{start};
    my $end    = $args{end};
    my $x_of   = $args{x_of};
    my $state  = $args{state};
    my $scale  = $args{scale};

    return if !$line;

    my $line_start =
        $line->{start_index};

    return if !defined $line_start;

    # Si la línea fue rota, termina en la vela de ruptura.
    # Si continúa activa, se extiende hasta el borde derecho visible.
    my $line_end;

    if (
        $line->{broken}
        && defined $line->{break_index}
    ) {
        $line_end = $line->{break_index};
    }
    else {
        $line_end = $end;
    }

    # La línea completa queda fuera de la ventana visible.
    return if $line_end < $start;
    return if $line_start > $end;

    my $visible_start =
        $line_start < $start
        ? $start
        : $line_start;

    my $visible_end =
        $line_end > $end
        ? $end
        : $line_end;

    return if $visible_end < $visible_start;

    my $price1 =
        $self->_line_value_at(
            $line,
            $visible_start
        );

    my $price2 =
        $self->_line_value_at(
            $line,
            $visible_end
        );

    return if !defined $price1;
    return if !defined $price2;

    my $local_start =
        $visible_start - $start;

    my $local_end =
        $visible_end - $start;

    my $x1 = $x_of->($local_start);
    my $x2 = $x_of->($local_end);

    return if !defined $x1;
    return if !defined $x2;

    my $y1 = $scale->price_to_y(
        $price1,
        $state->{price_min},
        $state->{price_max},
        0,
        $state->{price_h},
    );

    my $y2 = $scale->price_to_y(
        $price2,
        $state->{price_min},
        $state->{price_max},
        0,
        $state->{price_h},
    );

    return if !defined $y1;
    return if !defined $y2;

    my $is_bullish =
        ($line->{type} // '') eq 'BULLISH';

    my $color =
        $is_bullish
        ? '#00897B'
        : '#E53935';

    my @dash =
        $line->{broken}
        ? (7, 4)
        : ();

    $canvas->createLine(
        $x1,
        $y1,
        $x2,
        $y2,

        -fill  => $color,
        -width => 2,

        (@dash
            ? (-dash => \@dash)
            : ()
        ),

        -tags => [
            'trend_channel',
            'automatic_trendline',
        ],
    );

    if ($args{show_touches}) {
        $self->_draw_touches(
            canvas => $canvas,
            line   => $line,
            start  => $start,
            end    => $end,
            x_of   => $x_of,
            state  => $state,
            scale  => $scale,
            color  => $color,
        );
    }

    if ($args{show_labels}) {
        $self->_draw_label(
            canvas => $canvas,
            line   => $line,
            x      => $x2,
            y      => $y2,
            color  => $color,
        );
    }

    if (
        $line->{broken}
        && defined $line->{break_index}
        && $line->{break_index} >= $start
        && $line->{break_index} <= $end
    ) {
        $self->_draw_break_marker(
            canvas => $canvas,
            line   => $line,
            start  => $start,
            x_of   => $x_of,
            state  => $state,
            scale  => $scale,
            color  => $color,
        );
    }
}

sub _draw_touches {
    my ($self, %args) = @_;

    my $canvas = $args{canvas};
    my $line   = $args{line};
    my $start  = $args{start};
    my $end    = $args{end};
    my $x_of   = $args{x_of};
    my $state  = $args{state};
    my $scale  = $args{scale};
    my $color  = $args{color};

    my $touch_indices =
        $line->{touch_indices}
        || [];

    return if ref($touch_indices) ne 'ARRAY';

    for my $index (@$touch_indices) {
        next if !defined $index;
        next if $index < $start;
        next if $index > $end;

        my $price =
            $self->_line_value_at(
                $line,
                $index
            );

        next if !defined $price;

        my $x =
            $x_of->($index - $start);

        my $y = $scale->price_to_y(
            $price,
            $state->{price_min},
            $state->{price_max},
            0,
            $state->{price_h},
        );

        next if !defined $x;
        next if !defined $y;

        my $radius = 3;

        $canvas->createOval(
            $x - $radius,
            $y - $radius,
            $x + $radius,
            $y + $radius,

            -fill    => 'white',
            -outline => $color,
            -width   => 2,

            -tags => [
                'trend_channel',
                'trendline_touch',
            ],
        );
    }
}

sub _draw_label {
    my ($self, %args) = @_;

    my $canvas = $args{canvas};
    my $line   = $args{line};
    my $x      = $args{x};
    my $y      = $args{y};
    my $color  = $args{color};

    my $direction =
        ($line->{type} // '') eq 'BULLISH'
        ? 'Trendline alcista'
        : 'Trendline bajista';

    my $status =
        $line->{broken}
        ? 'ROTA'
        : 'ACTIVA';

    my $touches =
        $line->{touches}
        // 2;

    my $score =
        defined $line->{score}
        ? sprintf('%.1f', $line->{score})
        : '0';

    my $text =
          $direction
        . ' | '
        . $status
        . ' | Toques: '
        . $touches
        . ' | Score: '
        . $score;

    $canvas->createText(
        $x - 5,
        $y - 9,

        -text   => $text,
        -fill   => $color,
        -anchor => 'e',
        -font   => ['Arial', 8, 'bold'],

        -tags => [
            'trend_channel',
            'trendline_label',
        ],
    );
}

sub _draw_break_marker {
    my ($self, %args) = @_;

    my $canvas = $args{canvas};
    my $line   = $args{line};
    my $start  = $args{start};
    my $x_of   = $args{x_of};
    my $state  = $args{state};
    my $scale  = $args{scale};
    my $color  = $args{color};

    my $index =
        $line->{break_index};

    return if !defined $index;

    my $price =
        defined $line->{break_price}
        ? $line->{break_price}
        : $self->_line_value_at($line, $index);

    return if !defined $price;

    my $x =
        $x_of->($index - $start);

    my $y = $scale->price_to_y(
        $price,
        $state->{price_min},
        $state->{price_max},
        0,
        $state->{price_h},
    );

    return if !defined $x;
    return if !defined $y;

    $canvas->createText(
        $x,
        $y,

        -text   => '✕',
        -fill   => $color,
        -font   => ['Arial', 11, 'bold'],
        -anchor => 'center',

        -tags => [
            'trend_channel',
            'trendline_break',
        ],
    );
}

sub _line_value_at {
    my ($self, $line, $index) = @_;

    return undef if !$line;
    return undef if !defined $line->{slope};
    return undef if !defined $line->{intercept};
    return undef if !defined $index;

    return
          ($line->{slope} * $index)
        + $line->{intercept};
}

1;