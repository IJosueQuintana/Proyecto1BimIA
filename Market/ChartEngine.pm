package Market::ChartEngine;
use strict;
use warnings;
use Tk;
use lib '.';
use Time::Local;
use POSIX qw(floor ceil);
use Market::Panels::PricePanel;
use Market::Panels::ATRPanel;
use Market::Overlays::SMC_Structures;
use Market::Indicators::Liquidity;
use Market::Indicators::SMC_Structures;
use Market::Overlays::Liquidity;

sub new {
    my ($class, %args) = @_;

    my $self = {
        market     => $args{market},
        indicators => $args{indicators},
        mw         => $args{mw},
        canvas     => undef,

        tf      => 1,
        visible => 160,
        first   => 0,

        left     => 4,
        scale_w  => 92,
        bottom_h => 30,
        atr_h    => 170,
        vol_h    => 82,

        auto_y          => 1,
        lock_y_on_zoom  => 0,
        price_min       => 0,
        price_max       => 1,
        locked_index    => undef,
        mouse_index     => undef,
        atr_min         => undef,
        atr_max         => undef,
        drag            => undef,
        resize_atr      => 0,

        debug_scroll => 0,
        wheel_count  => 0,

       show_external_zigzag => 0,
        show_internal_zigzag => 0,
        show_bos   => 0,
        show_choch => 0,


       layers_panel_visible => 0,
        layers_panel         => undef,

        layers => {
    internal => {
        zigzag => 0, labels => 0, bos => 0, choch => 0,
        bsl => 0, ssl => 0, eqh => 0, eql => 0,
        liquidity_events => 0,
        fvg => 0,
        order_blocks => 0,
    },
    external => {
        zigzag => 0, labels => 0, bos => 0, choch => 0,
        bsl => 0, ssl => 0, eqh => 0, eql => 0,
        liquidity_events => 0,
        fvg => 0,
        order_blocks => 0,
    },
},

        show_external_labels => 0,
        show_internal_labels => 0,

        

        show_bsl => 0,
        show_ssl => 0,
        show_eqh => 0,
        show_eql => 0,

        show_fvg          => 0,
        show_order_blocks => 0,


        show_volume_pivots => 0,

        price_panel => Market::Panels::PricePanel->new(),
        atr_panel   => Market::Panels::ATRPanel->new(),

                internal_zigzag_tf  => 60,
        internal_zigzag_prd => 2,
        external_swing_len  => 150,

        liquidity_engine => Market::Indicators::Liquidity->new(
            atr_mult             => 4.0,
            minor_atr_mult       => 1.5,
            confirm_bars         => 3,
            internal_zigzag_tf   => 60,
            internal_zigzag_prd  => 2,
            external_swing_len   => 150,
        ),

        smc_external_engine => Market::Indicators::SMC_Structures->new(
            prefix => '',
            mode   => 'external',
        ),

        smc_internal_engine => Market::Indicators::SMC_Structures->new(
            prefix => 'i',
            mode   => 'internal',
        ),

        smc_overlay => Market::Overlays::SMC_Structures->new(
            smc_result => undef,
        ),

        liquidity_overlay => Market::Overlays::Liquidity->new(
            liq_result => undef,
        ),

        smc_cache_key     => undef,
        last_liq_result   => undef,
        last_smc_result   => undef,
        last_smc_external => undef,
        last_smc_internal => undef,

        replay_mode      => 0,
        replay_selecting => 0,
        replay_index     => undef,
        replay_after     => undef,
        replay_speed => 300,
        debug_replay => 0,

        audit_printed => 0,
    };

    bless $self, $class;
    return $self;
}

sub run {
    my ($self) = @_;
    my $mw = $self->{mw};

    $mw->title('TradingView IA Grupo 3');
    $mw->geometry('1400x800');
    $mw->minsize(900, 500);
    $mw->resizable(1, 1);
    $mw->geometry($mw->screenwidth . "x" . ($mw->screenheight - 80) . "+0+0");

    my $top = $mw->Frame()->pack(-side => 'top', -fill => 'x');
    $self->{top_bar} = $top;

    my @timeframes = (
        ['1m',  1],
        ['5m',  5],
        ['15m', 15],
        ['1h',  60],
        ['2h',  120],
        ['4h',  240],
        ['D',   'D'],
        ['W',   'W'],
    );

        $self->{internal_zigzag_tf_label} //= '1 hora';
    $self->{internal_zigzag_tf}       //= 60;

    my $selected_tf_label = '1m';

    my $tf_display = $top->Button(
        -text  => "Temporalidad: $selected_tf_label",
        -width => 18,
    )->pack(-side => 'left', -padx => 4);

    my $tf_popup = $mw->Toplevel();
    $tf_popup->withdraw();
    $tf_popup->overrideredirect(1);

    my $tf_list = $tf_popup->Listbox(
        -height          => 8,
        -width           => 12,
        -exportselection => 0,
    )->pack(-side => 'left');

    my $tf_scroll = $tf_popup->Scrollbar(
        -orient  => 'vertical',
        -command => ['yview', $tf_list],
    )->pack(-side => 'right', -fill => 'y');

    $tf_list->configure(
        -yscrollcommand => ['set', $tf_scroll]
    );

    for my $item (@timeframes) {
        $tf_list->insert('end', $item->[0]);
    }

    $tf_display->configure(
        -command => sub {
            if ($tf_popup->state eq 'withdrawn') {
                my $x = $tf_display->rootx;
                my $y = $tf_display->rooty + $tf_display->height;
                $tf_popup->geometry("+$x+$y");
                $tf_popup->deiconify();
                $tf_popup->raise();
            } else {
                $tf_popup->withdraw();
            }
        }
    );

    $tf_list->bind('<<ListboxSelect>>' => sub {
        my @sel = $tf_list->curselection;
        return if !@sel;

        my $pos = $sel[0];
        my ($label, $tf) = @{$timeframes[$pos]};

        $selected_tf_label = $label;
        $tf_display->configure(-text => "Temporalidad: $label ");

        $tf_popup->withdraw();

        $self->set_timeframe($tf);
        $self->{smc_cache_key} = undef;

        $self->fit_all();
        $self->draw();
    });

    
    my $layers_display = $top->Button(
        -text  => 'Layers',
        -width => 10,
    )->pack(-side => 'left', -padx => 4);

    $self->{layers_button} = $layers_display;

    $self->{layers_popup} = $mw->Toplevel();
    $self->{layers_popup}->withdraw();
    $self->{layers_popup}->overrideredirect(1);

    $self->_build_layers_popup();

    $layers_display->configure(
        -command => sub {
            if ($self->{layers_popup}->state eq 'withdrawn') {
                my $x = $layers_display->rootx;
                my $y = $layers_display->rooty + $layers_display->height;
                $self->{layers_popup}->geometry("+$x+$y");
                $self->{layers_popup}->deiconify();
                $self->{layers_popup}->raise();
            } else {
                $self->{layers_popup}->withdraw();
            }
        }
    );

        # ==============================
    # Selector de temporalidad ZZ Interno
    # ==============================

    my @zz_internal_timeframes = (
        ['3 minutos',  3],
        ['5 minutos',  5],
        ['10 minutos', 10],
        ['15 minutos', 15],
        ['30 minutos', 30],
        ['45 minutos', 45],
        ['1 hora',     60],
        ['2 horas',    120],
        ['3 horas',    180],
        ['4 horas',    240],
        ['1 día',      'D'],
        ['1 semana',   'W'],
    );

    $self->{internal_zigzag_tf_label} //= '1 hora';
    $self->{internal_zigzag_tf}       //= 60;

    my $zz_selected_label = $self->{internal_zigzag_tf_label};

    my $zz_tf_display = $top->Button(
        -text  => "ZZ Interno: $zz_selected_label",
        -width => 20,
    )->pack(-side => 'left', -padx => 4);

    my $zz_tf_popup = $mw->Toplevel();
    $zz_tf_popup->withdraw();
    $zz_tf_popup->overrideredirect(1);

    my $zz_tf_list = $zz_tf_popup->Listbox(
        -height          => 10,
        -width           => 14,
        -exportselection => 0,
    )->pack(-side => 'left');

    my $zz_tf_scroll = $zz_tf_popup->Scrollbar(
        -orient  => 'vertical',
        -command => ['yview', $zz_tf_list],
    )->pack(-side => 'right', -fill => 'y');

    $zz_tf_list->configure(
        -yscrollcommand => ['set', $zz_tf_scroll]
    );

    for my $item (@zz_internal_timeframes) {
        $zz_tf_list->insert('end', $item->[0]);
    }

    $zz_tf_display->configure(
        -command => sub {
            if ($zz_tf_popup->state eq 'withdrawn') {
                my $x = $zz_tf_display->rootx;
                my $y = $zz_tf_display->rooty + $zz_tf_display->height;
                $zz_tf_popup->geometry("+$x+$y");
                $zz_tf_popup->deiconify();
                $zz_tf_popup->raise();
            } else {
                $zz_tf_popup->withdraw();
            }
        }
    );

    $zz_tf_list->bind('<<ListboxSelect>>' => sub {
        my @sel = $zz_tf_list->curselection;
        return if !@sel;

        my $pos = $sel[0];
        my ($label, $tf) = @{$zz_internal_timeframes[$pos]};

        $self->{internal_zigzag_tf_label} = $label;
        $self->{internal_zigzag_tf}       = $tf;

        $zz_tf_display->configure(
            -text => "ZZ Interno: $label"
        );

        $zz_tf_popup->withdraw();

        if ($self->{liquidity_engine}) {
            $self->{liquidity_engine}->{internal_zigzag_tf} = $tf;
        }

        $self->{smc_cache_key} = undef;
        $self->draw();
    });


    $top->Checkbutton(
        -text     => 'Auto vertical',
        -variable => \$self->{auto_y},
        -command  => sub {
            $self->{lock_y_on_zoom} = 0;
            $self->draw;
        }
    )->pack(-side => 'left');

    $top->Button(
        -text    => 'Start',
        -command => sub { $self->go_to_start(); }
    )->pack(-side => 'left');

    $top->Button(
        -text    => 'End',
        -command => sub { $self->go_to_end(); }
    )->pack(-side => 'left');

    $top->Button(
    -text    => 'Replay',
    -command => sub { $self->replay_select_start(); }
    )->pack(-side => 'left');

    $top->Button(
    -text    => 'Play',
    -command => sub { $self->replay_play(); }
    )->pack(-side => 'left');

    $top->Button(
    -text    => 'Pause',
    -command => sub { $self->replay_pause(); }
    )->pack(-side => 'left');

    $top->Button(
    -text    => 'Step +',
    -command => sub { $self->replay_step(1); }
    )->pack(-side => 'left');

    $top->Button(
    -text    => 'Step -',
    -command => sub { $self->replay_step(-1); }
    )->pack(-side => 'left');

    $top->Button(
    -text    => 'Exit Replay',
    -command => sub { $self->replay_exit(); }
    )->pack(-side => 'left');



    $top->Button(
    -text    => 'VOL',
    -command => sub {
        $self->{show_volume_pivots} = !$self->{show_volume_pivots};
        $self->draw();
    }
    )->pack(-side => 'left');


    $top->Checkbutton(
    -text     => 'FVG',
    -variable => \$self->{show_fvg},
    -command  => sub { $self->draw(); }
    )->pack(-side => 'left');

    $top->Checkbutton(
    -text     => 'Order Blocks',
    -variable => \$self->{show_order_blocks},
    -command  => sub { $self->draw(); }
    )->pack(-side => 'left');







    my $canvas = $mw->Canvas(
        -background         => 'white',
        -highlightthickness => 0
    )->pack(-fill => 'both', -expand => 1);

    $canvas->configure(-cursor => 'crosshair');
    $self->{canvas} = $canvas;

    $canvas->bindtags([$canvas]);

    my $configured_once = 0;

    $canvas->Tk::bind('<Configure>' => sub {
        if (!$configured_once) {
            $configured_once = 1;
            $self->fit_all();
        }
        $self->draw();
    });

    $canvas->Tk::bind('<Motion>' => [
        sub {
            my ($w, $x, $y, $s) = @_;
            $self->mouse_move($x, $y, $s);
        },
        Tk::Ev('x'), Tk::Ev('y'), Tk::Ev('s')
    ]);

    $canvas->Tk::bind('<ButtonPress-1>' => [
        sub {
            my ($w, $x, $y) = @_;
            $self->mouse_down($x, $y);
        },
        Tk::Ev('x'), Tk::Ev('y')
    ]);

    $canvas->Tk::bind('<B1-Motion>' => [
        sub {
            my ($w, $x, $y) = @_;
            $self->mouse_drag($x, $y);
        },
        Tk::Ev('x'), Tk::Ev('y')
    ]);

    $canvas->Tk::bind('<ButtonRelease-1>' => [
        sub {
            my ($w, $x, $y) = @_;
            $self->mouse_up($x, $y);
        },
        Tk::Ev('x'), Tk::Ev('y')
    ]);

    $canvas->Tk::bind('<Button-4>' => [
        sub {
            my ($w, $x, $y, $s) = @_;
            $self->mouse_wheel(120, $x, $y, $s);
            return "break";
        },
        Tk::Ev('x'), Tk::Ev('y'), Tk::Ev('s')
    ]);

    $canvas->Tk::bind('<Button-5>' => [
        sub {
            my ($w, $x, $y, $s) = @_;
            $self->mouse_wheel(-120, $x, $y, $s);
            return "break";
        },
        Tk::Ev('x'), Tk::Ev('y'), Tk::Ev('s')
    ]);

    $canvas->Tk::bind('<MouseWheel>' => [
        sub {
            my ($w, $delta, $x, $y, $s) = @_;
            $self->mouse_wheel($delta, $x, $y, $s);
            return "break";
        },
        Tk::Ev('D'), Tk::Ev('x'), Tk::Ev('y'), Tk::Ev('s')
    ]);

    $mw->Tk::bind('<plus>'  => sub { $self->mouse_wheel(120); });
    $mw->Tk::bind('<minus>' => sub { $self->mouse_wheel(-120); });
    $mw->Tk::bind('<Escape>' => sub { $mw->destroy; });

    $self->fit_all();
    $self->draw();

    MainLoop;
}





sub set_timeframe {
    my ($self, $tf) = @_;
    $self->{tf} = $tf;
    $self->{market}->set_timeframe($tf);
    if ($self->{replay_mode}) {
    my $last = $self->{market}->last_index();
    $self->{replay_index} = $last if $self->{replay_index} > $last;
    $self->_replay_apply_window();
}
    $self->{smc_cache_key} = undef;
    $self->{indicators}->reset_all();
    $self->{indicators}->update_last($self->{market});
    $self->{locked_index} = undef;
    $self->{lock_y_on_zoom} = 0;
    $self->fit_all();
    $self->draw();
}

sub fit_all {
    my ($self) = @_;
    my $n = $self->{market}->size();
    return if $n <= 0;

    $self->{visible} = 180;
    $self->{visible} = $n + 4 if $n < 180;

    $self->{first} = $n - $self->{visible} + 2;
    $self->limit_first();
}

sub layout {
    my ($self) = @_;
    my $c = $self->{canvas};
    my $w = $c->width  || 1200;
    my $h = $c->height || 700;
    my $right = $w - $self->{scale_w};
    # Los paneles siempre quedan fijos: precio arriba y ATR abajo.
    # El zoom horizontal no debe cambiar estas posiciones.
    $self->{atr_h} = 80  if $self->{atr_h} < 80;
    $self->{atr_h} = 320 if $self->{atr_h} > 320;
    my $atr_top = $h - $self->{bottom_h} - $self->{atr_h};
    $atr_top = 120 if $atr_top < 120;
    my $price_h = $atr_top;
    my $plot_w = $right - $self->{left};
    
    my $step = $plot_w / $self->{visible};  
    my $bar_w = $step * 0.92;

    $bar_w = 1 if $bar_w < 1;
    $bar_w = 800 if $bar_w > 800;


    return ($w, $h, $right, $atr_top, $price_h, $plot_w, $bar_w);
}


sub update_smc_overlay {
    my ($self, $until_index) = @_;

    return if !defined $until_index;

    my $market     = $self->{market};
    my $indicators = $self->{indicators};

    my $tf = $market->{timeframe} // 1;

    my %tf_atr_mult = (
        1   => 4.0,
        5   => 4.0,
        15  => 4.0,
        60  => 3.0,
        120 => 2.8,
        240 => 2.5,
        D   => 2.0,
        W   => 1.5,
    );

    my %tf_minor_mult = (
        1   => 1.5,
        5   => 1.5,
        15  => 1.5,
        60  => 1.2,
        120 => 1.1,
        240 => 1.0,
        D   => 0.8,
        W   => 0.6,
    );

        $self->{liquidity_engine}->{atr_mult} =
        $tf_atr_mult{$tf} // 4.0;

    $self->{liquidity_engine}->{minor_atr_mult} =
        $tf_minor_mult{$tf} // 1.5;

    $self->{liquidity_engine}->{internal_zigzag_tf} =
        $self->{internal_zigzag_tf} // 60;

    $self->{liquidity_engine}->{internal_zigzag_prd} =
        $self->{internal_zigzag_prd} // 2;

    $self->{liquidity_engine}->{external_swing_len} =
        $self->{external_swing_len} // 150;

    my $cache_key = join(
        ':',
        $tf,
        $until_index,
        $self->{internal_zigzag_tf} // 60,
        $self->{internal_zigzag_prd} // 2,
        $self->{external_swing_len} // 150,
    );

    return if defined $self->{smc_cache_key}
        && $self->{smc_cache_key} eq $cache_key;

    $indicators->update_until($market, $until_index);

    my $atr_values = $indicators->get('ATR');

    my $liq_result = $self->{liquidity_engine}->calculate_until(
        $market->get_slice(0, $until_index),
        $atr_values,
        $until_index
    );

    my $smc_external = $self->{smc_external_engine}->calculate(
    $liq_result->{external_structure},
    $market
    );

    my $smc_internal = $self->{smc_internal_engine}->calculate(
    $liq_result->{internal_structure},
    $market
    );

    $self->{last_liq_result}   = $liq_result;
    $self->{last_smc_external} = $smc_external;
    $self->{last_smc_internal} = $smc_internal;
    $self->_print_audit_summary($liq_result, $smc_external, $smc_internal, $market);

    # Se mantiene por compatibilidad con auditoría y ML.
    # Para ML seguimos usando estructura externa.
    $self->{last_smc_result} = $smc_external;

    $self->{liquidity_overlay}->set_result($liq_result);
    $self->{smc_overlay}->set_result($smc_external);

    $self->{smc_cache_key} = $cache_key;
}

sub draw {
    my ($self) = @_;
    my $c = $self->{canvas};
    return if !$c;
    $c->delete('all');

    

    my ($w, $h, $right, $atr_top, $price_h, $plot_w, $bar_w) = $self->layout();

    

    my $last = $self->{market}->last_index();

    my $effective_last = $self->{replay_mode}
    ? $self->{replay_index}
    : $last;

    my $start = floor($self->{first});
    my $end = ceil($self->{first} + $self->{visible} - 1);
    
    


    $start = 0 if $start < 0;
    $end = $effective_last if $end > $effective_last;

    my $data = $self->{market}->get_slice($start, $end);
    my $atr = $self->{indicators}->slice_array('ATR', $start, $end);



    

    my $step = $plot_w / $self->{visible};

    my $x_of = sub {
        my ($local_i) = @_;
        my $global_i = $start + $local_i;

        return $self->{left}
            + ($step / 2)
            + ($global_i - $self->{first}) * $step;
    };

    my %state = (
        w => $w, h => $h, left => $self->{left}, right => $right, scale_w => $self->{scale_w},
        top => 0, price_h => $price_h, atr_top => $atr_top, atr_h => $self->{atr_h},
        vol_h => $self->{vol_h}, bar_w => $bar_w, auto_y => $self->{auto_y},
        lock_y => $self->{lock_y_on_zoom},
        price_min => $self->{price_min}, price_max => $self->{price_max}, tf => $self->{tf},
        atr_min => $self->{atr_min},
        atr_max => $self->{atr_max},    
        start_index => $start,
        end_index   => $end,
        mouse_index => $self->{mouse_index},
    );

    $self->draw_time_axis($start, $end, $x_of, $right, $h);
    $self->{price_panel}->draw($c, $data, $x_of, \%state);
    $self->{price_min} = $state{price_min};
    $self->{price_max} = $state{price_max};

my $plot_top    = $state{top};
my $plot_bottom = $state{price_h};

my $y_of = sub {
    my ($price) = @_;

    return $plot_bottom if $state{price_max} == $state{price_min};

    return $plot_bottom
        - (($price - $state{price_min}) / ($state{price_max} - $state{price_min}))
        * ($plot_bottom - $plot_top);
};

$state{y_of} = $y_of;

    
    #use Data::Dump qw(dump);

#print dump(\%state);
    

    my $calc_until = $self->{replay_mode}
    ? $self->{replay_index}
    : $self->{market}->last_index();

my $needs_smc_or_liquidity =
       $self->{show_external_zigzag}
    || $self->{show_external_labels}
    || $self->{show_internal_zigzag}
    || $self->{show_internal_labels}
    || $self->{layers}{external}{bos}
    || $self->{layers}{external}{choch}
    || $self->{layers}{internal}{bos}
    || $self->{layers}{internal}{choch}
    || $self->{show_bsl}
    || $self->{show_ssl}
    || $self->{show_eqh}
    || $self->{show_eql}
    || $self->{show_volume_pivots};

$self->update_smc_overlay($calc_until) if $needs_smc_or_liquidity;

    if ($self->{show_external_zigzag} || $self->{show_external_labels}) {
    $self->{smc_overlay}->draw(
        $c,
        $start,
        $end,
        $x_of,
        \%state,
        $self->{price_panel},
        result      => $self->{last_smc_external},
        style       => 'external',
        show_zigzag => $self->{show_external_zigzag},
        show_labels => $self->{show_external_labels},
    );
    }

    if ($self->{show_internal_zigzag} || $self->{show_internal_labels}) {
        $self->{smc_overlay}->draw(
            $c,
            $start,
            $end,
            $x_of,
            \%state,
            $self->{price_panel},
            result      => $self->{last_smc_internal},
            style       => 'internal',
            show_zigzag => $self->{show_internal_zigzag},
            show_labels => $self->{show_internal_labels},
        );
    }

    #print "DRAW EVENT FLAGS ext_bos=$self->{layers}{external}{bos} ext_choch=$self->{layers}{external}{choch} ";
    #print "int_bos=$self->{layers}{internal}{bos} int_choch=$self->{layers}{internal}{choch}\n";

    #print "EXT EVENTS = " . scalar(@{$self->{last_smc_external}->{events} || []}) . "\n";
    #print "INT EVENTS = " . scalar(@{$self->{last_smc_internal}->{events} || []}) . "\n";

    if ($self->{layers}{external}{bos} || $self->{layers}{external}{choch}) {
        my $ext_event_draw = $self->{smc_overlay}->draw_events(
            $c,
            $start,
            $end,
            $x_of,
            \%state,
            $self->{price_panel},
            $self->{last_smc_external}->{events} || [],
            show_bos   => $self->{layers}{external}{bos},
            show_choch => $self->{layers}{external}{choch},
            style      => 'external',
        );

       # print "DRAW EXT EVENTS total=$ext_event_draw->{total} visible=$ext_event_draw->{visible} drawn=$ext_event_draw->{drawn}\n"
        #    if $ext_event_draw;
    }

    if ($self->{layers}{internal}{bos} || $self->{layers}{internal}{choch}) {
        my $int_event_draw = $self->{smc_overlay}->draw_events(
            $c,
            $start,
            $end,
            $x_of,
            \%state,
            $self->{price_panel},
            $self->{last_smc_internal}->{events} || [],
            show_bos   => $self->{layers}{internal}{bos},
            show_choch => $self->{layers}{internal}{choch},
            style      => 'internal',
        );

        #print "DRAW INT EVENTS total=$int_event_draw->{total} visible=$int_event_draw->{visible} drawn=$int_event_draw->{drawn}\n"
         #   if $int_event_draw;
    }

    if ($self->{show_fvg}) {
    $self->{smc_overlay}->draw_fvg(
        $c,
        $start,
        $end,
        $x_of,
        \%state,
        $self->{price_panel},
        $self->{last_smc_external}->{fvg} || [],
    );
}

if ($self->{show_order_blocks}) {
    $self->{smc_overlay}->draw_order_blocks(
        $c,
        $start,
        $end,
        $x_of,
        \%state,
        $self->{price_panel},
        $self->{last_smc_external}->{order_blocks} || [],
    );
}

    if ($self->{show_bsl} || $self->{show_ssl} || $self->{show_eqh} || $self->{show_eql} || $self->{show_liquidity_events}) {
        $self->{liquidity_overlay}->{show_ssl} = $self->{show_ssl};
        $self->{liquidity_overlay}->{show_eqh} = $self->{show_eqh};
        $self->{liquidity_overlay}->{show_eql} = $self->{show_eql};
        $self->{liquidity_overlay}->{show_liquidity_events} = $self->{show_liquidity_events};

        $self->{liquidity_overlay}->draw(
            $c, $start, $end, $x_of, \%state, $self->{price_panel}
        );
    }

    if ($self->{show_volume_pivots}) {
        $self->{liquidity_overlay}->draw_volume_pivots(
            $c, $start, $end, $x_of, \%state, $self->{price_panel}
        );
    }


    # Limpia el área del ATR para ocultar cualquier vela/volumen que se haya pasado.
    $c->createRectangle(
        $self->{left}, $atr_top,
        $right, $h - $self->{bottom_h},
        -fill => 'white',
        -outline => 'white'
    );

$c->createLine($self->{left}, $atr_top, $right, $atr_top, -fill => '#cccccc', -width => 2);

$self->{atr_panel}->draw($c, $atr, $x_of, \%state);


    $self->{atr_min} = $state{atr_min};
    $self->{atr_max} = $state{atr_max};

    $self->draw_crosshair($start, $end, $x_of, $right, $h, \%state)if defined $self->{mouse_x};
}




sub draw_time_axis {
    my ($self, $start, $end, $x_of, $right, $h) = @_;
    my $c = $self->{canvas};
    my $data = $self->{market}->get_slice($start, $end);

    return if !@$data;

    my $left   = $self->{left};
    my $plot_w = $right - $left;
    my $count  = $end - $start + 1;
    return if $count <= 0;

    my $px_per_candle = $plot_w / $count;
    my $tf = $self->{tf} || 1;

    if ($tf eq 'D' || $tf eq 'W') {
    for my $i (0 .. $#$data) {
        my $time = $data->[$i]{time};
        my ($date) = $time =~ /(\d{4}-\d{2}-\d{2})T/;
        next if !defined $date;

        my $x = $x_of->($i);
        my $label = _day_label($date);

        $c->createLine($x, 0, $x, $h - $self->{bottom_h},
            -fill => '#dddddd');

        $c->createText($x, $h - 14,
            -text => $label,
            -fill => '#111',
            -font => ['Arial', 9, 'bold']);
    }

    return;
}

    my $min_gap  = 80;
    my $hour_gap = 70;

    my @important_ticks;

    # 1) TICKS IMPORTANTES:
    #    - cambio de día
    #    - medianoche 00:00
    #    - viernes 17:00 cierre de mercado
    for my $i (0 .. $#$data) {
        my $time = $data->[$i]{time};
        my ($date, $hh, $mm) = $time =~ /(\d{4}-\d{2}-\d{2})T(\d{2}):(\d{2})/;
        next if !defined $date;

        my $prev_time = $i > 0 ? $data->[$i - 1]{time} : '';
        my ($prev_date) = $prev_time =~ /(\d{4}-\d{2}-\d{2})T/;

        # La fecha SOLO se marca en medianoche real.
        # No se marca por ser la primera vela visible.
        my $is_new_day = 0;
        my $is_midnight = ($hh == 0 && $mm == 0);

        my ($y, $m, $d) = split /-/, $date;
        my $dow = (localtime(Time::Local::timelocal(0, 0, 12, $d, $m - 1, $y)))[6];
        my $is_friday_close = ($dow == 5 && $hh == 17 && $mm == 0);

        next if !$is_new_day && !$is_midnight && !$is_friday_close;

        my $label;
        if ($is_friday_close) {
            $label = _day_label($date) . " 17:00";
        } else {
            $label = _day_label($date);
        }

        my $x = $x_of->($i);
        push @important_ticks, [$x, $label];
    }

    # 2) Dibujar siempre los ticks importantes
    for my $tick (@important_ticks) {
        my ($x, $label) = @$tick;

        $c->createLine($x, 0, $x, $h - $self->{bottom_h},
            -fill => '#dddddd');

        $c->createText($x, $h - 14,
            -text => $label,
            -fill => '#111',
            -font => ['Arial', 9, 'bold']);
    }

    # 3) Si los ticks importantes están muy juntos, no dibujar horas normales
    my $min_important_distance = 999999;

    for my $i (1 .. $#important_ticks) {
        my $dist = $important_ticks[$i][0] - $important_ticks[$i - 1][0];
        $min_important_distance = $dist if $dist < $min_important_distance;
    }

    return if @important_ticks > 1 && $min_important_distance < 260;

    # 4) Intervalo de horas según zoom
    my $label_minutes;

    if ($px_per_candle >= 45) {
        $label_minutes = $tf;
    } elsif ($px_per_candle >= 25) {
        $label_minutes = $tf * 2;
    } elsif ($px_per_candle >= 12) {
        $label_minutes = $tf * 4;
    } elsif ($px_per_candle >= 6) {
        $label_minutes = 60;
    } elsif ($px_per_candle >= 3) {
        $label_minutes = 180;
    } else {
        $label_minutes = 360;
    }

    if ($label_minutes <= 1) {
        $label_minutes = 1;
    } elsif ($label_minutes <= 5) {
        $label_minutes = 5;
    } elsif ($label_minutes <= 15) {
        $label_minutes = 15;
    } elsif ($label_minutes <= 30) {
        $label_minutes = 30;
    } elsif ($label_minutes <= 60) {
        $label_minutes = 60;
    } elsif ($label_minutes <= 180) {
        $label_minutes = 180;
    } else {
        $label_minutes = 360;
    }

    # 5) Horas normales: solo si caben y no chocan
    my $last_hour_x = -999999;

    for my $i (0 .. $#$data) {
        my $time = $data->[$i]{time};
        my ($date, $hh, $mm) = $time =~ /(\d{4}-\d{2}-\d{2})T(\d{2}):(\d{2})/;
        next if !defined $date;

        my $minute_of_day = $hh * 60 + $mm;
        next if $minute_of_day % $label_minutes != 0;

        my $x = $x_of->($i);

        next if $x - $last_hour_x < $hour_gap;

        my $too_close = 0;
        for my $tick (@important_ticks) {
            my ($ix) = @$tick;
            if (abs($x - $ix) < $min_gap) {
                $too_close = 1;
                last;
            }
        }
        next if $too_close;

        $c->createLine($x, 0, $x, $h - $self->{bottom_h},
            -fill => '#eeeeee');

        $c->createText($x, $h - 14,
            -text => "$hh:$mm",
            -fill => '#111',
            -font => ['Arial', 9, 'normal']);

        $last_hour_x = $x;
    }
}

sub _day_label {
    my ($date) = @_;
    my ($y, $m, $d) = split /-/, $date;
    return "$d/$m";
}

sub draw_crosshair {
    my ($self, $start, $end, $x_of, $right, $h, $state) = @_;

    my $c = $self->{canvas};

    return if !defined $self->{mouse_x};
    return if !defined $self->{mouse_y};

    my $x = $self->{mouse_x};
    my $y = $self->{mouse_y};

    return if $x < $self->{left};
    return if $x > $right;

    my $idx = $self->x_to_index($x);
    $idx = $start if $idx < $start;
    $idx = $end   if $idx > $end;

    my $local_i = $idx - $start;
    my $candle = $self->{market}->get_candle($idx);

    # Snap horizontal: la línea vertical se pega al centro de la vela.
    if ($candle) {
        $x = $x_of->($local_i);
    }
# Snap vertical a O/H/L/C solo si el mouse está cerca de esos precios.
if ($candle && $y < $state->{atr_top}) {

    my @levels = (
        $candle->{open},
        $candle->{high},
        $candle->{low},
        $candle->{close},
    );

    my $best_y;
    my $best_dist = 999999;

    for my $price (@levels) {
        my $level_y = $self->{price_panel}->{scale}->price_to_y(
            $price,
            $self->{price_min},
            $self->{price_max},
            0,
            $state->{price_h}
        );

        my $dist = abs($y - $level_y);

        if ($dist < $best_dist) {
            $best_dist = $dist;
            $best_y = $level_y;
        }
    }

    # Sensibilidad del snap: 8 px.
    # Sube a 12 si quieres que se pegue más fácil.
    if ($best_dist <= 8) {
        $y = $best_y;
    }
}



    # Línea vertical y horizontal del crosshair
    $c->createLine($x, 0, $x, $h - $self->{bottom_h},
        -fill => '#666666', -dash => [4,4]);

    $c->createLine($self->{left}, $y, $right, $y,
        -fill => '#666666', -dash => [4,4]);




    my $label;

    if ($y < $state->{atr_top}) {
        my $price = $self->{price_panel}->{scale}->y_to_price(
    $y,
    $self->{price_min},
    $self->{price_max},
    0,
    $state->{price_h}
);

$price = _round_to_tick($price, 0.25);
$label = sprintf("%.2f", $price);
    } else {
        $label = sprintf("%.2f", $self->{atr_panel}->{scale}->y_to_price(
            $y,
            $self->{atr_min},
            $self->{atr_max},
            $state->{atr_top},
            $state->{atr_h}
        ));
    }

    $c->createRectangle($right + 2, $y - 10, $right + $self->{scale_w} - 5, $y + 10,
        -fill => '#c62828', -outline => '#c62828');

    $c->createText($right + 8, $y,
        -anchor => 'w',
        -text => $label,
        -fill => 'white');

    

    if ($candle && $y < $h - $self->{bottom_h}) {
        my ($date, $hhmm) = $candle->{time} =~ /(\d{4}-\d{2}-\d{2})T(\d{2}:\d{2})/;

        my $label_x = $x;

        # Mantener la etiqueta negra dentro del área visible.
        my $label_half_w = 55;
        my $min_x = $self->{left} + $label_half_w;
        my $max_x = $right - $label_half_w;

        $label_x = $min_x if $label_x < $min_x;
        $label_x = $max_x if $label_x > $max_x;

        $c->createRectangle($label_x - $label_half_w, $h - 34,
                            $label_x + $label_half_w, $h - 12,
            -fill => '#111111', -outline => '#111111');

        $c->createText($label_x, $h - 23,
            -text => "$date  $hhmm",
            -fill => 'white',
            -font => ['Arial', 9]);
    }


    # Mostrar OHLC de la vela actual del crosshair
if ($candle) {
    my $ohlc = sprintf(
        "O %.2f   H %.2f   L %.2f   C %.2f",
        $candle->{open},
        $candle->{high},
        $candle->{low},
        $candle->{close}
    );

    my $color = ($candle->{close} >= $candle->{open}) ? '#089981' : '#f23645';

    $c->createText(
        $self->{left} + 8,
        16,
        -anchor => 'w',
        -text => $ohlc,
        -fill => $color,
        -font => ['Arial', 10, 'bold']
    );
}
}

sub mouse_move {
    my ($self, $x, $y, $state) = @_;

    $self->{mouse_x} = $x;
    $self->{mouse_y} = $y;
    $self->{ctrl_down} = ($state & 0x0004) ? 1 : 0;

    my $idx = $self->x_to_index($x);
    my $last = $self->{market}->last_index();

    $idx = 0 if $idx < 0;
    $idx = $last if $idx > $last;

    $self->{mouse_index} = $idx;

    $self->draw();
    return;
}

sub x_to_index {
    my ($self, $x) = @_;
    my ($w, $h, $right, $atr_top, $price_h, $plot_w) = $self->layout();

    my $step = $plot_w / $self->{visible};

    my $idx = int(
        $self->{first}
        + (($x - $self->{left} - ($step / 2)) / $step)
        + 0.5
    );

    $idx = 0 if $idx < 0;
    $idx = $self->{market}->last_index if $idx > $self->{market}->last_index;

    return $idx;
}

sub mouse_down {
    my ($self, $x, $y) = @_;

        if ($self->{replay_selecting}) {
        my $idx = $self->x_to_index($x);
        $self->replay_start_at($idx);
        return;
    }
    my ($w, $h, $right, $atr_top) = $self->layout();

    # Drag sobre escala inferior: zoom horizontal
    if ($y >= $h - $self->{bottom_h}) {
        my ($w, $h, $right, $atr_top, $price_h, $plot_w) = $self->layout();

        my $ratio = ($x - $self->{left}) / $plot_w;
        $ratio = 0 if $ratio < 0;
        $ratio = 1 if $ratio > 1;

        $self->{time_scale_drag} = {
            x => $x,
            visible => $self->{visible},
            first => $self->{first},
            ratio => $ratio,
            anchor => $self->{first} + $ratio * $self->{visible},
        };

        return;
    }

    # Click sobre eje Y derecho: activar escalado vertical manual
    if ($x >= $right) {
        my $panel = ($y >= $atr_top) ? 'atr' : 'price';

        $self->{scale_drag} = {
            y => $y,
            panel => $panel,
            price_min => $self->{price_min},
            price_max => $self->{price_max},
            atr_min   => $self->{atr_min},
            atr_max   => $self->{atr_max},
        };

        return;
    }

    if (abs($y - $atr_top) < 6) {
        $self->{resize_atr} = 1;
    } else {
        my $panel = ($y >= $atr_top) ? 'atr' : 'price';

        $self->{drag} = {
            x => $x,
            y => $y,
            first => $self->{first},
            panel => $panel,

            price_min => $self->{price_min},
            price_max => $self->{price_max},

            atr_min => $self->{atr_min},
            atr_max => $self->{atr_max},
        };
    }
}

sub mouse_drag {
    my ($self, $x, $y) = @_;

    # Mantener el crosshair pegado al cursor mientras se arrastra.
    $self->{mouse_x} = $x;
    $self->{mouse_y} = $y;

    my $idx = $self->x_to_index($x);
    my $last = $self->{market}->last_index();

    $idx = 0 if $idx < 0;
    $idx = $last if $idx > $last;

    $self->{mouse_index} = $idx;

    my ($w, $h, $right, $atr_top, $price_h, $plot_w) = $self->layout();


    if ($self->{time_scale_drag}) {
        my $dx = $x - $self->{time_scale_drag}{x};

        # Izquierda: alejar / más velas
        # Derecha: acercar / menos velas
        my $factor = exp(-$dx / 250);
        my $new_visible = int($self->{time_scale_drag}{visible} * $factor);

        my $effective_last = $self->{replay_mode}
    ? $self->{replay_index}
    : $self->{market}->last_index();

my $n = $effective_last + 1;
        $new_visible = 2  if $new_visible < 2;
        $new_visible = $n if $new_visible > $n;

        my $ratio  = $self->{time_scale_drag}{ratio};
        my $anchor = $self->{time_scale_drag}{anchor};

        $self->{visible} = $new_visible;
        $self->{first} = $anchor - $ratio * $new_visible;

        $self->limit_first();

        if ($self->{auto_y}) {
            $self->{lock_y_on_zoom} = 0;
            delete $self->{price_min};
            delete $self->{price_max};
            delete $self->{atr_min};
            delete $self->{atr_max};
        }

        $self->draw();
        return;
    }

    if ($self->{scale_drag}) {
    my $dy = $y - $self->{scale_drag}{y};

    # Arriba: estirar velas/ATR
    # Abajo: comprimir velas/ATR
    my $factor = 1 + abs($dy) / 180;
    $factor = 1 / $factor if $dy < 0;

    # Si Auto vertical está activo:
    # solo permitimos arrastre horizontal.
    # El eje Y se recalcula automáticamente con las velas visibles.
    if ($self->{auto_y}) {
        $self->{lock_y_on_zoom} = 0;
        $self->draw();
        return;
    }

    # Si Auto vertical está apagado:
    # permitimos movimiento vertical manual.
    $self->{lock_y_on_zoom} = 1;

    if ($self->{scale_drag}{panel} eq 'price') {
        my $min = $self->{scale_drag}{price_min};
        my $max = $self->{scale_drag}{price_max};
        my $mid = ($min + $max) / 2;
        my $range = ($max - $min) * $factor;

        $self->{price_min} = $mid - $range / 2;
        $self->{price_max} = $mid + $range / 2;
    } else {
        my $min = $self->{scale_drag}{atr_min};
        my $max = $self->{scale_drag}{atr_max};
        my $mid = ($min + $max) / 2;
        my $range = ($max - $min) * $factor;

        $self->{atr_min} = $mid - $range / 2;
        $self->{atr_max} = $mid + $range / 2;
    }

    $self->draw();
    return;
}


    if ($self->{resize_atr}) {
        my $new = $h - $self->{bottom_h} - $y;
        $new = 80 if $new < 80;
        $new = 320 if $new > 320;
        $self->{atr_h} = $new;
    }
    elsif ($self->{drag}) {
        my $dx = $x - $self->{drag}{x};
        my $dy = $y - $self->{drag}{y};

        # Movimiento horizontal: tiempo/eje X
        $self->{first} = $self->{drag}{first} - $dx / $plot_w * $self->{visible};
        $self->limit_first();

            if ($self->{auto_y}) {
        # Auto vertical activo:
        # NO tocar Y manualmente.
        # NO bloquear Y.
        # El draw recalcula la escala con lo visible.
        $self->{lock_y_on_zoom} = 0;

        delete $self->{price_min};
        delete $self->{price_max};
        delete $self->{atr_min};
        delete $self->{atr_max};

        $self->draw();
        return;
    }
        $self->{lock_y_on_zoom} = 1;

        if ($self->{drag}{panel} eq 'price') {
            my $range = $self->{drag}{price_max} - $self->{drag}{price_min};
            $range = 1 if $range == 0;

            my $shift = $dy / $price_h * $range;

            $self->{price_min} = $self->{drag}{price_min} + $shift;
            $self->{price_max} = $self->{drag}{price_max} + $shift;
        }
        elsif ($self->{drag}{panel} eq 'atr') {
            my $range = $self->{drag}{atr_max} - $self->{drag}{atr_min};
            $range = 1 if !defined($range) || $range == 0;

            my $shift = $dy / $self->{atr_h} * $range;

            $self->{atr_min} = $self->{drag}{atr_min} + $shift;
            $self->{atr_max} = $self->{drag}{atr_max} + $shift;
        }
    }

    $self->draw();
}

sub mouse_up {
    my ($self, $x, $y) = @_;

    delete $self->{drag};
    delete $self->{resize_atr};
    delete $self->{scale_drag};
    delete $self->{time_scale_drag};

    $self->draw();
}

sub mouse_wheel {
    my ($self, $delta, $mouse_x, $mouse_y, $state) = @_;

    my $n = $self->{market}->last_index() + 1;
    return if $n <= 0;

    my ($w, $h, $right, $atr_top, $price_h, $plot_w, $bar_w) = $self->layout();

    my $old_visible = $self->{visible};
    my $old_first   = $self->{first};
    my $old_right   = $old_first + $old_visible;

    my $ctrl = defined($state) && ($state & 0x0004);

    my $new_visible;

    if ($delta > 0) {
        $new_visible = int($old_visible * 0.80);   # acercar
        $new_visible = $old_visible - 1 if $new_visible == $old_visible;
    } else {
        $new_visible = int($old_visible * 1.25);   # alejar
        $new_visible = $old_visible + 1 if $new_visible == $old_visible;
    }

    # Límites absolutos de zoom
    $new_visible = 2  if $new_visible < 2;
    $new_visible = $n if $new_visible > $n;

    if ($ctrl && defined($mouse_x) && $mouse_x >= $self->{left} && $mouse_x <= $right) {

        my $current_index = $self->x_to_index($mouse_x);
        $current_index = 0      if $current_index < 0;
        $current_index = $n - 1 if $current_index > $n - 1;

        # Se actualiza el ancla si es primera vez o si cambiaste de vela.
        if (
            !$self->{ctrl_zoom_anchor}
            || $self->{ctrl_zoom_anchor}{mouse_index} != $current_index
        ) {
            $self->{ctrl_zoom_anchor} = {
                index       => $current_index,
                mouse_index => $current_index,
                mouse_x     => $mouse_x,
            };
        }

        my $anchor_index = $self->{ctrl_zoom_anchor}{index};
        my $anchor_x     = $self->{ctrl_zoom_anchor}{mouse_x};

        my $new_step = $plot_w / $new_visible;

        # Fórmula compatible con x_of:
        # x = left + step/2 + (index - first) * step
        # Despejando first:
        $self->{first} = $anchor_index
            - (($anchor_x - $self->{left} - ($new_step / 2)) / $new_step);

    } else {

        # Si ya no hay Ctrl, se libera el congelado.
        delete $self->{ctrl_zoom_anchor};

        # Scroll normal mantiene fijo el borde derecho.
        $self->{first} = $old_right - $new_visible;
    }

    $self->{visible} = $new_visible;

    # IMPORTANTE:
    # En Ctrl + scroll NO llamamos limit_first porque mueve la vela ancla.
    # En scroll normal sí.
    if (!$ctrl) {
        $self->limit_first();
    }

    eval { $self->{canvas}->yviewMoveto(0); };

    if ($self->{auto_y}) {
        $self->{lock_y_on_zoom} = 0;
        delete $self->{price_min};
        delete $self->{price_max};
        delete $self->{atr_min};
        delete $self->{atr_max};
    } else {
        $self->{lock_y_on_zoom} = 1;
    }

    $self->draw();
}


sub limit_first {
    my ($self) = @_;

    my $last = $self->{market}->last_index();

    my $effective_last = $self->{replay_mode}
        ? $self->{replay_index}
        : $last;

    my $n = $effective_last + 1;
    return if $n <= 0;

    my $min_first = 2 - $self->{visible};
    my $max_first = $n - 2;

    $max_first = 0 if $max_first < 0;

    $self->{first} = $min_first if $self->{first} < $min_first;
    $self->{first} = $max_first if $self->{first} > $max_first;
}

sub go_to_start {
    my ($self) = @_;

    # Inicio: las 2 primeras velas quedan junto a la escala derecha.
    $self->{first} = 2 - $self->{visible};
    $self->limit_first();

    if ($self->{auto_y}) {
        delete $self->{price_min};
        delete $self->{price_max};
        delete $self->{atr_min};
        delete $self->{atr_max};
        $self->{lock_y_on_zoom} = 0;
    }

    $self->draw();
}

sub go_to_end {
    my ($self) = @_;

    my $n = $self->{market}->last_index() + 1;

    # Queremos que en el borde izquierdo queden solo 2 velas visibles
    # y luego espacio blanco hasta la última vela en el lado derecho.
    $self->{first} = $n - 2;

    if ($self->{auto_y}) {
        delete $self->{price_min};
        delete $self->{price_max};
        delete $self->{atr_min};
        delete $self->{atr_max};
        $self->{lock_y_on_zoom} = 0;
    }

    $self->draw();
}

sub _round_to_tick {
    my ($value, $tick) = @_;
    $tick = 0.25 if !defined $tick || $tick <= 0;
    return int($value / $tick + ($value >= 0 ? 0.5 : -0.5)) * $tick;
}

sub replay_select_start {
    my ($self) = @_;

    $self->replay_pause();

    $self->{replay_mode}      = 0;
    $self->{replay_selecting} = 1;
    $self->{replay_index}     = undef;

    print ">>> REPLAY SELECT MODE: haga click sobre la vela inicial del Replay\n";

    $self->draw();
}

sub replay_start_at {
    my ($self, $idx) = @_;

    my $last = $self->{market}->last_index();

    $idx = 0     if $idx < 0;
    $idx = $last if $idx > $last;

    print ">>> REPLAY START AT index=$idx\n";

    $self->{replay_selecting} = 0;
    $self->{replay_mode}      = 1;
    $self->{replay_index}     = $idx;

    $self->_replay_apply_window();

    if ($self->{auto_y}) {
        delete $self->{price_min};
        delete $self->{price_max};
        delete $self->{atr_min};
        delete $self->{atr_max};
        $self->{lock_y_on_zoom} = 0;
    }

    $self->draw();
    $self->audit_replay_state() if $self->{debug_replay};
}

sub replay_exit {
    my ($self) = @_;

    $self->replay_pause();

    $self->{replay_mode}      = 0;
    $self->{replay_selecting} = 0;
    $self->{replay_index}     = undef;

    $self->fit_all();
    $self->draw();
}

sub replay_pause {
    my ($self) = @_;

    if (defined $self->{replay_after}) {
        $self->{mw}->afterCancel($self->{replay_after});
        $self->{replay_after} = undef;
    }
}

sub replay_play {
    my ($self) = @_;

    return if !$self->{replay_mode};

    $self->replay_pause();

    $self->{replay_after} = $self->{mw}->after(
        $self->{replay_speed},
        sub {
            $self->replay_step(1);
            $self->replay_play() if $self->{replay_mode};
        }
    );
}

sub replay_step {
    my ($self, $dir) = @_;

    return if !$self->{replay_mode};

    my $last = $self->{market}->last_index();

    $self->{replay_index} += $dir;

    $self->{replay_index} = 0 if $self->{replay_index} < 0;
    $self->{replay_index} = $last if $self->{replay_index} > $last;

    $self->_replay_apply_window();
    $self->draw();
    $self->audit_replay_state() if $self->{debug_replay};
}

sub _replay_apply_window {
    my ($self) = @_;

    my $window = $self->{visible} // 120;
    $window = 120 if $window < 20;

    my $end = $self->{replay_index};
    my $first = $end - $window + 1;

    $first = 0 if $first < 0;

    $self->{first} = $first;

    my $max_visible = $end - $first + 1;
    $self->{visible} = $max_visible if $self->{visible} > $max_visible;
    $self->{visible} = 2 if $self->{visible} < 2;
}

sub audit_replay_state {
    my ($self) = @_;

    return if !$self->{debug_replay};
    return if !$self->{replay_mode};

    my $idx = $self->{replay_index};

    my $liq = $self->{last_liq_result};
    my $smc = $self->{last_smc_result};

    return if !$liq || !$smc;

    print "\n=== REPLAY AUDIT ===\n";
    print "Replay index: $idx\n";
    print "Timeframe: " . ($self->{market}->{timeframe} // '?') . "\n";
print "Last index: " . $self->{market}->last_index() . "\n";

    print "Structural pivots: "
        . scalar(@{$liq->{structural_pivots} || []}) . "\n";

    print "Minor pivots: "
        . scalar(@{$liq->{minor_pivots} || []}) . "\n";

    print "Liquidity levels: "
        . scalar(@{$liq->{liquidity} || []}) . "\n";

    print "SMC structure: "
        . scalar(@{$smc->{structure} || []}) . "\n";

    print "BOS / CHoCH events: "
        . scalar(@{$smc->{events} || []}) . "\n";

    my $future_problem = 0;

    for my $lvl (@{$liq->{liquidity} || []}) {
        for my $k (qw(created_index swept_index resolved_index)) {
            next if !defined $lvl->{$k};
            if ($lvl->{$k} > $idx) {
                print "ERROR FUTURO LIQUIDITY: $k=$lvl->{$k} replay=$idx\n";
                $future_problem = 1;
            }
        }
    }

    for my $e (@{$smc->{events} || []}) {
        if (defined $e->{index} && $e->{index} > $idx) {
            print "ERROR FUTURO SMC: $e->{type} index=$e->{index} replay=$idx\n";
            $future_problem = 1;
        }
    }

    print $future_problem
        ? "RESULTADO: HAY FILTRACION FUTURA\n"
        : "RESULTADO: OK, sin eventos futuros\n";

    print "====================\n";
}

sub toggle_liquidity {
    my ($self) = @_;

    $self->{show_liquidity} = !$self->{show_liquidity};
    $self->draw();
}

sub toggle_smc_events {
    my ($self) = @_;

    $self->{show_smc_events} = !$self->{show_smc_events};
    $self->draw();
}


sub _print_audit_summary {
    my ($self, $liq_result, $smc_external, $smc_internal, $market) = @_;

    return if $self->{audit_printed};

    my $liq_audit = $liq_result->{audit} || {};
    my $ext_audit = $smc_external->{audit} || {};
    my $int_audit = $smc_internal->{audit} || {};

    my $external_pivots = scalar grep {
        ($_->{structure} // '') eq 'external'
    } @{$liq_audit->{pivots} || []};

    my $internal_pivots = scalar grep {
        ($_->{structure} // '') eq 'internal'
    } @{$liq_audit->{pivots} || []};

    my $dup_ext = 0;
    my $dup_int = 0;

    my $chrono_ext = 0;
    my $chrono_int = 0;

    my $label_errors = 0;

    my $prev_high;
    my $prev_low;
    my $label_tolerance = 0.01;
    my $eq_errors = 0;
    my $bsl_ssl_errors = 0;
    my $liquidity_state_errors = 0;
    my $resolved_without_sweep = 0;
    my $missing_resolution = 0;
    my $sweep_errors = 0;
    my $grab_errors  = 0;
    my $run_errors   = 0;
    my $bos_position_errors   = 0;
    my $choch_position_errors = 0;


    for my $eq (@{$liq_result->{equal_levels} || []}) {

        my $type      = $eq->{type} // '';
        my $price1    = $eq->{price1} // $eq->{price};
        my $price2    = $eq->{price2} // $eq->{price};
        my $tolerance = $eq->{tolerance};

        next if !$type;
        next if !defined $price1;
        next if !defined $price2;
        next if !defined $tolerance;

        my $diff = abs($price1 - $price2);

        if ($diff > $tolerance) {
            $eq_errors++;

            printf "EQ ERROR: type=%s diff=%.4f tolerance=%.4f price1=%.2f price2=%.2f\n",
                $type, $diff, $tolerance, $price1, $price2;
        }
    }


    for my $liq (@{$liq_result->{liquidity} || []}) {

        my $type  = $liq->{type}  // '';
        my $price = $liq->{price};

        next if !$type;
        next if !defined $price;

        if ($type eq 'BSL') {

            my $origin_type = $liq->{origin_type}
                // $liq->{pivot_type}
                // $liq->{source_type}
                // '';

            if ($origin_type ne '' && $origin_type ne 'HIGH' && $origin_type ne 'EQH') {
                $bsl_ssl_errors++;

                printf "BSL SOURCE ERROR: price=%.2f origin_type=%s\n",
                    $price, $origin_type;
            }
        }

        elsif ($type eq 'SSL') {

            my $origin_type = $liq->{origin_type}
                // $liq->{pivot_type}
                // $liq->{source_type}
                // '';

            if ($origin_type ne '' && $origin_type ne 'LOW' && $origin_type ne 'EQL') {
                $bsl_ssl_errors++;

                printf "SSL SOURCE ERROR: price=%.2f origin_type=%s\n",
                    $price, $origin_type;
            }
        }
    }
    for my $liq (@{$liq_result->{liquidity} || []}) {

        my $state    = $liq->{state} // '';
        my $created  = $liq->{created_index};
        my $swept    = $liq->{swept_index};
        my $resolved = $liq->{resolved_index};

        next if !$state;

        if (defined $swept && defined $created && $swept < $created) {
            $liquidity_state_errors++;

            printf "LIQ STATE ERROR: swept before created type=%s price=%.2f created=%s swept=%s\n",
                $liq->{type} // '', $liq->{price} // 0, $created, $swept;
        }

        if (defined $resolved && defined $swept && $resolved < $swept) {
            $liquidity_state_errors++;

            printf "LIQ STATE ERROR: resolved before swept type=%s price=%.2f swept=%s resolved=%s\n",
                $liq->{type} // '', $liq->{price} // 0, $swept, $resolved;
        }

        if ($state eq 'Resolved' && !defined $swept) {
            $resolved_without_sweep++;

            printf "LIQ STATE ERROR: resolved without sweep type=%s price=%.2f created=%s\n",
                $liq->{type} // '', $liq->{price} // 0, $created // -1;
        }

        if (defined $swept && $state ne 'Resolved' && !defined $resolved) {
            $missing_resolution++;

            printf "LIQ STATE WARNING: swept but not resolved type=%s price=%.2f swept=%s state=%s\n",
                $liq->{type} // '', $liq->{price} // 0, $swept, $state;
        }
    }


    for my $liq (@{$liq_result->{liquidity} || []}) {

        my $type  = $liq->{type} // '';
        my $class = $liq->{classification} // '';
        my $price = $liq->{price};

        my $swept_i    = $liq->{swept_index};
        my $resolved_i = $liq->{resolved_index};

        next if !$type || !$class;
        next if !defined $price;
        next if !defined $swept_i;
        next if !defined $resolved_i;

        my $swept_bar = $market->get_slice($swept_i, $swept_i)->[0];
        my $resolved_bar = $market->get_slice($resolved_i, $resolved_i)->[0];

        next if !$swept_bar || !$resolved_bar;

        my $bars_after_sweep = $resolved_i - $swept_i;

        if ($class eq 'Sweep') {

            if ($bars_after_sweep != 0) {
                $sweep_errors++;
            }

            if ($type eq 'BSL') {
                if (!(($swept_bar->{high} // 0) > $price && ($resolved_bar->{close} // 0) < $price)) {
                    $sweep_errors++;
                }
            }
            elsif ($type eq 'SSL') {
                if (!(($swept_bar->{low} // 0) < $price && ($resolved_bar->{close} // 0) > $price)) {
                    $sweep_errors++;
                }
            }
        }

        elsif ($class eq 'Grab') {

            if ($bars_after_sweep <= 0) {
                $grab_errors++;
            }

            if ($type eq 'BSL') {
                if (!(($swept_bar->{high} // 0) > $price && ($resolved_bar->{close} // 0) < $price)) {
                    $grab_errors++;
                }
            }
            elsif ($type eq 'SSL') {
                if (!(($swept_bar->{low} // 0) < $price && ($resolved_bar->{close} // 0) > $price)) {
                    $grab_errors++;
                }
            }
        }

        elsif ($class eq 'Run') {

            my $outside_count = 0;

            for my $j ($swept_i .. $resolved_i) {
            my $bar = $market->get_slice($j, $j)->[0];
            next if !$bar;

                if ($type eq 'BSL' && ($bar->{close} // 0) > $price) {
                    $outside_count++;
                }
                elsif ($type eq 'SSL' && ($bar->{close} // 0) < $price) {
                    $outside_count++;
                }
            }

            if ($outside_count < ($liq->{outside_count} // 0)) {
                $run_errors++;
            }

            if ($outside_count < ($self->{confirm_bars} // 3)) {
                $run_errors++;
            }
        }
    }

    for my $e (@{$smc_external->{events} || []}) {

        my $raw_type    = $e->{raw_type} // '';
        my $break_index = $e->{break_index};
        my $event_index = $e->{index};
        my $pivot_index = $e->{pivot_index};

        my $break_price = $e->{break_price};
        my $pivot_price = $e->{pivot_price};

        next if !$raw_type;
        next if !defined $break_index;
        next if !defined $event_index;
        next if !defined $pivot_index;
        next if !defined $break_price;
        next if !defined $pivot_price;

        my $is_bos   = $raw_type =~ /BOS/;
        my $is_choch = $raw_type =~ /CHoCH/;

        next if !$is_bos && !$is_choch;

        my $error = 0;

        # La ruptura real no debe ocurrir antes del pivote roto
        if ($break_index < $pivot_index) {
            $error = 1;
        }

        # La ruptura real no debe ocurrir después del pivote/evento actual
        if ($break_index > $event_index) {
            $error = 1;
        }

        # Validación de dirección
        if ($raw_type =~ /UP/) {
            if ($break_price <= $pivot_price) {
                $error = 1;
            }
        }
        elsif ($raw_type =~ /DOWN/) {
            if ($break_price >= $pivot_price) {
                $error = 1;
            }
        }

        if ($error) {
            if ($is_bos) {
                $bos_position_errors++;
            }
            elsif ($is_choch) {
                $choch_position_errors++;
            }

            printf "SMC POSITION ERROR: type=%s pivot_i=%s break_i=%s event_i=%s pivot_price=%.2f break_price=%.2f\n",
                $raw_type,
                $pivot_index,
                $break_index,
                $event_index,
                $pivot_price,
                $break_price;
        }
    }

    for my $s (@{$smc_external->{structure} || []}) {

        my $label = $s->{raw_label} // '';
        my $type  = $s->{type} // '';
        my $price = $s->{price};

        next if !$label;
        next if !defined $price;

        if ($type eq 'HIGH') {

            if (defined $prev_high) {
                if ($label eq 'HH' && $price < $prev_high->{price} - $label_tolerance) {
                    $label_errors++;
                    printf "LABEL ERROR HIGH: i=%s label=%s price=%.2f prev_high_i=%s prev_high_price=%.2f\n",
                        $s->{index}, $label, $price, $prev_high->{index}, $prev_high->{price};
                }
                elsif ($label eq 'LH' && $price > $prev_high->{price} + $label_tolerance) {
                    $label_errors++;
                    printf "LABEL ERROR HIGH: i=%s label=%s price=%.2f prev_high_i=%s prev_high_price=%.2f\n",
                        $s->{index}, $label, $price, $prev_high->{index}, $prev_high->{price};
                }
            }

            $prev_high = $s;
        }

        elsif ($type eq 'LOW') {

            if (defined $prev_low) {
                if ($label eq 'HL' && $price < $prev_low->{price} - $label_tolerance) {
                    $label_errors++;
                    printf "LABEL ERROR LOW: i=%s label=%s price=%.2f prev_low_i=%s prev_low_price=%.2f\n",
                        $s->{index}, $label, $price, $prev_low->{index}, $prev_low->{price};
                }
                elsif ($label eq 'LL' && $price > $prev_low->{price} + $label_tolerance) {
                    $label_errors++;
                    printf "LABEL ERROR LOW: i=%s label=%s price=%.2f prev_low_i=%s prev_low_price=%.2f\n",
                        $s->{index}, $label, $price, $prev_low->{index}, $prev_low->{price};
                }
            }

            $prev_low = $s;
        }
    }


    my $prev_type;
    my $prev_index;

    for my $p (@{$liq_audit->{pivots} || []}) {

        next unless ($p->{structure} // '') eq 'external';

        if (defined $prev_type && $p->{type} eq $prev_type) {
            $dup_ext++;
        }

        if (defined $prev_index && $p->{index} < $prev_index) {
        $chrono_ext++;
    }

        $prev_type  = $p->{type};
        $prev_index = $p->{index};
    }

    $prev_type  = undef;
    $prev_index = undef;

    for my $p (@{$liq_audit->{pivots} || []}) {

        next unless ($p->{structure} // '') eq 'internal';

        if (defined $prev_type && $p->{type} eq $prev_type) {
            $dup_int++;
        }

        if (defined $prev_index && $p->{index} < $prev_index) {
        $chrono_int++;
    }

        $prev_type  = $p->{type};
        $prev_index = $p->{index};
    }


    my $hh = scalar grep { ($_->{label} // '') eq 'HH' } @{$ext_audit->{labels} || []};
    my $hl = scalar grep { ($_->{label} // '') eq 'HL' } @{$ext_audit->{labels} || []};
    my $lh = scalar grep { ($_->{label} // '') eq 'LH' } @{$ext_audit->{labels} || []};
    my $ll = scalar grep { ($_->{label} // '') eq 'LL' } @{$ext_audit->{labels} || []};

    my $bos = scalar @{$ext_audit->{bos} || []};
    my $choch = scalar @{$ext_audit->{choch} || []};

    print "\n================ AUDIT SUMMARY ================\n";
    print "External pivots : $external_pivots\n";
    print "Internal pivots : $internal_pivots\n";
    print "HH              : $hh\n";
    print "HL              : $hl\n";
    print "LH              : $lh\n";
    print "LL              : $ll\n";
    print "BOS             : $bos\n";
    print "CHoCH           : $choch\n";

    print "\n";
    print "---- ZIGZAG HEALTH -----------------\n";
    print "External duplicate HIGH/LOW : $dup_ext\n";
    print "Internal duplicate HIGH/LOW : $dup_int\n";
    print "External chronological errs : $chrono_ext\n";
    print "Internal chronological errs : $chrono_int\n";
    print "Label consistency errors    : $label_errors\n";
    print "------------------------------------\n";

    print "\n";
    print "---- LIQUIDITY POSITION HEALTH -----\n";
    print "EQH/EQL tolerance errors : $eq_errors\n";
    print "\n";
    print "---- LIQUIDITY STATE MACHINE -------\n";
    print "State order errors       : $liquidity_state_errors\n";
    print "Resolved without sweep   : $resolved_without_sweep\n";
    print "\n";
    print "---- LIQUIDITY CLASSIFICATION -------\n";
    print "Sweep rule errors : $sweep_errors\n";
    print "Grab rule errors  : $grab_errors\n";
    print "\n";
    print "---- SMC POSITION HEALTH -----------\n";
    print "BOS position errors   : $bos_position_errors\n";
    print "CHoCH position errors : $choch_position_errors\n";
    print "------------------------------------\n";

    print "================================================\n\n";

    $self->{audit_printed} = 1;
}
sub _open_layers_window {
    my ($self) = @_;

    if ($self->{layers_window} && Tk::Exists($self->{layers_window})) {
        $self->{layers_window}->raise;
        return;
    }

    my $win = $self->{mw}->Toplevel();
    $self->{layers_window} = $win;

    $win->title('Capas de estructura');
    $win->geometry('360x520');

    my $main = $win->Frame()->pack(
        -fill   => 'both',
        -expand => 1,
        -padx   => 10,
        -pady   => 10,
    );

    $main->Label(
        -text => 'Capas visibles',
        -font => ['Arial', 12, 'bold'],
    )->pack(-anchor => 'w', -pady => [0, 10]);

    $self->_build_layer_group(
        $main,
        'Estructura externa',
        'external'
    );

    $self->_build_layer_group(
        $main,
        'Estructura interna',
        'internal'
    );

    $main->Button(
        -text    => 'Ocultar todo',
        -command => sub {
            for my $scope (qw(external internal)) {
                for my $key (keys %{$self->{layers}{$scope}}) {
                    $self->{layers}{$scope}{$key} = 0;
                }
            }

            $self->_sync_legacy_layer_flags();
            $self->draw();
            $win->destroy;
            $self->{layers_window} = undef;
        }
    )->pack(-fill => 'x', -pady => [12, 4]);

    $main->Button(
        -text    => 'Cerrar',
        -command => sub {
            $win->destroy;
            $self->{layers_window} = undef;
        }
    )->pack(-fill => 'x');

    $win->protocol('WM_DELETE_WINDOW' => sub {
        $win->destroy;
        $self->{layers_window} = undef;
    });
}

sub _build_layer_group {
    my ($self, $parent, $title, $scope) = @_;

    my $frame = $parent->LabFrame(
        -label      => $title,
        -labelside  => 'acrosstop',
    )->pack(
        -fill => 'x',
        -pady => 8,
    );

    my @items = (
        ['zigzag',           'ZigZag'],
        ['labels',           'Etiquetas HH/HL/LH/LL'],
        ['bos',              'BOS'],
        ['choch',            'CHoCH'],
        ['bsl',              'BSL'],
        ['ssl',              'SSL'],
        ['eqh',              'EQH'],
        ['eql',              'EQL'],
        ['liquidity_events', 'Sweep / Grab / Run'],
        ['fvg',              'FVG'],
['order_blocks',     'Order Blocks'],
    );

    for my $item (@items) {
        my ($key, $label) = @$item;

        $frame->Checkbutton(
            -text     => $label,
            -variable => \$self->{layers}{$scope}{$key},
            -command  => sub {
                $self->_sync_legacy_layer_flags();
                $self->draw();
            },
        )->pack(-anchor => 'w');
    }
}
sub _toggle_layers_panel {
    my ($self) = @_;

    if ($self->{layers_panel_visible}) {
        $self->{layers_panel}->packForget();
        $self->{layers_panel_visible} = 0;
        return;
    }

    $self->{layers_panel}->pack(
        -side => 'top',
        -fill => 'x',
        -after => $self->{top_bar},
    );

    $self->{layers_panel_visible} = 1;
}
sub _set_internal_zigzag_tf {
    my ($self, $label) = @_;

    my %map = (
        '3 minutos'  => 3,
        '5 minutos'  => 5,
        '10 minutos' => 10,
        '15 minutos' => 15,
        '30 minutos' => 30,
        '45 minutos' => 45,
        '1 hora'     => 60,
        '2 horas'    => 120,
        '3 horas'    => 180,
        '4 horas'    => 240,
        '1 día'      => 'D',
        '1 semana'   => 'W',
    );

    $self->{internal_zigzag_tf_label} = $label;
    $self->{internal_zigzag_tf} = $map{$label} // 60;

    $self->{smc_cache_key} = undef;

    if ($self->{liquidity_engine}) {
        $self->{liquidity_engine}->{internal_zigzag_tf} = $self->{internal_zigzag_tf};
    }

    $self->draw();
}


sub _build_layers_panel {
    my ($self) = @_;

    my $panel = $self->{layers_panel};

    for my $child ($panel->children) {
        $child->destroy;
    }

    $panel->Label(
        -text => 'SMC Layers',
        -font => ['Arial', 10, 'bold'],
    )->grid(-row => 0, -column => 0, -padx => 8, -pady => 4);

    $panel->Label(
        -text => 'Internal',
        -font => ['Arial', 9, 'bold'],
    )->grid(-row => 0, -column => 1, -padx => 12);

    $panel->Label(
        -text => 'External',
        -font => ['Arial', 9, 'bold'],
    )->grid(-row => 0, -column => 2, -padx => 12);

    my @rows = (
        ['zigzag',           'ZigZag'],
        ['labels',           'HH HL LH LL'],
        ['bos',              'BOS'],
        ['choch',            'CHoCH'],
        ['bsl',              'BSL'],
        ['ssl',              'SSL'],
        ['eqh',              'EQH'],
        ['eql',              'EQL'],
        ['liquidity_events', 'Sweep / Grab / Run'],
        ['fvg',              'FVG'],
          ['order_blocks',     'Order Blocks'],
    );

    my $r = 1;

    for my $item (@rows) {
        my ($key, $label) = @$item;

        $panel->Label(
            -text => $label,
        )->grid(
            -row => $r,
            -column => 0,
            -sticky => 'w',
            -padx => 8,
            -pady => 2,
        );

        $panel->Checkbutton(
            -variable => \$self->{layers}{internal}{$key},
            -command  => sub {
                $self->_sync_layer_flags();
                $self->draw();
            },
        )->grid(-row => $r, -column => 1);

        $panel->Checkbutton(
            -variable => \$self->{layers}{external}{$key},
            -command  => sub {
                $self->_sync_layer_flags();
                $self->draw();
            },
        )->grid(-row => $r, -column => 2);

        $r++;
    }

        $panel->Label(
        -text => 'ZZ interno TF',
    )->grid(
        -row => $r,
        -column => 0,
        -sticky => 'w',
        -padx => 8,
        -pady => 2,
    );

    $panel->Optionmenu(
        -options  => [3, 5, 10, 15, 30, 45, 60, 120, 180, 240, 'D', 'W'],
        -variable => \$self->{internal_zigzag_tf},
        -command  => sub {
            $self->{smc_cache_key} = undef;
            $self->draw();
        },
    )->grid(
        -row => $r,
        -column => 1,
        -columnspan => 2,
        -sticky => 'w',
    );

    $r++;

    $panel->Label(
        -text => 'ZZ externo Len',
    )->grid(
        -row => $r,
        -column => 0,
        -sticky => 'w',
        -padx => 8,
        -pady => 2,
    );

    $panel->Scale(
        -from       => 50,
        -to         => 300,
        -orient     => 'horizontal',
        -resolution => 10,
        -variable   => \$self->{external_swing_len},
        -command    => sub {
            $self->{smc_cache_key} = undef;
            $self->draw();
        },
    )->grid(
        -row => $r,
        -column => 1,
        -columnspan => 2,
        -sticky => 'we',
    );

    $r++;


    $panel->Button(
        -text => 'Ocultar todo',
        -command => sub {
            for my $scope (qw(internal external)) {
                for my $key (keys %{$self->{layers}{$scope}}) {
                    $self->{layers}{$scope}{$key} = 0;
                }
            }
            $self->_sync_layer_flags();
            $self->draw();
        },
    )->grid(
        -row => 1,
        -column => 3,
        -rowspan => 2,
        -padx => 12,
        -sticky => 'nsew',
    );

    $panel->Button(
        -text => 'Cerrar',
        -command => sub {
            $self->{layers_panel}->packForget();
            $self->{layers_panel_visible} = 0;
        },
    )->grid(
        -row => 3,
        -column => 3,
        -rowspan => 2,
        -padx => 12,
        -sticky => 'nsew',
    );
}

sub _sync_layer_flags {
    my ($self) = @_;

    $self->{show_external_zigzag} = $self->{layers}{external}{zigzag};
    $self->{show_internal_zigzag} = $self->{layers}{internal}{zigzag};

    $self->{show_external_labels} = $self->{layers}{external}{labels};
    $self->{show_internal_labels} = $self->{layers}{internal}{labels};

    $self->{show_bos} =
        $self->{layers}{external}{bos} || $self->{layers}{internal}{bos};

    $self->{show_choch} =
        $self->{layers}{external}{choch} || $self->{layers}{internal}{choch};

    $self->{show_bsl} =
        $self->{layers}{external}{bsl} || $self->{layers}{internal}{bsl};

    $self->{show_ssl} =
        $self->{layers}{external}{ssl} || $self->{layers}{internal}{ssl};

    $self->{show_eqh} =
        $self->{layers}{external}{eqh} || $self->{layers}{internal}{eqh};

    $self->{show_eql} =
        $self->{layers}{external}{eql} || $self->{layers}{internal}{eql};

    $self->{show_liquidity_events} =
        $self->{layers}{external}{liquidity_events}
        || $self->{layers}{internal}{liquidity_events};
        $self->{show_fvg} =
    $self->{layers}{external}{fvg}
    || $self->{layers}{internal}{fvg};

$self->{show_order_blocks} =
    $self->{layers}{external}{order_blocks}
    || $self->{layers}{internal}{order_blocks};
        
}

sub _build_layers_popup {
    my ($self) = @_;

    my $popup = $self->{layers_popup};

    my $frame = $popup->Frame(
        -relief      => 'solid',
        -borderwidth => 1,
        -background  => '#f5f5f5',
    )->pack(-fill => 'both', -expand => 1);

    $frame->Label(
        -text       => 'SMC Layers',
        -font       => ['Arial', 10, 'bold'],
        -background => '#f5f5f5',
    )->grid(
        -row => 0,
        -column => 0,
        -padx => 8,
        -pady => 5,
        -sticky => 'w',
    );

    $frame->Label(
        -text       => 'Internal',
        -font       => ['Arial', 9, 'bold'],
        -background => '#f5f5f5',
    )->grid(-row => 0, -column => 1, -padx => 10);

    $frame->Label(
        -text       => 'External',
        -font       => ['Arial', 9, 'bold'],
        -background => '#f5f5f5',
    )->grid(-row => 0, -column => 2, -padx => 10);

    my @rows = (
        ['zigzag',           'ZigZag'],
        ['labels',           'HH HL LH LL'],
        ['bos',              'BOS'],
        ['choch',            'CHoCH'],
        ['bsl',              'BSL'],
        ['ssl',              'SSL'],
        ['eqh',              'EQH'],
        ['eql',              'EQL'],
        ['liquidity_events', 'Sweep / Grab / Run'],
    );

    my $r = 1;

    for my $item (@rows) {
        my ($key, $label) = @$item;

        $frame->Label(
            -text       => $label,
            -background => '#f5f5f5',
        )->grid(
            -row => $r,
            -column => 0,
            -sticky => 'w',
            -padx => 8,
            -pady => 2,
        );

        $frame->Checkbutton(
            -variable   => \$self->{layers}{internal}{$key},
            -background => '#f5f5f5',
            -command    => sub {
                $self->_sync_layer_flags();
                $self->draw();
            },
        )->grid(-row => $r, -column => 1);

        $frame->Checkbutton(
            -variable   => \$self->{layers}{external}{$key},
            -background => '#f5f5f5',
            -command    => sub {
                $self->_sync_layer_flags();
                $self->draw();
            },
        )->grid(-row => $r, -column => 2);

        $r++;
    }

    $frame->Button(
        -text    => 'Ocultar todo',
        -command => sub {
            for my $scope (qw(internal external)) {
                for my $key (keys %{$self->{layers}{$scope}}) {
                    $self->{layers}{$scope}{$key} = 0;
                }
            }

            $self->_sync_layer_flags();
            $self->draw();
        },
    )->grid(
        -row => $r,
        -column => 0,
        -columnspan => 3,
        -sticky => 'we',
        -padx => 8,
        -pady => [8, 3],
    );
}


1;
