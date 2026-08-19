package Market::ML::DatasetPipeline;

use strict;
use warnings;

use File::Basename qw(basename);
use Time::Piece;

use Market::MarketData;
use Market::IndicatorManager;
use Market::Indicators::ATR;
use Market::Indicators::Liquidity;
use Market::Indicators::SMC_Structures;
use Market::ML::PivotFeatureExtractor;
use Market::ML::DatasetExporter;
use Market::ML::DatasetValidator;

sub new {
    my ($class, %args) = @_;

    return bless {
        symbol          => $args{symbol}          // 'MARKET',
        timeframe       => $args{timeframe}       // 1,
        volume_lookback => $args{volume_lookback} // 20,
        atr_period      => $args{atr_period}      // 14,
        atr_mult        => $args{atr_mult}        // 4.0,
        minor_atr_mult  => $args{minor_atr_mult}  // 1.5,
        confirm_bars    => $args{confirm_bars}    // 3,
        choch_atr_mult  => $args{choch_atr_mult}  // 2.0,
    }, $class;
}

sub build_file_dataset {
    my ($self, %args) = @_;

    my $file = $args{file};
    die "Debe indicar file\n" if !defined $file || $file eq '';
    die "No existe el archivo '$file'\n" if !-f $file;

    my $dataset_date = $args{dataset_date} // _date_from_filename($file);
    my $source_file  = basename($file);

    my $raw = _load_csv_rows($file);
    my $market = Market::MarketData->new();

    for my $row (@$raw) {
        next if ref($row) ne 'ARRAY' || @$row < 6;

        my $time = $row->[0];
        next if !defined $time || $time eq '';

        $time =~ s/\.\d+//;
        my $clean = $time;
        $clean =~ s/[-+]\d\d:\d\d$//;

        my $epoch = Time::Piece->strptime(
            $clean,
            '%Y-%m-%dT%H:%M:%S'
        )->epoch;

        $market->add_candle({
            time   => $time,
            epoch  => $epoch,
            open   => $row->[1] + 0,
            high   => $row->[2] + 0,
            low    => $row->[3] + 0,
            close  => $row->[4] + 0,
            volume => $row->[5] + 0,
        });
    }

    $market->build_timeframes();
    $market->set_timeframe($self->{timeframe});

    my $indicators = Market::IndicatorManager->new();
    $indicators->register(
        'ATR',
        Market::Indicators::ATR->new(period => $self->{atr_period})
    );
    $indicators->update_last($market);
    my $atr_values = $indicators->get('ATR');

    my $liquidity = Market::Indicators::Liquidity->new(
        atr_mult       => $self->{atr_mult},
        minor_atr_mult => $self->{minor_atr_mult},
        confirm_bars   => $self->{confirm_bars},
    );

    my $liq_result = $liquidity->calculate_until(
        $market->get_slice(0, $market->last_index()),
        $atr_values,
        $market->last_index(),
    );

    my $smc = Market::Indicators::SMC_Structures->new(
        choch_atr_mult => $self->{choch_atr_mult},
    );

    my $smc_result = $smc->calculate(
        $liq_result->{structural_pivots},
        $market,
    );

    my $extractor = Market::ML::PivotFeatureExtractor->new(
        volume_lookback => $self->{volume_lookback},
        symbol          => $self->{symbol},
        timeframe       => $self->{timeframe},
    );

    my $rows = $extractor->extract(
        candles          => $market->get_slice(0, $market->last_index()),
        pivots            => $smc_result->{structure},
        atr               => $atr_values,
        liquidity         => $liq_result->{liquidity},
        structure_events  => $smc_result->{events},
        equal_levels      => $liq_result->{equal_levels},
        fvg_levels        => $smc_result->{fvg},
        order_blocks      => $smc_result->{order_blocks},
        symbol            => $self->{symbol},
        timeframe         => $self->{timeframe},
    );

    for my $row (@$rows) {
        $row->{dataset_date} = $dataset_date;
        $row->{source_file}  = $source_file;
    }

    my $exporter = Market::ML::DatasetExporter->new();
    my $trainable = $exporter->filter_trainable_rows(rows => $rows);

    my $validator = Market::ML::DatasetValidator->new(verbose => 0);
    my $validation = $validator->validate(rows => $rows);

    return {
        file          => $file,
        source_file   => $source_file,
        dataset_date  => $dataset_date,
        candle_count  => $market->size(),
        rows          => $rows,
        trainable     => $trainable,
        columns       => [ 'dataset_date', 'source_file', @{$extractor->feature_names()} ],
        validation    => $validation,
    };
}

sub _load_csv_rows {
    my ($file) = @_;

    open my $fh, '<:encoding(UTF-8)', $file
        or die "No se puede abrir '$file': $!\n";

    my $header = <$fh>;
    my @rows;

    while (my $line = <$fh>) {
        chomp $line;
        $line =~ s/\r$//;
        next if $line =~ /^\s*$/;

        my @fields = _parse_csv_line($line);
        next if @fields < 6;
        push @rows, \@fields;
    }

    close $fh;
    return \@rows;
}

sub _parse_csv_line {
    my ($line) = @_;
    my @fields;
    my $field = '';
    my $quoted = 0;

    for (my $i = 0; $i < length($line); $i++) {
        my $char = substr($line, $i, 1);

        if ($char eq '"') {
            if ($quoted && $i + 1 < length($line) && substr($line, $i + 1, 1) eq '"') {
                $field .= '"';
                $i++;
            } else {
                $quoted = !$quoted;
            }
        } elsif ($char eq ',' && !$quoted) {
            push @fields, $field;
            $field = '';
        } else {
            $field .= $char;
        }
    }

    push @fields, $field;
    return @fields;
}

sub _date_from_filename {
    my ($file) = @_;
    my $name = basename($file);
    return "$1-$2-$3" if $name =~ /(\d{4})_(\d{2})_(\d{2})/;
    return "$1-$2" if $name =~ /(\d{4})_(\d{2})/;
    return 'UNKNOWN';
}

1;
