package Market::Panels::PricePanel;
use strict;
use warnings;
use lib ".";
use Market::Panels::Scales;

sub new {
    my ($class) = @_;
    bless { scale => Market::Panels::Scales->new() }, $class;
}

sub draw {
    my ($self, $canvas, $data, $x_of, $state) = @_;
    my $left = $state->{left};
    my $right = $state->{right};
    my $top = $state->{top};
    my $height = $state->{price_h};
    my $bar_w = $state->{bar_w};
    my $scale_w = $state->{scale_w};
    my $w = $state->{w};

    my ($min, $max);
    
    if ((!$state->{auto_y} || $state->{lock_y}) && defined $state->{price_min} && defined $state->{price_max}) {
        $min = $state->{price_min};
        $max = $state->{price_max};
    } else {
        ($min, $max) = _range_price($data);
        my $pad = ($max - $min) * 0.08 || 1;
        $min -= $pad;
        $max += $pad;

        $state->{price_min} = $min;
        $state->{price_max} = $max;
    }

    _grid_price($canvas, $self->{scale}, $min, $max, $top, $height, $left, $right, $w, $scale_w);

    for my $i (0 .. $#$data) {
        my $c = $data->[$i];
        my $x = $x_of->($i);
        next if $x < $left - $bar_w || $x > $right + $bar_w;

        my $yo = $self->{scale}->price_to_y($c->{open},  $min, $max, $top, $height);
        my $yh = $self->{scale}->price_to_y($c->{high},  $min, $max, $top, $height);
        my $yl = $self->{scale}->price_to_y($c->{low},   $min, $max, $top, $height);
        my $yc = $self->{scale}->price_to_y($c->{close}, $min, $max, $top, $height);
        my $color = ($c->{close} >= $c->{open}) ? '#089981' : '#f23645';

        my $bottom = $top + $height;

        next if $c->{low}  > $max;
        next if $c->{high} < $min;

        $yo = _clip_y($yo, $top, $bottom);
        $yh = _clip_y($yh, $top, $bottom);
        $yl = _clip_y($yl, $top, $bottom);
        $yc = _clip_y($yc, $top, $bottom);




        my $body_top = $yo < $yc ? $yo : $yc;
        my $body_bot = $yo > $yc ? $yo : $yc;
        $body_bot = $body_top + 1 if $body_bot - $body_top < 1;

        my $x_left  = $x - $bar_w / 2;
        my $x_right = $x + $bar_w / 2;

        $x_left  = $left  + 1 if $x_left  < $left + 1;
        $x_right = $right - 3 if $x_right > $right - 3;

        next if $x_right <= $x_left;

        my $wick_x = int(($x_left + $x_right) / 2);

        # Cuerpo primero
        $canvas->createRectangle($x_left, $body_top, $x_right, $body_bot,
            -fill => $color, -outline => $color);

        # Mecha superior: solo desde high hasta el cuerpo
        if ($yh < $body_top) {
            $canvas->createLine($wick_x, $yh, $wick_x, $body_top, -fill => $color);
        }

        # Mecha inferior: solo desde el cuerpo hasta low
        if ($yl > $body_bot) {
            $canvas->createLine($wick_x, $body_bot, $wick_x, $yl, -fill => $color);
        }

    }

    _draw_volume($canvas, $data, $x_of, $state);
    _header($canvas, $data, $state);




}

sub _clip_y {
    my ($y, $top, $bottom) = @_;
    return $top if $y < $top;
    return $bottom if $y > $bottom;
    return $y;
}

sub _range_price {
    my ($data) = @_;
    my ($min, $max);
    for my $c (@$data) {
        $min = $c->{low}  if !defined($min) || $c->{low}  < $min;
        $max = $c->{high} if !defined($max) || $c->{high} > $max;
    }
    return ($min || 0, $max || 1);
}

sub _grid_price {
    my ($canvas, $scale, $min, $max, $top, $height, $left, $right, $w, $scale_w) = @_;
    my $step = $scale->nice_step($max - $min, $height);

    # Para NQ los precios deben respetar tick de 0.25.
    $step = 0.25 if $step < 0.25;
    $step = int($step / 0.25 + 0.999999) * 0.25;
    my $first = int($min / $step) * $step;
    for (my $p = $first; $p <= $max + $step; $p += $step) {
        next if $p < $min;
        my $y = $scale->price_to_y($p, $min, $max, $top, $height);
        $canvas->createLine($left, $y, $right, $y, -fill => '#eeeeee');
        $canvas->createText($w - $scale_w + 5, $y, -anchor => 'w', -text => sprintf('%.2f', $p), -fill => '#222');
    }
    $canvas->createLine($right, $top, $right, $top + $height, -fill => '#dddddd');
}

sub _draw_volume {
    my ($canvas, $data, $x_of, $state) = @_;
    my $top = $state->{top} + $state->{price_h} - $state->{vol_h};
    my $h = $state->{vol_h};
    my $bar_w = $state->{bar_w};
    my $maxv = 1;
    for my $c (@$data) { $maxv = $c->{volume} if $c->{volume} > $maxv; }
    for my $i (0 .. $#$data) {
        my $c = $data->[$i];
        my $x = $x_of->($i);
        my $vh = ($c->{volume} / $maxv) * $h;
        my $color = ($c->{close} >= $c->{open}) ? '#8dd3c7' : '#fb9a99';
        $canvas->createRectangle($x - $bar_w/2, $top + $h - $vh, $x + $bar_w/2, $top + $h,
            -fill => $color, -outline => $color);
    }
    my $lastv = @$data ? $data->[-1]{volume} : 0;
    $canvas->createText($state->{left} + 8, $top + 15, -anchor => 'w', -text => 'Vol. ' . _fmt_k($lastv), -fill => '#333');
}

sub _fmt_k {
    my ($v) = @_;
    return sprintf('%.2f K', $v / 1000) if $v >= 1000;
    return $v;
}

sub _header {
    my ($canvas, $data, $state) = @_;
    return if !@$data;
    my $c = $data->[-1];
    my $chg = $c->{close} - $c->{open};
    my $color = $chg >= 0 ? '#089981' : '#f23645';
    #my $txt = sprintf('Futuros NASDAQ 100 E-mini · %dm · CME   O %.2f  H %.2f  L %.2f  C %.2f  %+0.2f',
    #    $state->{tf}, $c->{open}, $c->{high}, $c->{low}, $c->{close}, $chg);
    #$canvas->createText($state->{left} + 8, 15, -anchor => 'w', -text => $txt, -fill => $color,
    #    -font => ['Arial', 11, 'bold']);
}

1;
