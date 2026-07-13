package Market::Overlays::TrendLines;

use strict;
use warnings;

sub new {
    my ($class, %args) = @_;

    my $self = {
        bullish_color => $args{bullish_color} // '#16a34a',
        bearish_color => $args{bearish_color} // '#ef4444',
        width         => $args{width} // 1.2,
        anchor_pivots => [],
    };

    return bless $self, $class;
}

sub get_line_points {
    my ($self, $data, $x_of, $state) = @_;

    return undef if !$data || ref($data) ne 'ARRAY';
    return undef if @$data < 2;

    my $first = $data->[0];
    my $last  = $data->[-1];

    return undef if !defined $first->{close} || !defined $last->{close};
    return undef if !defined $state->{y_of};

    my $x1 = $x_of->(0);
    my $x2 = $x_of->(@$data - 1);
    my $y1 = $state->{y_of}->($first->{close});
    my $y2 = $state->{y_of}->($last->{close});

    return undef if !defined $x1 || !defined $x2 || !defined $y1 || !defined $y2;

    return {
        x1 => $x1,
        y1 => $y1,
        x2 => $x2,
        y2 => $y2,
    };
}

sub clear {
    my ($self) = @_;
    $self->{anchor_pivots} = [];
}

sub _select_significant_pivots {
    my ($self, $result, $start, $end) = @_;

    return [] if !$result || !$result->{structure} || !@{$result->{structure}};

    my @structure = @{$result->{structure}};
    my @significant;

    for (my $i = $#structure; $i >= 0; $i--) {
        my $pivot = $structure[$i];
        next if !$pivot || !defined $pivot->{index};

        my $label = $pivot->{label} // '';
        next if $label eq 'H' || $label eq 'L';
        next if $label !~ /HH|HL|LH|LL/;

        push @significant, {
            index => $pivot->{index},
            price => $pivot->{price},
            label => $label,
            type  => $pivot->{type},
        };

        last if @significant >= 2;
    }

    return \@significant if @significant >= 2;

    my @fallback;
    for (my $i = $#structure; $i >= 0; $i--) {
        my $pivot = $structure[$i];
        next if !$pivot || !defined $pivot->{index};

        push @fallback, {
            index => $pivot->{index},
            price => $pivot->{price},
            label => $pivot->{label} // '',
            type  => $pivot->{type},
        };

        last if @fallback >= 2;
    }

    return \@fallback;
}

sub draw {
    my ($self, $canvas, $data, $start, $end, $x_of, $state, $price_panel, %args) = @_;

    return if !$canvas;
    return if !$state->{y_of};

    my $result = $args{result};
    $self->{anchor_pivots} = $self->_select_significant_pivots($result, $start, $end)
        if $result && $result->{structure};

    my @pivot_points;
    my $visible_span = ($end - $start);
    $visible_span = 1 if $visible_span < 1;

    for my $anchor (@{$self->{anchor_pivots} || []}) {
        my $local_i = $anchor->{index} - $start;
        $local_i = 0 if $local_i < 0;
        $local_i = $visible_span if $local_i > $visible_span;

        my $x = $x_of->($local_i);
        my $y = $state->{y_of}->($anchor->{price});
        next if !defined $x || !defined $y;

        push @pivot_points, {
            x => $x,
            y => $y,
            label => $anchor->{label},
            price => $anchor->{price},
        };
    }

    return if @pivot_points < 2;

    my $points = {
        x1 => $pivot_points[0]{x},
        y1 => $pivot_points[0]{y},
        x2 => $pivot_points[1]{x},
        y2 => $pivot_points[1]{y},
    };

    return if !$points;

    my $right_limit = $state->{right} - 5;
    my $left_limit  = $state->{left} + 2;
    my $x1 = $points->{x1};
    my $x2 = $points->{x2};
    my $y1 = $points->{y1};
    my $y2 = $points->{y2};

    if ($x2 < $left_limit) {
        return;
    }

    if ($x1 > $right_limit && $x2 > $right_limit) {
        return;
    }

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

    my $color = $pivot_points[1]{price} > $pivot_points[0]{price}
        ? $self->{bullish_color}
        : $self->{bearish_color};

    $canvas->createLine(
        $x1, $y1,
        $x2, $y2,
        -fill   => $color,
        -width  => $self->{width},
    );

    my $label_text = $pivot_points[0]{label} . ' -> ' . $pivot_points[1]{label};

    $canvas->createText(
        $x2 - 8,
        $y2 - 10,
        -text   => $label_text,
        -fill   => $color,
        -font   => ['Arial', 8, 'bold'],
        -anchor => 'sw',
    );
}

1;
