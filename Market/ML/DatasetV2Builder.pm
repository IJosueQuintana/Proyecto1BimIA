package Market::ML::DatasetV2Builder;
use strict;
use warnings;
use File::Path qw(make_path);
use File::Spec;
use Scalar::Util qw(looks_like_number);

sub new {
    my ($class, %args) = @_;
    return bless { output_dir => $args{output_dir} // 'datasets/ml_pipeline/v2' }, $class;
}

sub build {
    my ($self, %args) = @_;
    my $train_file = $args{train_file} or die "Falta train_file\n";
    my $validation_file = $args{validation_file} or die "Falta validation_file\n";
    die "No existe TRAIN: $train_file\n" if !-f $train_file;
    die "No existe VALIDATION: $validation_file\n" if !-f $validation_file;
    make_path($self->{output_dir}) if !-d $self->{output_dir};

    my $train = _read_csv($train_file);
    my $validation = _read_csv($validation_file);
    _assert_same_schema($train->{headers}, $validation->{headers});

    my %available = map { $_ => 1 } @{$train->{headers}};
    my @metadata_candidates = qw(source_file file session dataset_split symbol timeframe pivot_id pivot_index confirmation_index pivot_timestamp confirmation_timestamp swept_index resolved_index target label class);
    my @categorical_candidates = qw(pivot_type pivot_label previous_pivot_type previous_pivot_label last_structure_event nearest_liquidity_type liquidity_side trend_state);
    my @numeric_candidates = qw(atr pivot_body_atr pivot_range_atr upper_wick_atr lower_wick_atr swing_size_atr distance_previous_pivot_atr distance_previous_pivot bars_previous_pivot distance_equal_level_atr bars_since_equal_level liquidity_imbalance_20 liquidity_imbalance_50 liquidity_imbalance_100 active_bsl_count active_ssl_count active_fvg_count_50 active_ob_count_50 distance_fvg_atr fvg_size_atr distance_ob_atr distance_last_structure_event_atr bars_since_structure_event confirm_displacement_atr price_change_from_previous_atr rejection_ratio penetration_atr volume_zscore volatility_20 return_1 return_5 slope_20);
    my @forbidden = qw(confirmation_delay structure_mode liquidity_state pivot_open pivot_high pivot_low pivot_close pivot_price confirm_open confirm_high confirm_low confirm_close previous_pivot_price near_equal_level inside_fvg fvg_mitigated inside_order_block ob_invalidated bos_count_previous_20 choch_count_previous_20);
    my %forbidden = map { $_ => 1 } @forbidden;

    my @metadata = grep { $available{$_} } @metadata_candidates;
    my @categorical = grep { $available{$_} && !$forbidden{$_} } @categorical_candidates;
    my @numeric = grep { $available{$_} && !$forbidden{$_} } @numeric_candidates;
    my %num = map { $_ => 1 } @numeric;
    @numeric = grep { $_ ne 'distance_previous_pivot' } @numeric if $num{distance_previous_pivot_atr};

    my @predictors = (@numeric, @categorical);
    die "No se encontraron suficientes features candidatas. Encontradas: " . scalar(@predictors) . "\n" if @predictors < 5;

    my (@output_headers, %seen);
    for my $name (@metadata, @predictors) {
        next if $seen{$name}++;
        push @output_headers, $name;
    }
    my $target_name = _find_target_name($train->{headers});
    if (defined $target_name && !$seen{$target_name}) {
        push @output_headers, $target_name;
        $seen{$target_name} = 1;
    }

    my ($train_rows, $duplicates) = _deduplicate_rows($train->{rows}, $train->{headers});
    my $validation_rows = [ @{$validation->{rows}} ];

    my $train_out = File::Spec->catfile($self->{output_dir}, 'train_v2.csv');
    my $validation_out = File::Spec->catfile($self->{output_dir}, 'validation_v2.csv');
    _write_csv($train_out, \@output_headers, $train_rows);
    _write_csv($validation_out, \@output_headers, $validation_rows);

    my $stats = _feature_quality(rows => $train_rows, numeric => \@numeric, categorical => \@categorical);
    my $report_file = File::Spec->catfile($self->{output_dir}, 'FEATURE_SELECTION_REPORT.md');
    _write_report(
        file => $report_file,
        train_rows_original => scalar(@{$train->{rows}}), train_rows_v2 => scalar(@$train_rows),
        validation_rows => scalar(@$validation_rows), duplicates_removed => scalar(@$duplicates),
        metadata => \@metadata, numeric => \@numeric, categorical => \@categorical,
        forbidden => \@forbidden,
        missing_candidates => [ grep { !$available{$_} } (@numeric_candidates, @categorical_candidates) ],
        stats => $stats,
    );

    my $features_file = File::Spec->catfile($self->{output_dir}, 'selected_features.txt');
    open my $ffh, '>:encoding(UTF-8)', $features_file or die "No se pudo escribir $features_file: $!\n";
    print {$ffh} "NUMERICAS\n", map { "$_\n" } @numeric;
    print {$ffh} "\nCATEGORICAS\n", map { "$_\n" } @categorical;
    close $ffh;

    my $duplicates_file = File::Spec->catfile($self->{output_dir}, 'removed_duplicate_rows.csv');
    if (@$duplicates) { _write_csv($duplicates_file, $train->{headers}, $duplicates); }
    else {
        open my $dfh, '>:encoding(UTF-8)', $duplicates_file or die "No se pudo escribir $duplicates_file: $!\n";
        print {$dfh} "status\nNO_DUPLICATES_REMOVED\n";
        close $dfh;
    }

    return {
        train_out => $train_out, validation_out => $validation_out, report_file => $report_file,
        features_file => $features_file, duplicates_file => $duplicates_file,
        train_rows_original => scalar(@{$train->{rows}}), train_rows_v2 => scalar(@$train_rows),
        validation_rows => scalar(@$validation_rows), duplicates_removed => scalar(@$duplicates),
        numeric_count => scalar(@numeric), categorical_count => scalar(@categorical), predictor_count => scalar(@predictors),
    };
}

sub _find_target_name { my ($h)=@_; my %x=map {$_=>1} @$h; for(qw(target label class)){return $_ if $x{$_}} return undef; }

sub _deduplicate_rows {
    my ($rows, $headers) = @_;
    my %available = map { $_ => 1 } @$headers;
    my @keys = grep { $available{$_} } qw(source_file file session symbol timeframe pivot_index confirmation_index);
    return ([ @$rows ], []) if !@keys;
    my (%seen, @clean, @dup);
    for my $row (@$rows) {
        my $key = join('|', map { defined $row->{$_} ? $row->{$_} : '' } @keys);
        $seen{$key}++ ? push(@dup,$row) : push(@clean,$row);
    }
    return (\@clean, \@dup);
}

sub _feature_quality {
    my (%args)=@_; my $rows=$args{rows}; my @items;
    for my $f (@{$args{numeric}}) {
        my @v = grep { defined $_ && $_ ne '' && looks_like_number($_) } map { $_->{$f} } @$rows;
        my $n=@v; my $missing=@$rows-$n; my ($mean,$sd,$min,$max)=('','','','');
        if($n){ my $sum=0; $sum+=$_ for @v; $mean=$sum/$n; my $sq=0; $sq+=($_-$mean)**2 for @v; $sd=$n>1?sqrt($sq/($n-1)):0; $min=$max=$v[0]; for(@v){$min=$_ if $_<$min;$max=$_ if $_>$max;} }
        push @items,{feature=>$f,type=>'numeric',non_missing=>$n,missing=>$missing,unique=>scalar(keys %{ {map {$_=>1} @v} }),mean=>$mean,sd=>$sd,min=>$min,max=>$max};
    }
    for my $f (@{$args{categorical}}) {
        my @v=grep {defined $_ && $_ ne ''} map {$_->{$f}} @$rows;
        push @items,{feature=>$f,type=>'categorical',non_missing=>scalar(@v),missing=>scalar(@$rows)-scalar(@v),unique=>scalar(keys %{ {map {$_=>1} @v} }),mean=>'',sd=>'',min=>'',max=>''};
    }
    return \@items;
}

sub _write_report {
    my (%a)=@_; open my $fh,'>:encoding(UTF-8)',$a{file} or die $!;
    print {$fh} "# Dataset V2 — selección controlada de features\n\nEste proceso usa exclusivamente TRAIN y VALIDATION. **TEST no se lee.**\n\n";
    print {$fh} "## Resumen\n\n- TRAIN original: **$a{train_rows_original}** filas\n- TRAIN V2: **$a{train_rows_v2}** filas\n- VALIDATION V2: **$a{validation_rows}** filas\n- Duplicados eliminados de TRAIN: **$a{duplicates_removed}**\n- Features numéricas: **".scalar(@{$a{numeric}})."**\n- Features categóricas: **".scalar(@{$a{categorical}})."**\n\n";
    print {$fh} "## Features numéricas\n\n", map {"- `$_`\n"} @{$a{numeric}};
    print {$fh} "\n## Features categóricas\n\n", map {"- `$_`\n"} @{$a{categorical}};
    print {$fh} "\n## Metadatos conservados solo para trazabilidad\n\n", map {"- `$_`\n"} @{$a{metadata}};
    print {$fh} "\n## Variables excluidas deliberadamente\n\n", map {"- `$_`\n"} @{$a{forbidden}};
    print {$fh} "\n## Candidatas no presentes\n\n";
    @{$a{missing_candidates}} ? print {$fh} map {"- `$_`\n"} @{$a{missing_candidates}} : print {$fh} "Todas estaban presentes.\n";
    print {$fh} "\n## Control estadístico básico\n\n| Feature | Tipo | No vacíos | Vacíos | Únicos | Media | Desv. estándar | Min | Max |\n|---|---:|---:|---:|---:|---:|---:|---:|---:|\n";
    for my $s (@{$a{stats}}) {
        my @v=map {defined $_?$_:''} @{$s}{qw(feature type non_missing missing unique mean sd min max)};
        for my $i (5..8){$v[$i]=sprintf('%.6f',$v[$i]) if $v[$i] ne '' && looks_like_number($v[$i]);}
        print {$fh} '| '.join(' | ',@v)." |\n";
    }
    print {$fh} "\n## Interpretación\n\nEl Dataset V2 reduce dimensionalidad y evita que precios absolutos, índices, timestamps o variables constantes dominen las distancias y las distribuciones gaussianas. No cambia RUN/GRAB/SWEEP.\n";
    close $fh;
}

sub _assert_same_schema { my($a,$b)=@_; die "TRAIN y VALIDATION no tienen el mismo encabezado\n" if join("\x1E",@$a) ne join("\x1E",@$b); }
sub _read_csv {
    my($file)=@_; open my $fh,'<:encoding(UTF-8)',$file or die $!; my $line=<$fh>; die "CSV vacío: $file\n" if !defined $line; chomp $line; $line=~s/\r$//; my @h=_parse_csv_line($line); my @rows;
    while(my $l=<$fh>){chomp$l;$l=~s/\r$//;next if $l eq '';my @v=_parse_csv_line($l);push @v,('')x(@h-@v) if @v<@h;$#v=$#h if @v>@h;my %r;@r{@h}=@v;push @rows,\%r;}
    close$fh; return {headers=>\@h,rows=>\@rows};
}
sub _write_csv { my($file,$h,$rows)=@_; open my $fh,'>:encoding(UTF-8)',$file or die $!; print {$fh} join(',',map{_csv_escape($_)}@$h),"\n"; for my $r(@$rows){print {$fh} join(',',map{_csv_escape(defined$r->{$_}?$r->{$_}:'')}@$h),"\n";} close$fh; }
sub _parse_csv_line { my($l)=@_;my(@f,$x);$x='';my$q=0;my@c=split//,$l;for(my$i=0;$i<@c;$i++){my$ch=$c[$i];if($q){if($ch eq '"'){if($i+1<@c&&$c[$i+1] eq '"'){$x.='"';$i++}else{$q=0}}else{$x.=$ch}}else{if($ch eq '"'){$q=1}elsif($ch eq ','){push@f,$x;$x=''}else{$x.=$ch}}}push@f,$x;return@f;}
sub _csv_escape { my($v)=@_;$v='' if !defined$v;$v=~s/"/""/g;return $v=~/[",\r\n]/?qq{"$v"}:$v; }
1;
