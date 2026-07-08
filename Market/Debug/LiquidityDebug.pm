package Market::Debug::LiquidityDebug;

use strict;
use warnings;

sub audit {

    my (%args) = @_;

    my $candles = $args{candles};
    my $level   = $args{level};

    return unless $candles;
    return unless $level;

    print "\n";
    print "=========================================\n";
    print "         LIQUIDITY AUDIT\n";
    print "=========================================\n";

    print "TYPE : $level->{type}\n";
    print "PRICE: $level->{price}\n";

    print "CREATED : $level->{created_index}\n";
    print "SWEPT   : ".($level->{swept_index}//'-')."\n";
    print "RESOLVED: ".($level->{resolved_index}//'-')."\n";

    print "STATE : $level->{state}\n";

    print "CLASS : ".($level->{classification}//'-')."\n";

    print "-----------------------------------------\n";

    my $center = defined $level->{swept_index}
    ? $level->{swept_index}
    : $level->{created_index};

my $from = $center - 5;
$from = 0 if $from < 0;

my $to = $center + 5;
$to = $#$candles if $to > $#$candles;

    for my $i ($from .. $to){

        my $c = $candles->[$i];

        my $mark = '';

        if($level->{type} eq 'BSL'){

            if($c->{high} > $level->{price}){
                $mark = '<-- HIGH BREAK';
            }

        }else{

            if($c->{low} < $level->{price}){
                $mark = '<-- LOW BREAK';
            }

        }

        printf(
            "%5d  O=%8.2f H=%8.2f L=%8.2f C=%8.2f %s\n",
            $i,
            $c->{open},
            $c->{high},
            $c->{low},
            $c->{close},
            $mark
        );
    }

    print "=========================================\n";
}

1;