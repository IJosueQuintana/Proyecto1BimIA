package Market::ML::TemporalStateLabeler;
use strict;
use warnings;
use List::Util qw(max min);

sub new { my ($class,%a)=@_; return bless { approach_atr=>$a{approach_atr}//1.0, expansion_return=>$a{expansion_return}//0.0015, target_horizon=>$a{target_horizon}//10, run_atr=>$a{run_atr}//1.0 },$class; }

sub label {
    my ($self,%args)=@_;
    my $rows=$args{rows}//[];
    my $candles=$args{candles}//[];
    my $atr=$args{atr}//[];

    for my $r (@$rows) {
        my $i=$r->{candle_index};
        my $near = _min_positive(
            $r->{distance_to_bsl_atr}, $r->{distance_to_ssl_atr},
            $r->{distance_fvg_atr}, $r->{distance_ob_atr}
        );

        $r->{state_label} = ($r->{inside_fvg} || $r->{inside_order_block}) ? 'INTERACTION'
            : (abs($r->{return_1}) >= $self->{expansion_return} && $r->{range_atr} >= 1) ? 'EXPANSION'
            : (defined($near) && $near <= $self->{approach_atr}) ? 'APPROACH'
            : 'IDLE';

        my ($event,$outcome)=('NONE','NONE');
        my $a=$atr->[$i]||0;
        my $end=min($#$candles,$i+$self->{target_horizon});

        if ($a>0 && $end>$i) {
            my $origin=$candles->[$i]{close};
            my $up_level=$origin + $self->{run_atr}*$a;
            my $down_level=$origin - $self->{run_atr}*$a;

            # Target causalmente separado: se observa el futuro únicamente
            # para etiquetar. Se asigna la dirección cuyo umbral se alcanza
            # primero. Si una misma vela atraviesa ambos umbrales, el orden
            # intravela es desconocido y se conserva NONE.
            for my $j ($i+1..$end) {
                my $hit_up   = $candles->[$j]{high} >= $up_level;
                my $hit_down = $candles->[$j]{low}  <= $down_level;
                if ($hit_up && $hit_down) { $outcome='NONE'; last; }
                if ($hit_up)   { $outcome='RUN_UP';   last; }
                if ($hit_down) { $outcome='RUN_DOWN'; last; }
            }

            if ($r->{state_label} eq 'INTERACTION' || (defined($near) && $near<=0.25)) {
                my ($took_high,$took_low)=(0,0);
                for my $j ($i+1..$end) {
                    $took_high ||= $candles->[$j]{high} > $candles->[$i]{high};
                    $took_low  ||= $candles->[$j]{low}  < $candles->[$i]{low};
                }
                $event = ($took_high && $took_low) ? 'SWEEP'
                       : ($took_high || $took_low)  ? 'GRAB'
                       : 'NONE';
            }
        }

        $r->{event_target}=$event;
        $r->{outcome_target}=$outcome;
    }
    return $rows;
}
sub _min_positive { my @v=grep{defined($_)&&$_>=0}@_; return @v?min(@v):undef; }
1;
