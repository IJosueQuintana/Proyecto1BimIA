package Market::Panels::ATRPanel;
use strict;
use warnings;
use lib ".";
use Market::Panels::Scales;

sub new { bless { scale => Market::Panels::Scales->new() }, shift }

sub draw {
    my ($self, $canvas, $atr, $x_of, $state) = @_;
    my $top = $state->{atr_top};
    my $h = $state->{atr_h};
    my $left = $state->{left};
    my $right = $state->{right};
    my $w = $state->{w};
    my $scale_w = $state->{scale_w};

    my ($min, $max);
    
    if ((!$state->{auto_y} || $state->{lock_y}) && defined $state->{atr_min} && defined $state->{atr_max}) {
        $min = $state->{atr_min};
        $max = $state->{atr_max};
    } else {
        ($min, $max) = _range_atr($atr);
        my $pad = ($max - $min) * 0.10 || 1;
        $min -= $pad;
        $max += $pad;

        $state->{atr_min} = $min;
        $state->{atr_max} = $max;
    }

    my $step = $self->{scale}->nice_step($max - $min, $h);
    my $first = int($min / $step) * $step;
    for (my $p = $first; $p <= $max + $step; $p += $step) {
        next if $p < $min;
        my $y = $self->{scale}->price_to_y($p, $min, $max, $top, $h);
        next if $y < $top + 14;
        next if $y > $top + $h - 14;


        
        $canvas->createLine($left, $y, $right, $y, -fill => '#eeeeee');
        $canvas->createText($w - $scale_w + 5, $y, -anchor => 'w', -text => sprintf('%.2f', $p), -fill => '#333');
    }

    my @pts;

for my $i (0 .. $#$atr) {
    next if !defined $atr->[$i];

    my $x = $x_of->($i);
    next if $x < $left || $x > $right;

    my $y = $self->{scale}->price_to_y($atr->[$i], $min, $max, $top, $h);

    # Si el ATR está fuera del panel manual, cortar la línea.
    # Así no queda una línea horizontal pegada arriba o abajo.
    if ($y < $top || $y > $top + $h) {
        $canvas->createLine(@pts, -fill => '#d62728', -width => 1.4) if @pts >= 4;
        @pts = ();
        next;
    }

    push @pts, ($x, $y);
}

$canvas->createLine(@pts, -fill => '#d62728', -width => 1.4) if @pts >= 4;

    my $value;

if (defined $state->{mouse_index}) {

    my $idx = $state->{mouse_index} - ($state->{start_index} // 0);

    if ($idx >= 0 && $idx <= $#$atr && defined $atr->[$idx]) {
        $value = $atr->[$idx];
    }
}

$value = _last_defined($atr) if !defined $value;



   my $label = defined $value? sprintf('ATR 14 RMA   %.2f', $value): 'ATR 14 RMA';
    $canvas->createText($left + 8, $top + 16, -anchor => 'w', -text => $label, -fill => '#d62728');
    #if (defined $value) {
    #    my $y = $self->{scale}->price_to_y($value, $min, $max, $top, $h);
    #    $canvas->createRectangle($right + 2, $y - 10, $w - 5, $y + 10, -fill => '#c62828', -outline => '#c62828');
    #    $canvas->createText($right + 8, $y, -anchor => 'w', -text => sprintf('%.2f', $value), -fill => 'white');
    #}
}

sub _clip_y {
    my ($y, $top, $bottom) = @_;
    return $top if $y < $top;
    return $bottom if $y > $bottom;
    return $y;
}
sub _range_atr_visible {
    my ($atr, $start, $end) = @_;

    my ($min, $max);

    $start = 0 if !defined($start) || $start < 0;
    $end = $#$atr if !defined($end) || $end > $#$atr;

    for my $i ($start .. $end) {
        next if !defined $atr->[$i];

        $min = $atr->[$i] if !defined($min) || $atr->[$i] < $min;
        $max = $atr->[$i] if !defined($max) || $atr->[$i] > $max;
    }

    $min = 0 if !defined $min;
    $max = 1 if !defined $max;

    return ($min, $max);
}

sub _range_atr {
    my ($atr) = @_;
    my ($min, $max);
    for my $v (@$atr) {
        next if !defined $v;
        $min = $v if !defined($min) || $v < $min;
        $max = $v if !defined($max) || $v > $max;
    }
    return ($min || 0, $max || 1);
}

sub _last_defined {
    my ($arr) = @_;
    for (my $i = $#$arr; $i >= 0; $i--) { return $arr->[$i] if defined $arr->[$i]; }
    return undef;
}

1;
