package Market::ML::SequentialDatasetBuilder;
use strict; use warnings; use File::Basename qw(basename); use Time::Piece;
use Market::MarketData; use Market::IndicatorManager; use Market::Indicators::ATR; use Market::Indicators::Liquidity; use Market::Indicators::SMC_Structures;
use Market::ML::SequentialFeatureExtractor; use Market::ML::TemporalStateLabeler; use Market::ML::SequentialFeatureSchema;
sub new { my ($class,%a)=@_; return bless {symbol=>$a{symbol}//'MARKET',timeframe=>$a{timeframe}//1,atr_period=>$a{atr_period}//14,atr_mult=>$a{atr_mult}//4,minor_atr_mult=>$a{minor_atr_mult}//1.5,confirm_bars=>$a{confirm_bars}//3,choch_atr_mult=>$a{choch_atr_mult}//2,target_horizon=>$a{target_horizon}//10},$class; }
sub build_file_dataset {
 my ($s,%a)=@_; my $file=$a{file} or die "Debe indicar file\n"; die "No existe '$file'\n" if !-f$file; my $m=Market::MarketData->new();
 open my $fh,'<',$file or die $!; <$fh>; while(<$fh>){chomp;next if/^\s*$/;my @x=split/,/;next if @x<6;my $t=$x[0];$t=~s/\.\d+//;my $clean=$t;$clean=~s/[-+]\d\d:\d\d$//;my $e=Time::Piece->strptime($clean,'%Y-%m-%dT%H:%M:%S')->epoch;$m->add_candle({time=>$t,epoch=>$e,open=>0+$x[1],high=>0+$x[2],low=>0+$x[3],close=>0+$x[4],volume=>0+$x[5]});} close$fh;
 $m->build_timeframes();$m->set_timeframe($s->{timeframe}); my $im=Market::IndicatorManager->new();$im->register('ATR',Market::Indicators::ATR->new(period=>$s->{atr_period}));$im->update_last($m);my $atr=$im->get('ATR');my $candles=$m->get_slice(0,$m->last_index());
 my $l=Market::Indicators::Liquidity->new(atr_mult=>$s->{atr_mult},minor_atr_mult=>$s->{minor_atr_mult},confirm_bars=>$s->{confirm_bars});my $lr=$l->calculate_until($candles,$atr,$m->last_index());my $smc=Market::Indicators::SMC_Structures->new(choch_atr_mult=>$s->{choch_atr_mult});my $sr=$smc->calculate($lr->{structural_pivots},$m);
 my $ex=Market::ML::SequentialFeatureExtractor->new(symbol=>$s->{symbol},timeframe=>$s->{timeframe});my $rows=$ex->extract(candles=>$candles,atr=>$atr,liquidity=>$lr->{liquidity},structure_events=>$sr->{events},fvg_levels=>$sr->{fvg},order_blocks=>$sr->{order_blocks});
 Market::ML::TemporalStateLabeler->new(target_horizon=>$s->{target_horizon})->label(rows=>$rows,candles=>$candles,atr=>$atr); my $date=basename($file);$date=($date=~/(\d{4})_(\d{2})_(\d{2})/)?"$1-$2-$3":'UNKNOWN';for(@$rows){$_->{dataset_date}=$date;$_->{source_file}=basename($file)}
 return {rows=>$rows,columns=>Market::ML::SequentialFeatureSchema->all_columns,candle_count=>$m->size(),source_file=>basename($file)};
}
1;
