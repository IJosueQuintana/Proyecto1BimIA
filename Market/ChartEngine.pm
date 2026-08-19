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
        show_external_fibonacci =>
            0,
        show_bos   => 0,
        show_choch => 0,


       layers_panel_visible => 0,
        layers_panel         => undef,
        indicators_popup => undef,
        layers => {

            internal => {
                zigzag => 0,
                labels => 0,
                bos    => 0,
                choch  => 0,

                fvg          => 0,
                order_blocks => 0,
                
            },

            external => {
                zigzag => 0,
                labels => 0,
                bos    => 0,
                choch  => 0,
                fibonacci => 0,

                bsl => 0,
                ssl => 0,

                liquidity_events => 0,

                fvg          => 0,
                order_blocks => 0,
                 supply_demand   => 0,
            },

            # EQH/EQL no son internos ni externos.
            # Son una estructura independiente, igual que en LuxAlgo.
            equal => {
                eqh => 0,
                eql => 0,
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
        show_supply_demand => 0,

        # ============================================================
        # ANCHORED VWAP
        # ============================================================

        show_anchored_vwap => 0,

        # MANUAL, SESSION, DAY, WEEK o MONTH
        vwap_anchor_mode => 'MANUAL',

        # Índice elegido por el usuario en modo MANUAL.
        vwap_anchor_index => undef,

        # Indica que el próximo clic sobre el gráfico seleccionará el ancla.
        vwap_selecting_anchor => 0,

        # Precio utilizado:
        # HLC3 = (high + low + close) / 3
        vwap_price_source => 'HLC3',

        # Bandas de desviación estándar.
        show_vwap_band_1 => 1,
        show_vwap_band_2 => 0,
        show_vwap_band_3 => 0,

        vwap_band_mult_1 => 1.0,
        vwap_band_mult_2 => 2.0,
        vwap_band_mult_3 => 3.0,

        # ============================================================
        # CACHE DEL VWAP
        # ============================================================

        vwap_cache => undef,

        vwap_cache_anchor => undef,
        vwap_cache_until  => undef,
        vwap_cache_mode   => undef,

                    # ============================================================
        # VOLUME PROFILE
        # ============================================================

        show_volume_profile => 0,

        # Cantidad de filas o niveles de precio utilizados para
        # construir el histograma del perfil de volumen.
        volume_profile_rows => 48,

        # Porcentaje del volumen total que debe pertenecer al
        # área de valor. El valor 0.70 representa el 70 %.
        volume_profile_value_area => 0.70,

        # ============================================================
        # MODO DEL VOLUME PROFILE
        # ============================================================

        # Modos disponibles:
        #
        # VISIBLE:
        #   Utiliza únicamente las velas visibles actualmente.
        #
        # SESSION:
        #   Utiliza las velas pertenecientes a la sesión actual.
        #
        # BOS_CHOCH:
        #   Utiliza como ancla el último evento estructural
        #   BOS o CHoCH confirmado.
        #
        # HISTORICAL:
        #   Utiliza una cantidad fija de velas históricas.
        volume_profile_mode => 'VISIBLE',

        # Índice inicial utilizado por los modos que requieren
        # un punto de anclaje, principalmente BOS_CHOCH.
        volume_profile_anchor_index => undef,

        # Conserva el ancla estructural anterior. Esto permitirá
        # limitar el perfil entre dos eventos BOS/CHoCH consecutivos
        # cuando se implemente ese comportamiento.
        volume_profile_previous_anchor_index => undef,

        # Tipo del evento que produjo el anclaje.
        # Sus valores podrán ser: BOS, CHOCH o undef.
        volume_profile_anchor_type => undef,

        # Alcance estructural del evento utilizado como ancla.
        # Sus valores podrán ser: internal, external o undef.
        volume_profile_anchor_scope => undef,

        # Última vela que puede utilizar el perfil.
        # En Replay evita que se utilicen velas futuras.
        volume_profile_until_index => undef,

        # Cantidad de velas utilizadas por el modo HISTORICAL.
        volume_profile_historical_bars => 500,

        # ============================================================
        # CACHE DEL VOLUME PROFILE
        # ============================================================

        volume_profile_cache       => undef,
        volume_profile_cache_first => undef,
        volume_profile_cache_last  => undef,

        # También se guardará el modo con el cual se construyó
        # el caché para evitar reutilizar un perfil de otro modo.
        volume_profile_cache_mode => undef,

        # Resultados principales del perfil.
        volume_profile_poc => undef,
        volume_profile_vah => undef,
        volume_profile_val => undef,
        volume_profile_max => undef,

        show_volume_pivots => 0,    

        price_panel => Market::Panels::PricePanel->new(),
        atr_panel   => Market::Panels::ATRPanel->new(),

        internal_zigzag_tf  => 60,
        internal_zigzag_prd => 2,

        # Longitud interna utilizada por el indicador SMC.
        internal_smc_len    => 5,

        equal_smc_len => 3,

        external_swing_len  => 150,

        liquidity_engine => Market::Indicators::Liquidity->new(
        atr_mult             => 4.0,
        minor_atr_mult       => 1.5,
        confirm_bars         => 3,

        # ZigZag interno MTF configurable.
        internal_zigzag_tf   => 60,
        internal_zigzag_prd  => 2,

        # Estructura interna SMC del timeframe activo.
        internal_smc_len     => 5,

        equal_smc_len => 3,
        eq_tolerance => 0.10,

        external_swing_len   => 150,
        supply_demand_require_volume => 0,
    ),

        smc_external_engine => Market::Indicators::SMC_Structures->new(
            prefix => '',
            mode   => 'external',
        ),

        # Motor exclusivamente visual para el ZigZag interno MTF
        # y sus etiquetas HH/HL/LH/LL.
        smc_internal_visual_engine => Market::Indicators::SMC_Structures->new(
            prefix => 'i',
            mode   => 'internal',
        ),

        smc_internal_engine => Market::Indicators::SMC_Structures->new(
            prefix => 'i',
            mode   => 'internal',
            internal_confluence => 0
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
        last_smc_external        => undef,

        # ZigZag interno MTF visible.
        last_smc_internal_visual => undef,

        # Eventos internos iBOS/iCHoCH del timeframe activo.
        last_smc_internal        => undef,

        replay_mode      => 0,
        replay_selecting => 0,
        replay_index     => undef,
        replay_after     => undef,
        replay_speed => 300,
        # Indica que el Replay automático está ejecutándose.
        replay_playing => 0,

        # Durante Play, los indicadores estructurales pesados
        # se actualizan cada N velas.
        #
        # Las velas siguen avanzando una por una.
        replay_indicator_stride => 10,

        # Última vela donde se hizo un cálculo estructural completo.
        replay_last_heavy_index => undef,
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
        # ==========================================================
    # POPUP DE INDICADORES
    # Anchored VWAP y Volume Profile
    # ==========================================================

    my $indicators_display = $top->Button(
        -text  => 'Indicadores',
        -width => 11,
    )->pack(
        -side => 'left',
        -padx => 4,
    );

    $self->{indicators_button} = $indicators_display;

    $self->{indicators_popup} = $mw->Toplevel();
    $self->{indicators_popup}->withdraw();
    $self->{indicators_popup}->overrideredirect(1);

    $self->_build_indicators_popup();

    $indicators_display->configure(
        -command => sub {

            if (
                $self->{indicators_popup}->state
                eq 'withdrawn'
            ) {
                # Cerrar Layers para evitar dos menús
                # flotantes abiertos simultáneamente.
                if (
                    $self->{layers_popup}
                    && $self->{layers_popup}->state ne 'withdrawn'
                ) {
                    $self->{layers_popup}->withdraw();
                }

                my $x =
                    $indicators_display->rootx;

                my $y =
                    $indicators_display->rooty
                    +
                    $indicators_display->height;

                $self->{indicators_popup}->geometry(
                    "+$x+$y"
                );

                $self->{indicators_popup}->deiconify();
                $self->{indicators_popup}->raise();
            }
            else {
                $self->{indicators_popup}->withdraw();
            }
        },
    );
    
        $layers_display->configure(
        -command => sub {

            if ($self->{layers_popup}->state eq 'withdrawn') {

                # Cerrar Indicadores antes de abrir Layers.
                if (
                    $self->{indicators_popup}
                    && $self->{indicators_popup}->state ne 'withdrawn'
                ) {
                    $self->{indicators_popup}->withdraw();
                }

                my $x = $layers_display->rootx;
                my $y =
                    $layers_display->rooty
                    +
                    $layers_display->height;

                $self->{layers_popup}->geometry("+$x+$y");
                $self->{layers_popup}->deiconify();
                $self->{layers_popup}->raise();
            }
            else {
                $self->{layers_popup}->withdraw();
            }
        },
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
        $self->{replay_last_heavy_index} = undef;
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

        # ==========================================================
    # NAVEGACIÓN Y REPLAY COMPACTOS
    # ==========================================================

    $top->Button(
        -text    => '|<',
        -width   => 3,
        -command => sub {
            $self->go_to_start();
        },
    )->pack(
        -side => 'left',
        -padx => 1,
    );

    $top->Button(
        -text    => '>|',
        -width   => 3,
        -command => sub {
            $self->go_to_end();
        },
    )->pack(
        -side => 'left',
        -padx => 1,
    );

    $top->Button(
        -text    => 'R',
        -width   => 3,
        -command => sub {
            $self->replay_select_start();
        },
    )->pack(
        -side => 'left',
        -padx => 1,
    );

    $top->Button(
        -text    => '>',
        -width   => 3,
        -command => sub {
            $self->replay_play();
        },
    )->pack(
        -side => 'left',
        -padx => 1,
    );

    $top->Button(
        -text    => '||',
        -width   => 3,
        -command => sub {
            $self->replay_pause();
        },
    )->pack(
        -side => 'left',
        -padx => 1,
    );

    $top->Button(
        -text    => '>>',
        -width   => 3,
        -command => sub {
            $self->replay_step(1);
        },
    )->pack(
        -side => 'left',
        -padx => 1,
    );

    $top->Button(
        -text    => '<<',
        -width   => 3,
        -command => sub {
            $self->replay_step(-1);
        },
    )->pack(
        -side => 'left',
        -padx => 1,
    );

    $top->Button(
        -text    => 'ER',
        -width   => 4,
        -command => sub {
            $self->replay_exit();
        },
    )->pack(
        -side => 'left',
        -padx => 1,
    );

    $top->Button(
        -text    => 'V',
        -width   => 3,
        -command => sub {
            $self->{show_volume_pivots} =
                !$self->{show_volume_pivots};

            $self->draw();
        },
    )->pack(
        -side => 'left',
        -padx => 1,
    );


    




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

# ==========================================================
# PRECÁLCULO ESTRUCTURAL INICIAL
#
# La aplicación puede tardar al iniciar, pero después todas
# las capas reutilizan estos resultados y deben activarse
# prácticamente de inmediato.
# ==========================================================
my $initial_until =
    $self->{market}->last_index();

if (
    defined $initial_until
    &&
    $initial_until >= 0
) {
    print ">>> Calculando estructura inicial...\n";

    $self->update_smc_overlay(
        $initial_until
    );

    print ">>> Estructura inicial lista.\n";
}

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
    $self->{replay_last_heavy_index} = undef;
    $self->{indicators}->reset_all();
    $self->{indicators}->update_last($self->{market});
    $self->{locked_index} = undef;
    $self->{lock_y_on_zoom} = 0;
    # Las velas cambiaron de temporalidad.
    $self->invalidate_vwap_cache();
    $self->invalidate_volume_profile_cache();
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

        # ==========================================================
    # OPTIMIZACIÓN DEL REPLAY AUTOMÁTICO
    #
    # Durante Play no reconstruimos toda la estructura en cada
    # vela. Reutilizamos el último resultado durante unas pocas
    # velas y actualizamos periódicamente.
    #
    # Al pausar o avanzar manualmente, replay_playing será 0 y
    # el cálculo se realizará exactamente en la vela solicitada.
    # ==========================================================
    if (
        $self->{replay_mode}
        &&
        $self->{replay_playing}
        &&
        defined $self->{replay_last_heavy_index}
    ) {
        my $stride =
            $self->{replay_indicator_stride}
            // 5;

        $stride = 1
            if $stride < 1;

        my $distance =
            abs(
                $until_index
                -
                $self->{replay_last_heavy_index}
            );

        return
            if $distance < $stride;
    }

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

    # Siempre permanece en 5 para imitar la estructura interna
    # del indicador sobre la temporalidad activa.
    $self->{liquidity_engine}->{internal_smc_len} =
        $self->{internal_smc_len} // 5;

    $self->{liquidity_engine}->{equal_smc_len} =
    $self->{equal_smc_len} // 3;

    $self->{liquidity_engine}->{external_swing_len} =
        $self->{external_swing_len} // 150;

    my $cache_key = join(
        ':',
        $tf,
        $until_index,

        # ZigZag interno visual.
        $self->{internal_zigzag_tf} // 60,
        $self->{internal_zigzag_prd} // 2,

        # Estructura SMC interna.
        $self->{internal_smc_len} // 5,
        $self->{equal_smc_len} // 3,
        $self->{liquidity_engine}->{eq_tolerance} // 0.10,

        # Estructura externa.
        $self->{external_swing_len} // 150,
                $self->{liquidity_engine}
            ->{supply_demand_volume_lookback}
            // 20,

        $self->{liquidity_engine}
            ->{supply_demand_volume_mult}
            // 1.5,

        $self->{liquidity_engine}
            ->{supply_demand_range_atr_min}
            // 0.80,

        $self->{liquidity_engine}
            ->{supply_demand_box_width}
            // 2.5,

        $self->{liquidity_engine}
            ->{supply_demand_overlap_atr_mult}
            // 2.0,
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
        $market,
        until_index => $until_index,
    );
    # Resultado exclusivamente visual del ZigZag interno MTF.
    my $smc_internal_visual =
        $self->{smc_internal_visual_engine}->calculate(
            $liq_result->{internal_structure},
            $market,
            until_index => $until_index,
        );

    # Preparamos los niveles swing externos para replicar:
    #
    # internalHigh.currentLevel != swingHigh.currentLevel
    # internalLow.currentLevel  != swingLow.currentLevel
    #
    # del indicador TradingView.
    my %external_highs;
    my %external_lows;

    for my $pivot (@{$liq_result->{external_structure} || []}) {
        next if !$pivot;
        next if !defined $pivot->{price};
        next if !defined $pivot->{type};

        if ($pivot->{type} eq 'HIGH') {
            $external_highs{$pivot->{price}} = 1;
        }
        elsif ($pivot->{type} eq 'LOW') {
            $external_lows{$pivot->{price}} = 1;
        }
    }

    my $smc_internal = $self->{smc_internal_engine}->calculate(
    $liq_result->{internal_smc_structure},
    $market,

    until_index    => $until_index,
    external_highs => \%external_highs,
    external_lows  => \%external_lows,  
    );

    $self->{last_liq_result}          = $liq_result;
    $self->{last_smc_external}        = $smc_external;
    $self->{last_smc_internal_visual} = $smc_internal_visual;
    $self->{last_smc_internal}        = $smc_internal;
    #$self->_print_audit_summary($liq_result, $smc_external, $smc_internal, $market);

    # Se mantiene por compatibilidad con auditoría y ML.
    # Para ML seguimos usando estructura externa.
    $self->{last_smc_result} = $smc_external;

    $self->{liquidity_overlay}->set_result($liq_result);
    $self->{smc_overlay}->set_result($smc_external);

        $self->{smc_cache_key} = $cache_key;

    # Registrar la última vela donde sí se reconstruyeron
    # completamente Liquidity y SMC.
    $self->{replay_last_heavy_index} =
        $until_index;
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

    # ========================================================
    # ANCHORED VWAP
    # Se dibuja después de las velas y después de resolver
    # la escala vertical, pero antes de los overlays SMC.
    # ========================================================
    if ($self->{show_anchored_vwap}) {
        $self->_draw_anchored_vwap(
            canvas      => $c,
            start       => $start,
            end         => $end,
            x_of        => $x_of,
            state       => \%state,
            price_panel => $self->{price_panel},
        );
    }

        

    
    #use Data::Dump qw(dump);

    #print dump(\%state);
    

    my $calc_until = $self->{replay_mode}
    ? $self->{replay_index}
    : $self->{market}->last_index();

    my $needs_smc_or_liquidity =
       (
            $self->{show_volume_profile}
            &&
            uc(
                $self->{volume_profile_mode}
                //
                'VISIBLE'
            ) eq 'BOS_CHOCH'
       )

    || $self->{show_external_zigzag}
    || $self->{show_external_labels}
        || $self->{show_external_fibonacci}
    || $self->{show_internal_zigzag}
    || $self->{show_internal_labels}

    # BOS / CHoCH
    || $self->{layers}{external}{bos}
    || $self->{layers}{external}{choch}
    || $self->{layers}{internal}{bos}
    || $self->{layers}{internal}{choch}

    # Liquidez
    || $self->{show_bsl}
    || $self->{show_ssl}
    || $self->{show_eqh}
    || $self->{show_eql}
    || $self->{show_volume_pivots}

    # FVG y Order Blocks deben poder calcularse y mostrarse
    # independientemente de que el ZigZag esté visible.
    || $self->{show_fvg}
    || $self->{show_order_blocks}
    || $self->{show_supply_demand};

    $self->update_smc_overlay($calc_until) if $needs_smc_or_liquidity;

        # ========================================================
        # VOLUME PROFILE
        #
        # Se dibuja después de actualizar SMC para que el modo
        # BOS_CHOCH utilice los eventos estructurales confirmados
        # correspondientes a la vela actual.
        # ========================================================
        if ($self->{show_volume_profile}) {
            $self->_draw_volume_profile(
                canvas      => $c,
                start       => $start,
                end         => $end,
                state       => \%state,
                price_panel => $self->{price_panel},
            );
        }

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
        # ========================================================
    # FIBONACCI DEL ÚLTIMO TRAMO EXTERNO
    # ========================================================
    if ($self->{show_external_fibonacci}) {
        $self->{smc_overlay}->draw_external_fibonacci(
            $c,
            $start,
            $end,
            $x_of,
            \%state,
            $self->{price_panel},

            $self->{last_liq_result}
                ? $self->{last_liq_result}
                    ->{external_fibonacci}
                : undef,
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
            result => $self->{last_smc_internal_visual},
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

            # Fuera de Replay: últimos 3 FVG detectadoss.
            history_limit => 3,

            # En Replay: únicamente los FVG activos en ese punto.
            replay_mode => $self->{replay_mode} ? 1 : 0,
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

        if (
        $self->{show_bsl}
        || $self->{show_ssl}
        || $self->{show_eqh}
        || $self->{show_eql}
        || $self->{show_liquidity_events}
        || $self->{show_supply_demand}
    ) {
        # Es indispensable enviar SIEMPRE todos los flags.
        # Así el overlay no conserva valores de una selección anterior.
        $self->{liquidity_overlay}->{show_bsl} =
            $self->{show_bsl} ? 1 : 0;

        $self->{liquidity_overlay}->{show_ssl} =
            $self->{show_ssl} ? 1 : 0;

        $self->{liquidity_overlay}->{show_eqh} =
            $self->{show_eqh} ? 1 : 0;

        $self->{liquidity_overlay}->{show_eql} =
            $self->{show_eql} ? 1 : 0;

        $self->{liquidity_overlay}->{show_liquidity_events} =
            $self->{show_liquidity_events} ? 1 : 0;

        $self->{liquidity_overlay}->{show_supply_demand} =
            $self->{show_supply_demand} ? 1 : 0;


        $self->{liquidity_overlay}->draw(
            $c,
            $start,
            $end,
            $x_of,
            \%state,
            $self->{price_panel},
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

    # ========================================================
    # SELECCIÓN DEL INICIO DEL REPLAY
    # ========================================================
    if ($self->{replay_selecting}) {
        my $idx = $self->x_to_index($x);

        $self->replay_start_at($idx);

        return;
    }

    # ========================================================
    # SELECCIÓN MANUAL DEL ANCLA VWAP
    # ========================================================
    if ($self->{vwap_selecting_anchor}) {
        my $idx = $self->x_to_index($x);

        my $until_index =
            $self->_current_until_index();

        $idx = 0
            if $idx < 0;

        $idx = $until_index
            if $idx > $until_index;

        $self->set_vwap_anchor_index($idx);

        print STDERR
            ">>> VWAP ANCHOR SELECTED: index=$idx\n";

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
    $self->invalidate_vwap_cache();
    $self->invalidate_volume_profile_cache();

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
        $self->{replay_playing}          = 0;
    $self->{replay_last_heavy_index} = undef;
    $self->{smc_cache_key}           = undef;
    $self->invalidate_vwap_cache();
    $self->invalidate_volume_profile_cache();
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
        $self->{replay_playing}          = 0;
    $self->{replay_last_heavy_index} = undef;
    $self->{smc_cache_key}           = undef;
    $self->invalidate_vwap_cache();
    $self->invalidate_volume_profile_cache();
    $self->fit_all();
    $self->draw();
}

sub replay_pause {
    my ($self) = @_;

    my $was_playing =
        $self->{replay_playing}
        ? 1
        : 0;

    $self->{replay_playing} = 0;

    if (defined $self->{replay_after}) {
        $self->{mw}->afterCancel(
            $self->{replay_after}
        );

        $self->{replay_after} = undef;
    }

    return
        if !$self->{replay_mode};

    # Al detener el Replay hacemos un cálculo exacto en la
    # vela actual, incluso si durante Play se reutilizó una
    # estructura calculada unas velas atrás.
    if ($was_playing) {
        $self->{replay_last_heavy_index} = undef;
        $self->{smc_cache_key}           = undef;

        $self->invalidate_vwap_cache();
        $self->invalidate_volume_profile_cache();

        $self->draw();
    }
}

sub replay_play {
    my ($self) = @_;

    return if !$self->{replay_mode};

    # Evitar dos temporizadores simultáneos.
    if (defined $self->{replay_after}) {
        $self->{mw}->afterCancel(
            $self->{replay_after}
        );

        $self->{replay_after} = undef;
    }

    $self->{replay_playing} = 1;

    # draw() decidirá si realmente existe algún indicador
    # estructural que necesite actualizarse.
    #
    # No llamamos directamente a update_smc_overlay(),
    # porque eso recalcularía SMC incluso sin capas activas.
    $self->draw();

    $self->_replay_schedule_next();
}

sub _replay_schedule_next {
    my ($self) = @_;

    return if !$self->{replay_mode};
    return if !$self->{replay_playing};

    $self->{replay_after} =
        $self->{mw}->after(
            $self->{replay_speed},

            sub {
                $self->{replay_after} = undef;

                return
                    if !$self->{replay_mode};

                return
                    if !$self->{replay_playing};

                my $last =
                    $self->{market}->last_index();

                if (
                    $self->{replay_index}
                    >=
                    $last
                ) {
                    $self->replay_pause();
                    return;
                }

                # Segundo argumento = llamada automática.
                $self->replay_step(1, 1);

                $self->_replay_schedule_next()
                    if $self->{replay_playing};
            }
        );
}

sub replay_step {
    my (
        $self,
        $dir,
        $from_auto,
    ) = @_;

    return if !$self->{replay_mode};

    $dir //= 1;
    $from_auto //= 0;

    my $last =
        $self->{market}->last_index();

    my $previous_index =
        $self->{replay_index};

    $self->{replay_index} +=
        $dir;

    $self->{replay_index} = 0
        if $self->{replay_index} < 0;

    $self->{replay_index} = $last
        if $self->{replay_index} > $last;

    return
        if defined $previous_index
        &&
        $self->{replay_index}
            ==
        $previous_index;

    # ==========================================================
    # PASO MANUAL
    #
    # Step+, Step- o cualquier movimiento manual debe mostrar
    # indicadores exactos inmediatamente.
    # ==========================================================
    if (!$from_auto) {
        $self->{replay_playing}         = 0;
        $self->{replay_last_heavy_index} = undef;
        $self->{smc_cache_key}           = undef;

        $self->invalidate_vwap_cache();
        $self->invalidate_volume_profile_cache();
    }
    else {
        # En reproducción automática, VWAP y Volume Profile
        # también se actualizan con la misma frecuencia que
        # los indicadores pesados.
        my $stride =
            $self->{replay_indicator_stride}
            // 5;

        $stride = 1
            if $stride < 1;

        my $must_refresh =
            !defined
                $self->{replay_last_heavy_index}
            ||
            abs(
                $self->{replay_index}
                -
                $self->{replay_last_heavy_index}
            ) >= $stride;

        if ($must_refresh) {
            $self->invalidate_vwap_cache();
            $self->invalidate_volume_profile_cache();
        }
    }

    $self->_replay_apply_window();
    $self->draw();

    $self->audit_replay_state()
        if $self->{debug_replay};
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
    $self->{replay_last_heavy_index} = undef;

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
            for my $scope (qw(internal external equal)) {
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

    # ==========================================================
    # ESTRUCTURA INTERNA
    # ==========================================================
    $self->{show_internal_zigzag} =
        $self->{layers}{internal}{zigzag} // 0;

    $self->{show_internal_labels} =
        $self->{layers}{internal}{labels} // 0;

    # ==========================================================
    # ESTRUCTURA EXTERNA
    # ==========================================================
    $self->{show_external_zigzag} =
        $self->{layers}{external}{zigzag} // 0;

    $self->{show_external_labels} =
        $self->{layers}{external}{labels} // 0;
         $self->{show_external_fibonacci} =
        $self->{layers}{external}{fibonacci}
        // 0;

    # ==========================================================
    # BOS / CHoCH
    # ==========================================================
    $self->{show_bos} =
           ($self->{layers}{external}{bos} // 0)
        || ($self->{layers}{internal}{bos} // 0);

    $self->{show_choch} =
           ($self->{layers}{external}{choch} // 0)
        || ($self->{layers}{internal}{choch} // 0);

    # ==========================================================
    # LIQUIDEZ EXTERNA
    # BSL / SSL / Sweep / Grab / Run
    # ==========================================================
    $self->{show_bsl} =
        $self->{layers}{external}{bsl} // 0;

    $self->{show_ssl} =
        $self->{layers}{external}{ssl} // 0;

    $self->{show_liquidity_events} =
        $self->{layers}{external}{liquidity_events} // 0;

    # ==========================================================
    # EQH / EQL
    # Capa independiente
    # ==========================================================
    $self->{show_eqh} =
        $self->{layers}{equal}{eqh} // 0;

    $self->{show_eql} =
        $self->{layers}{equal}{eql} // 0;

    # ==========================================================
    # FVG / ORDER BLOCKS
    # ==========================================================
    $self->{show_fvg} =
           ($self->{layers}{external}{fvg} // 0)
        || ($self->{layers}{internal}{fvg} // 0);

    $self->{show_order_blocks} =
           ($self->{layers}{external}{order_blocks} // 0)
        || ($self->{layers}{internal}{order_blocks} // 0);
            $self->{show_supply_demand} =
        $self->{layers}{external}{supply_demand}
        // 0;
}

sub _refresh_structural_layers {
    my ($self) = @_;

    # Sincronizar los checkboxes con los flags usados por draw().
    $self->_sync_layer_flags();

    # ==========================================================
    # MODO NORMAL
    #
    # Las estructuras ya fueron precalculadas hasta la última vela.
    # Mostrar u ocultar una capa no requiere recalcular.
    # ==========================================================
    if (!$self->{replay_mode}) {
        $self->draw();
        return;
    }

    # ==========================================================
    # REPLAY
    #
    # Al activar la primera capa estructural durante Replay,
    # debemos asegurarnos de que exista un resultado calculado
    # exactamente hasta replay_index.
    #
    # No podemos reutilizar el precálculo del modo normal porque
    # contendría velas futuras.
    # ==========================================================
    my $replay_index =
        $self->{replay_index};

    if (!defined $replay_index) {
        $self->draw();
        return;
    }

    my $expected_prefix =
    join(
        ':',
        $self->{market}->{timeframe} // 1,
        $replay_index,
    ) . ':';

    my $cache_matches_replay =
        defined $self->{smc_cache_key}
        &&
        index(
            $self->{smc_cache_key},
            $expected_prefix
        ) == 0;

    # Solo invalidar si el resultado almacenado no corresponde
    # a la vela actual del Replay.
    if (!$cache_matches_replay) {
        $self->{smc_cache_key} = undef;
        $self->{replay_last_heavy_index} = undef;
    }

    $self->draw();
}


sub _build_layers_popup {


    my ($self) = @_;

    my $popup = $self->{layers_popup};

    my $frame = $popup->Frame(
        -relief      => 'solid',
        -borderwidth => 1,
        -background  => '#f5f5f5',
    )->pack(
        -fill   => 'both',
        -expand => 1,
    );

    # ==========================================================
    # TÍTULO
    # ==========================================================
    $frame->Label(
        -text       => 'SMC Layers',
        -font       => ['Arial', 10, 'bold'],
        -background => '#f5f5f5',
    )->grid(
        -row        => 0,
        -column     => 0,
        -columnspan => 3,
        -padx       => 8,
        -pady       => 6,
    );

    # ==========================================================
    # ENCABEZADOS
    # ==========================================================
    $frame->Label(
        -text       => 'Internal',
        -font       => ['Arial', 9, 'bold'],
        -background => '#f5f5f5',
    )->grid(
        -row    => 1,
        -column => 1,
        -padx   => 10,
    );

    $frame->Label(
        -text       => 'External',
        -font       => ['Arial', 9, 'bold'],
        -background => '#f5f5f5',
    )->grid(
        -row    => 1,
        -column => 2,
        -padx   => 10,
    );

    my @structure_rows = (
        ['zigzag', 'ZigZag'],
        ['labels', 'HH HL LH LL'],
        ['bos',    'BOS'],
        ['choch',  'CHoCH'],
    );

    my $row = 2;

    # ==========================================================
    # ESTRUCTURA INTERNA / EXTERNA
    # ==========================================================
    for my $item (@structure_rows) {
        my ($key, $label) = @$item;

        $frame->Label(
            -text       => $label,
            -background => '#f5f5f5',
        )->grid(
            -row    => $row,
            -column => 0,
            -sticky => 'w',
            -padx   => 8,
            -pady   => 2,
        );

        $frame->Checkbutton(
            -variable   => \$self->{layers}{internal}{$key},
            -background => '#f5f5f5',
            -command => sub {
                $self->_refresh_structural_layers();
            },
        )->grid(
            -row    => $row,
            -column => 1,
        );

        $frame->Checkbutton(
            -variable   => \$self->{layers}{external}{$key},
            -background => '#f5f5f5',
            -command => sub {
                $self->_refresh_structural_layers();
            },
        )->grid(
            -row    => $row,
            -column => 2,
        );

        $row++;
    }

        # ==========================================================
    # FIBONACCI EXTERNO
    # ==========================================================
    $frame->Label(
        -text       => 'Fibonacci',
        -background => '#f5f5f5',
    )->grid(
        -row    => $row,
        -column => 0,
        -sticky => 'w',
        -padx   => 8,
        -pady   => 2,
    );

    # La columna interna queda vacía porque este Fibonacci
    # pertenece únicamente al ZigZag externo.
    $frame->Label(
        -text       => '',
        -background => '#f5f5f5',
    )->grid(
        -row    => $row,
        -column => 1,
    );

    $frame->Checkbutton(
        -variable =>
            \$self->{layers}{external}{fibonacci},

        -background =>
            '#f5f5f5',

        -command => sub {
            $self->_refresh_structural_layers();
        },
    )->grid(
        -row    => $row,
        -column => 2,
    );

    $row++;

    # ==========================================================
    # LIQUIDEZ EXTERNA
    # ==========================================================
    $frame->Label(
        -text       => 'External Liquidity',
        -font       => ['Arial', 9, 'bold'],
        -background => '#f5f5f5',
    )->grid(
        -row        => $row,
        -column     => 0,
        -columnspan => 3,
        -padx       => 8,
        -pady       => [8, 4],
    );

    $row++;

    my @external_liquidity_rows = (
        ['bsl',              'BSL'],
        ['ssl',              'SSL'],
        ['liquidity_events', 'Sweep / Grab / Run'],
    );

    for my $item (@external_liquidity_rows) {
        my ($key, $label) = @$item;

        $frame->Checkbutton(
            -text       => $label,
            -variable   => \$self->{layers}{external}{$key},
            -background => '#f5f5f5',
            -command => sub {
                $self->_refresh_structural_layers();
            },
        )->grid(
            -row        => $row,
            -column     => 0,
            -columnspan => 3,
            -sticky     => 'w',
            -padx       => 20,
            -pady       => 2,
        );

        $row++;
    }

    # ==========================================================
    # EQH / EQL INDEPENDIENTES
    # ==========================================================
    $frame->Label(
        -text       => 'Equal Highs / Lows',
        -font       => ['Arial', 9, 'bold'],
        -background => '#f5f5f5',
    )->grid(
        -row        => $row,
        -column     => 0,
        -columnspan => 3,
        -padx       => 8,
        -pady       => [8, 4],
    );

    $row++;

    my $equal_frame = $frame->Frame(
        -background => '#f5f5f5',
    );

    $equal_frame->grid(
        -row        => $row,
        -column     => 0,
        -columnspan => 3,
        -pady       => 2,
    );

    $equal_frame->Checkbutton(
        -text       => 'EQH',
        -variable   => \$self->{layers}{equal}{eqh},
        -background => '#f5f5f5',
        -command => sub {
            $self->_refresh_structural_layers();
        },
    )->pack(
        -side => 'left',
        -padx => 8,
    );

    $equal_frame->Checkbutton(
        -text       => 'EQL',
        -variable   => \$self->{layers}{equal}{eql},
        -background => '#f5f5f5',
        -command => sub {
            $self->_refresh_structural_layers();
        },
    )->pack(
        -side => 'left',
        -padx => 8,
    );

    $row++;
        # ==========================================================
    # FVG Y ORDER BLOCKS
    # ==========================================================

    $frame->Label(
        -text       => 'Imbalances',
        -font       => ['Arial', 9, 'bold'],
        -background => '#f5f5f5',
    )->grid(
        -row        => $row,
        -column     => 0,
        -columnspan => 3,
        -padx       => 8,
        -pady       => [8, 4],
    );

    $row++;


    $frame->Checkbutton(
        -text       => 'Supply / Demand',
        -variable   =>
            \$self->{layers}{external}
                {supply_demand},

        -background => '#f5f5f5',

        -command => sub {
            $self->_refresh_structural_layers();
        },

    )->grid(
        -row        => $row,
        -column     => 0,
        -columnspan => 3,
        -sticky     => 'w',
        -padx       => 20,
        -pady       => 2,
    );

    $row++;


    $frame->Checkbutton(
        -text       => 'FVG',
        -variable   => \$self->{layers}{external}{fvg},
        -background => '#f5f5f5',
        -command => sub {
            $self->_refresh_structural_layers();
        },

    )->grid(
        -row        => $row,
        -column     => 0,
        -columnspan => 3,
        -sticky     => 'w',
        -padx       => 20,
        -pady       => 2,
    );

    $row++;

    $frame->Checkbutton(
        -text       => 'Order Blocks',
        -variable   => \$self->{layers}{external}{order_blocks},
        -background => '#f5f5f5',
        -command => sub {
            $self->_refresh_structural_layers();
        },

    )->grid(
        -row        => $row,
        -column     => 0,
        -columnspan => 3,
        -sticky     => 'w',
        -padx       => 20,
        -pady       => 2,
    );

    $row++;

    # ==========================================================
    # BOTÓN OCULTAR TODO
    # ==========================================================
    $frame->Button(
        -text    => 'Ocultar todo',
        -command => sub {

            for my $scope (qw(internal external equal)) {
                next if !$self->{layers}{$scope};

                for my $key (keys %{$self->{layers}{$scope}}) {
                    $self->{layers}{$scope}{$key} = 0;
                }
            }
            $self->{show_anchored_vwap} = 0;
    $self->{vwap_selecting_anchor} = 0;
    $self->{show_volume_profile} = 0;

    $self->invalidate_volume_profile_cache();
    $self->invalidate_vwap_cache();

                $self->_refresh_structural_layers();
            },
        )->grid(
            -row        => $row,
            -column     => 0,
            -columnspan => 3,
            -sticky     => 'we',
            -padx       => 8,
            -pady       => [10, 5],
        );
}

sub _build_indicators_popup {
    my ($self) = @_;

    my $popup =
        $self->{indicators_popup};

    return if !$popup;

    my $frame = $popup->Frame(
        -relief      => 'solid',
        -borderwidth => 1,
        -background  => '#f5f5f5',
    )->pack(
        -fill   => 'both',
        -expand => 1,
    );

    my $row = 0;

    # ==========================================================
    # TÍTULO
    # ==========================================================

    $frame->Label(
        -text       => 'Indicadores',
        -font       => ['Arial', 10, 'bold'],
        -background => '#f5f5f5',
    )->grid(
        -row        => $row,
        -column     => 0,
        -columnspan => 3,
        -padx       => 8,
        -pady       => 6,
    );

    $row++;

    # ==========================================================
    # ANCHORED VWAP
    # ==========================================================

    $frame->Label(
        -text       => 'Anchored VWAP',
        -font       => ['Arial', 9, 'bold'],
        -background => '#f5f5f5',
    )->grid(
        -row        => $row,
        -column     => 0,
        -columnspan => 3,
        -padx       => 8,
        -pady       => [4, 4],
    );

    $row++;

    $frame->Checkbutton(
        -text       => 'Mostrar VWAP',
        -variable   => \$self->{show_anchored_vwap},
        -background => '#f5f5f5',
        -command    => sub {
            $self->invalidate_vwap_cache();
            $self->draw();
        },
    )->grid(
        -row        => $row,
        -column     => 0,
        -columnspan => 3,
        -sticky     => 'w',
        -padx       => 18,
        -pady       => 2,
    );

    $row++;

    # ==========================================================
    # SELECTOR DEL MODO VWAP
    # ==========================================================

    $frame->Label(
        -text       => 'Modo VWAP',
        -background => '#f5f5f5',
    )->grid(
        -row    => $row,
        -column => 0,
        -sticky => 'w',
        -padx   => 8,
        -pady   => 2,
    );

    my $vwap_mode_display =
        $frame->Button(
            -text  =>
                $self->{vwap_anchor_mode}
                //
                'MANUAL',
            -width => 12,
        );

    $vwap_mode_display->grid(
        -row        => $row,
        -column     => 1,
        -columnspan => 2,
        -sticky     => 'we',
        -padx       => 4,
        -pady       => 2,
    );

    my $vwap_mode_popup =
        $self->{mw}->Toplevel();

    $vwap_mode_popup->withdraw();
    $vwap_mode_popup->overrideredirect(1);

    my @vwap_modes = qw(
        MANUAL
        DAY
        WEEK
        MONTH
    );

    my $vwap_mode_list =
        $vwap_mode_popup->Listbox(
            -height          => scalar(@vwap_modes),
            -width           => 12,
            -exportselection => 0,
        )->pack(
            -fill   => 'both',
            -expand => 1,
        );

    for my $mode (@vwap_modes) {
        $vwap_mode_list->insert(
            'end',
            $mode
        );
    }

    $vwap_mode_display->configure(
        -command => sub {

            if (
                $vwap_mode_popup->state
                eq 'withdrawn'
            ) {
                my $x =
                    $vwap_mode_display->rootx;

                my $y =
                    $vwap_mode_display->rooty
                    +
                    $vwap_mode_display->height;

                $vwap_mode_popup->geometry(
                    "+$x+$y"
                );

                $vwap_mode_popup->deiconify();
                $vwap_mode_popup->raise();
            }
            else {
                $vwap_mode_popup->withdraw();
            }
        },
    );

    $vwap_mode_list->bind(
        '<<ListboxSelect>>' => sub {

            my @selection =
                $vwap_mode_list->curselection;

            return if !@selection;

            my $mode =
                $vwap_modes[
                    $selection[0]
                ];

            $self->set_vwap_anchor_mode(
                $mode
            );

            $vwap_mode_display->configure(
                -text => $mode
            );

            $self->{show_anchored_vwap} = 1;

            $vwap_mode_popup->withdraw();

            $self->draw();
        },
    );

    $row++;

    # ==========================================================
    # ANCLA MANUAL
    # ==========================================================

    $frame->Label(
        -text       => 'Ancla manual',
        -background => '#f5f5f5',
    )->grid(
        -row    => $row,
        -column => 0,
        -sticky => 'w',
        -padx   => 8,
        -pady   => 2,
    );

    $frame->Button(
        -text    => 'Seleccionar vela',
        -command => sub {

            $self->{vwap_anchor_mode} =
                'MANUAL';

            $vwap_mode_display->configure(
                -text => 'MANUAL'
            );

            $self->{show_anchored_vwap} = 1;

            $self->start_vwap_anchor_selection();

            $self->{indicators_popup}->withdraw();
            $vwap_mode_popup->withdraw();

            print STDERR
                ">>> VWAP SELECT MODE: haga clic sobre una vela\n";

            $self->draw();
        },
    )->grid(
        -row        => $row,
        -column     => 1,
        -columnspan => 2,
        -sticky     => 'we',
        -padx       => 4,
        -pady       => 2,
    );

    $row++;

    # ==========================================================
    # BANDAS VWAP
    # ==========================================================

    $frame->Label(
        -text       => 'Bandas',
        -background => '#f5f5f5',
    )->grid(
        -row    => $row,
        -column => 0,
        -sticky => 'w',
        -padx   => 8,
        -pady   => 2,
    );

    my $bands_frame =
        $frame->Frame(
            -background => '#f5f5f5',
        );

    $bands_frame->grid(
        -row        => $row,
        -column     => 1,
        -columnspan => 2,
        -sticky     => 'w',
        -padx       => 4,
    );

    for my $band (
        [
            '±1',
            'show_vwap_band_1',
        ],
        [
            '±2',
            'show_vwap_band_2',
        ],
        [
            '±3',
            'show_vwap_band_3',
        ],
    ) {
        my ($label, $key) = @{$band};

        $bands_frame->Checkbutton(
            -text       => $label,
            -variable   => \$self->{$key},
            -background => '#f5f5f5',
            -command    => sub {
                $self->draw();
            },
        )->pack(
            -side => 'left',
            -padx => 2,
        );
    }

    $row++;

    # ==========================================================
    # VOLUME PROFILE
    # ==========================================================

    $frame->Label(
        -text       => 'Volume Profile',
        -font       => ['Arial', 9, 'bold'],
        -background => '#f5f5f5',
    )->grid(
        -row        => $row,
        -column     => 0,
        -columnspan => 3,
        -padx       => 8,
        -pady       => [10, 4],
    );

    $row++;

    $frame->Checkbutton(
        -text       => 'Mostrar Volume Profile',
        -variable   => \$self->{show_volume_profile},
        -background => '#f5f5f5',
        -command    => sub {
            $self->invalidate_volume_profile_cache();
            $self->draw();
        },
    )->grid(
        -row        => $row,
        -column     => 0,
        -columnspan => 3,
        -sticky     => 'w',
        -padx       => 18,
        -pady       => 2,
    );

    $row++;

    # ==========================================================
    # SELECTOR DE MODO VOLUME PROFILE
    # ==========================================================

    $frame->Label(
        -text       => 'Modo Profile',
        -background => '#f5f5f5',
    )->grid(
        -row    => $row,
        -column => 0,
        -sticky => 'w',
        -padx   => 8,
        -pady   => 2,
    );

    my $profile_mode_display =
        $frame->Button(
            -text  =>
                $self->{volume_profile_mode}
                //
                'VISIBLE',
            -width => 12,
        );

    $profile_mode_display->grid(
        -row        => $row,
        -column     => 1,
        -columnspan => 2,
        -sticky     => 'we',
        -padx       => 4,
        -pady       => 2,
    );

    my $profile_mode_popup =
        $self->{mw}->Toplevel();

    $profile_mode_popup->withdraw();
    $profile_mode_popup->overrideredirect(1);

    my @profile_modes = qw(
        VISIBLE
        SESSION
        BOS_CHOCH
        HISTORICAL
    );

    my $profile_mode_list =
        $profile_mode_popup->Listbox(
            -height          => scalar(@profile_modes),
            -width           => 14,
            -exportselection => 0,
        )->pack(
            -fill   => 'both',
            -expand => 1,
        );

    for my $mode (@profile_modes) {
        $profile_mode_list->insert(
            'end',
            $mode
        );
    }

    $profile_mode_display->configure(
        -command => sub {

            if (
                $profile_mode_popup->state
                eq 'withdrawn'
            ) {
                my $x =
                    $profile_mode_display->rootx;

                my $y =
                    $profile_mode_display->rooty
                    +
                    $profile_mode_display->height;

                $profile_mode_popup->geometry(
                    "+$x+$y"
                );

                $profile_mode_popup->deiconify();
                $profile_mode_popup->raise();
            }
            else {
                $profile_mode_popup->withdraw();
            }
        },
    );

    $profile_mode_list->bind(
        '<<ListboxSelect>>' => sub {

            my @selection =
                $profile_mode_list->curselection;

            return if !@selection;

            my $mode =
                $profile_modes[
                    $selection[0]
                ];

            $self->{volume_profile_mode} =
                $mode;

            $self->{show_volume_profile} = 1;

            $profile_mode_display->configure(
                -text => $mode
            );

            $profile_mode_popup->withdraw();

            $self->invalidate_volume_profile_cache();
            $self->draw();
        },
    );

    $row++;

    # ==========================================================
    # CANTIDAD DE VELAS HISTÓRICAS
    # ==========================================================

    $frame->Label(
        -text       => 'Velas históricas',
        -background => '#f5f5f5',
    )->grid(
        -row    => $row,
        -column => 0,
        -sticky => 'w',
        -padx   => 8,
        -pady   => 2,
    );

    my @historical_options = (
        100,
        250,
        500,
        1000,
        2000,
    );

    my $historical_display =
        $frame->Button(
            -text  =>
                $self->{volume_profile_historical_bars}
                //
                500,
            -width => 12,
        );

    $historical_display->grid(
        -row        => $row,
        -column     => 1,
        -columnspan => 2,
        -sticky     => 'we',
        -padx       => 4,
        -pady       => 2,
    );

    my $historical_popup =
        $self->{mw}->Toplevel();

    $historical_popup->withdraw();
    $historical_popup->overrideredirect(1);

    my $historical_list =
        $historical_popup->Listbox(
            -height          => scalar(@historical_options),
            -width           => 12,
            -exportselection => 0,
        )->pack(
            -fill   => 'both',
            -expand => 1,
        );

    for my $bars (@historical_options) {
        $historical_list->insert(
            'end',
            $bars
        );
    }

    $historical_display->configure(
        -command => sub {

            if (
                $historical_popup->state
                eq 'withdrawn'
            ) {
                my $x =
                    $historical_display->rootx;

                my $y =
                    $historical_display->rooty
                    +
                    $historical_display->height;

                $historical_popup->geometry(
                    "+$x+$y"
                );

                $historical_popup->deiconify();
                $historical_popup->raise();
            }
            else {
                $historical_popup->withdraw();
            }
        },
    );

    $historical_list->bind(
        '<<ListboxSelect>>' => sub {

            my @selection =
                $historical_list->curselection;

            return if !@selection;

            my $bars =
                $historical_options[
                    $selection[0]
                ];

            $self->{volume_profile_historical_bars} =
                $bars;

            $historical_display->configure(
                -text => $bars
            );

            $historical_popup->withdraw();

            $self->invalidate_volume_profile_cache();
            $self->draw();
        },
    );

    $row++;

    # ==========================================================
    # OCULTAR INDICADORES
    # ==========================================================

    $frame->Button(
        -text => 'Ocultar indicadores',
        -command => sub {

            $self->{show_anchored_vwap} = 0;
            $self->{vwap_selecting_anchor} = 0;

            $self->{show_volume_profile} = 0;

            $self->invalidate_vwap_cache();
            $self->invalidate_volume_profile_cache();

            $self->draw();
        },
    )->grid(
        -row        => $row,
        -column     => 0,
        -columnspan => 3,
        -sticky     => 'we',
        -padx       => 8,
        -pady       => [10, 5],
    );
}

sub _current_until_index {
    my ($self) = @_;

    my $last_index = $self->{market}->last_index();

    # En Replay únicamente puede calcularse hasta la vela revelada.
    if (
        $self->{replay_mode}
        && defined $self->{replay_index}
        && $self->{replay_index} < $last_index
    ) {
        return $self->{replay_index};
    }

    return $last_index;
}


sub _vwap_period_key {
    my ($self, $candle, $mode) = @_;

    return undef if !$candle;
    return undef if !defined $candle->{epoch};

    my @time = localtime($candle->{epoch});

    my $year  = $time[5] + 1900;
    my $month = $time[4] + 1;
    my $day   = $time[3];
    my $wday  = $time[6];

    $mode = uc($mode // 'MANUAL');

    # SESSION y DAY utilizan por el momento la misma división:
    # cada nueva fecha inicia un nuevo VWAP.
    if ($mode eq 'SESSION' || $mode eq 'DAY') {
        return sprintf(
            '%04d-%02d-%02d',
            $year,
            $month,
            $day
        );
    }

    if ($mode eq 'WEEK') {

        # Perl:
        # 0 = domingo
        # 1 = lunes
        # ...
        # 6 = sábado
        #
        # Convertimos la fecha actual al lunes de su semana.
        my $days_from_monday = $wday == 0
            ? 6
            : $wday - 1;

        my $monday_epoch =
            $candle->{epoch}
            - ($days_from_monday * 86400);

        my @monday = localtime($monday_epoch);

        return sprintf(
            '%04d-%02d-%02d',
            $monday[5] + 1900,
            $monday[4] + 1,
            $monday[3]
        );
    }

    if ($mode eq 'MONTH') {
        return sprintf(
            '%04d-%02d',
            $year,
            $month
        );
    }

    return 'MANUAL';
}


sub _resolve_vwap_anchor_index {
    my ($self, $until_index) = @_;

    return undef if !defined $until_index;
    return undef if $until_index < 0;

    my $market = $self->{market};
    my $mode   = uc($self->{vwap_anchor_mode} // 'MANUAL');

    # --------------------------------------------------------
    # Ancla seleccionada manualmente
    # --------------------------------------------------------
    if ($mode eq 'MANUAL') {

        return undef
            if !defined $self->{vwap_anchor_index};

        return undef
            if $self->{vwap_anchor_index} > $until_index;

        return 0
            if $self->{vwap_anchor_index} < 0;

        return $self->{vwap_anchor_index};
    }

    # --------------------------------------------------------
    # Anclas automáticas
    # --------------------------------------------------------
    my $until_candle = $market->get_candle($until_index);

    return undef if !$until_candle;

    my $target_key =
        $self->_vwap_period_key(
            $until_candle,
            $mode
        );

    return undef if !defined $target_key;

    my $anchor_index = $until_index;

    # Recorrer hacia atrás hasta encontrar el inicio
    # del día, semana o mes actualmente activo.
    for (
        my $i = $until_index;
        $i >= 0;
        $i--
    ) {
        my $bar = $market->get_candle($i);

        last if !$bar;

        my $key =
            $self->_vwap_period_key(
                $bar,
                $mode
            );

        last
            if !defined $key
            || $key ne $target_key;

        $anchor_index = $i;
    }

    return $anchor_index;
}


sub _calculate_anchored_vwap {
    my ($self, %args) = @_;

    my $market = $self->{market};

    return [] if !$market;

    my $until_index = defined $args{until_index}
        ? $args{until_index}
        : $self->_current_until_index();

    my $market_last = $market->last_index();

    $until_index = $market_last
        if $until_index > $market_last;

    return [] if $until_index < 0;

    my $anchor_index = defined $args{anchor_index}
        ? $args{anchor_index}
        : $self->_resolve_vwap_anchor_index(
            $until_index
        );

    return [] if !defined $anchor_index;
    return [] if $anchor_index > $until_index;

        $anchor_index = 0
        if $anchor_index < 0;

    # Modo actual utilizado para validar el caché.
    my $current_mode =
        uc($self->{vwap_anchor_mode} // 'MANUAL');

    # Reutilizar el cálculo anterior si nada cambió.
    if (
        defined $self->{vwap_cache}
        && ref($self->{vwap_cache}) eq 'ARRAY'
        && defined $self->{vwap_cache_anchor}
        && defined $self->{vwap_cache_until}
        && defined $self->{vwap_cache_mode}
        && $self->{vwap_cache_anchor} == $anchor_index
        && $self->{vwap_cache_until} == $until_index
        && uc($self->{vwap_cache_mode}) eq $current_mode
    ) {
        return $self->{vwap_cache};
    }
    my $mult_1 =
        $self->{vwap_band_mult_1} // 1.0;

    my $mult_2 =
        $self->{vwap_band_mult_2} // 2.0;

    my $mult_3 =
        $self->{vwap_band_mult_3} // 3.0;

    my $sum_volume        = 0;
    my $sum_price_volume  = 0;
    my $sum_price2_volume = 0;

    my @values;

    for my $i ($anchor_index .. $until_index) {

        my $bar = $market->get_candle($i);

        next if !$bar;
        next if !defined $bar->{high};
        next if !defined $bar->{low};
        next if !defined $bar->{close};

        my $volume = defined $bar->{volume}
            ? $bar->{volume}
            : 0;

        # No incorporar volúmenes negativos.
        $volume = 0 if $volume < 0;

        # Igual que el VWAP del indicador DIY:
        # precio típico HLC3.
        my $typical_price = (
            $bar->{high}
            + $bar->{low}
            + $bar->{close}
        ) / 3;

        # Cuando no existe volumen, esa vela no altera
        # el acumulado. Esto evita divisiones por cero.
        if ($volume > 0) {
            $sum_volume += $volume;

            $sum_price_volume +=
                $typical_price
                * $volume;

            $sum_price2_volume +=
                $typical_price
                * $typical_price
                * $volume;
        }

        next if $sum_volume <= 0;

        my $vwap =
            $sum_price_volume
            / $sum_volume;

        my $variance =
            ($sum_price2_volume / $sum_volume)
            - ($vwap * $vwap);

        # Puede aparecer un pequeño valor negativo por
        # precisión numérica.
        $variance = 0
            if $variance < 0
            && abs($variance) < 0.0000001;

        $variance = 0
            if $variance < 0;

        my $stdev = sqrt($variance);

        push @values, {
            index => $i,

            anchor_index => $anchor_index,

            typical_price => $typical_price,
            volume        => $volume,

            cumulative_volume => $sum_volume,

            vwap     => $vwap,
            variance => $variance,
            stdev    => $stdev,

            upper_1 => $vwap + $stdev * $mult_1,
            lower_1 => $vwap - $stdev * $mult_1,

            upper_2 => $vwap + $stdev * $mult_2,
            lower_2 => $vwap - $stdev * $mult_2,

            upper_3 => $vwap + $stdev * $mult_3,
            lower_3 => $vwap - $stdev * $mult_3,

            price_above_vwap =>
                $bar->{close} >= $vwap
                    ? 1
                    : 0,

            distance_to_vwap =>
                $bar->{close} - $vwap,

            source => 'ANCHORED_VWAP',
        };
    }

    $self->{vwap_cache} = \@values;

    $self->{vwap_cache_anchor} = $anchor_index;
    $self->{vwap_cache_until}  = $until_index;
        $self->{vwap_cache_mode} =
        uc($self->{vwap_anchor_mode} // 'MANUAL');

    return $self->{vwap_cache};
}


sub _draw_vwap_series {
    my ($self, %args) = @_;

    my $canvas      = $args{canvas};
    my $values      = $args{values};
    my $field       = $args{field};
    my $color       = $args{color};
    my $width       = $args{width} // 1;
    my $dash        = $args{dash};
    my $start       = $args{start};
    my $end         = $args{end};
    my $x_of        = $args{x_of};
    my $state       = $args{state};
    my $price_panel = $args{price_panel};

    return if !$canvas;
    return if !$values;
    return if ref($values) ne 'ARRAY';
    return if !@$values;
    return if !$field;
    return if !$x_of;
    return if !$price_panel;

    my $scale = $price_panel->{scale};

    my @points;

    for my $point (@$values) {

        next if !$point;
        next if !defined $point->{index};
        next if !defined $point->{$field};

        my $index = $point->{index};

        # Mantener un punto adicional fuera de la vista
        # permite que la línea entre correctamente por el borde.
        next if $index < $start - 1;
        next if $index > $end + 1;

        my $local_index =
            $index - $start;

        my $x =
            $x_of->($local_index);

        my $y =
            $scale->price_to_y(
                $point->{$field},
                $state->{price_min},
                $state->{price_max},
                0,
                $state->{price_h}
            );

        next if !defined $x;
        next if !defined $y;

        # Si el valor queda fuera de la escala visible,
        # cortamos el segmento en lugar de pegarlo al borde.
        if (
            $y < 0
            || $y > $state->{price_h}
        ) {
            if (@points >= 4) {
                my @options = (
                    -fill  => $color,
                    -width => $width,
                );

                push @options, (
                    -dash => $dash
                ) if defined $dash;

                $canvas->createLine(
                    @points,
                    @options
                );
            }

            @points = ();
            next;
        }

        push @points, $x, $y;
    }

    if (@points >= 4) {
        my @options = (
            -fill  => $color,
            -width => $width,
        );

        push @options, (
            -dash => $dash
        ) if defined $dash;

        $canvas->createLine(
            @points,
            @options
        );
    }
}


sub _draw_anchored_vwap {
    my ($self, %args) = @_;

    return if !$self->{show_anchored_vwap};

    my $canvas      = $args{canvas};
    my $start       = $args{start};
    my $end         = $args{end};
    my $x_of        = $args{x_of};
    my $state       = $args{state};
    my $price_panel = $args{price_panel};

    return if !$canvas;
    return if !$x_of;
    return if !$state;
    return if !$price_panel;

    my $until_index =
        $self->_current_until_index();

    my $values =
        $self->_calculate_anchored_vwap(
            until_index => $until_index,
        );

    return if !$values;
    return if !@$values;

    # --------------------------------------------------------
    # VWAP principal
    # --------------------------------------------------------
    $self->_draw_vwap_series(
        canvas      => $canvas,
        values      => $values,
        field       => 'vwap',
        color       => '#2962ff',
        width       => 2,
        start       => $start,
        end         => $end,
        x_of        => $x_of,
        state       => $state,
        price_panel => $price_panel,
    );

    # --------------------------------------------------------
    # Primera desviación estándar
    # --------------------------------------------------------
    if ($self->{show_vwap_band_1}) {

        $self->_draw_vwap_series(
            canvas      => $canvas,
            values      => $values,
            field       => 'upper_1',
            color       => '#26a69a',
            width       => 1,
            dash        => '.',
            start       => $start,
            end         => $end,
            x_of        => $x_of,
            state       => $state,
            price_panel => $price_panel,
        );

        $self->_draw_vwap_series(
            canvas      => $canvas,
            values      => $values,
            field       => 'lower_1',
            color       => '#26a69a',
            width       => 1,
            dash        => '.',
            start       => $start,
            end         => $end,
            x_of        => $x_of,
            state       => $state,
            price_panel => $price_panel,
        );
    }

    # --------------------------------------------------------
    # Segunda desviación estándar
    # --------------------------------------------------------
    if ($self->{show_vwap_band_2}) {

        $self->_draw_vwap_series(
            canvas      => $canvas,
            values      => $values,
            field       => 'upper_2',
            color       => '#ff9800',
            width       => 1,
            dash        => '-',
            start       => $start,
            end         => $end,
            x_of        => $x_of,
            state       => $state,
            price_panel => $price_panel,
        );

        $self->_draw_vwap_series(
            canvas      => $canvas,
            values      => $values,
            field       => 'lower_2',
            color       => '#ff9800',
            width       => 1,
            dash        => '-',
            start       => $start,
            end         => $end,
            x_of        => $x_of,
            state       => $state,
            price_panel => $price_panel,
        );
    }

    # --------------------------------------------------------
    # Tercera desviación estándar
    # --------------------------------------------------------
    if ($self->{show_vwap_band_3}) {

        $self->_draw_vwap_series(
            canvas      => $canvas,
            values      => $values,
            field       => 'upper_3',
            color       => '#9c27b0',
            width       => 1,
            dash        => '-.',
            start       => $start,
            end         => $end,
            x_of        => $x_of,
            state       => $state,
            price_panel => $price_panel,
        );

        $self->_draw_vwap_series(
            canvas      => $canvas,
            values      => $values,
            field       => 'lower_3',
            color       => '#9c27b0',
            width       => 1,
            dash        => '-.',
            start       => $start,
            end         => $end,
            x_of        => $x_of,
            state       => $state,
            price_panel => $price_panel,
        );
    }

    # --------------------------------------------------------
    # Marca visual del ancla
    # --------------------------------------------------------
    my $anchor_index =
        $values->[0]{anchor_index};

    if (
        defined $anchor_index
        && $anchor_index >= $start
        && $anchor_index <= $end
    ) {
        my $x =
            $x_of->(
                $anchor_index - $start
            );

        if (defined $x) {
            $canvas->createLine(
                $x,
                0,
                $x,
                $state->{price_h},
                -fill  => '#2962ff',
                -width => 1,
                -dash  => '.',
            );

            $canvas->createText(
                $x + 5,
                25,
                -text   => 'VWAP',
                -fill   => '#2962ff',
                -font   => [
                    'Arial',
                    8,
                    'bold'
                ],
                -anchor => 'w',
            );
        }
    }

    # --------------------------------------------------------
    # Etiqueta del valor actual
    # --------------------------------------------------------
    my $last = $values->[-1];

    if (
        $last
        && defined $last->{vwap}
    ) {
        my $scale =
            $price_panel->{scale};

        my $y =
            $scale->price_to_y(
                $last->{vwap},
                $state->{price_min},
                $state->{price_max},
                0,
                $state->{price_h}
            );

        if (
            defined $y
            && $y >= 0
            && $y <= $state->{price_h}
        ) {
            my $mode =
                uc(
                    $self->{vwap_anchor_mode}
                    // 'MANUAL'
                );

            my $label = sprintf(
                'VWAP %s %.2f',
                $mode,
                $last->{vwap}
            );

            $canvas->createText(
                $state->{left} + 8,
                38,
                -text   => $label,
                -fill   => '#2962ff',
                -font   => [
                    'Arial',
                    9,
                    'bold'
                ],
                -anchor => 'w',
            );
        }
    }
}


sub set_vwap_anchor_index {
    my ($self, $index) = @_;

    return if !defined $index;

    my $last_index =
        $self->{market}->last_index();

    $index = 0
        if $index < 0;

    $index = $last_index
        if $index > $last_index;

    my $until_index =
        $self->_current_until_index();

    $index = $until_index
        if $index > $until_index;

    $self->{vwap_anchor_index} = $index;
    $self->{vwap_anchor_mode}  = 'MANUAL';

    $self->{vwap_selecting_anchor} = 0;
    $self->{show_anchored_vwap}    = 1;

    # Cambió el ancla: el resultado anterior ya no sirve.
    $self->invalidate_vwap_cache();

    $self->draw()
        if $self->can('draw');
}


sub start_vwap_anchor_selection {
    my ($self) = @_;

    $self->{vwap_anchor_mode} = 'MANUAL';

    $self->{vwap_selecting_anchor} = 1;

    $self->{show_anchored_vwap} = 1;
}


sub set_vwap_anchor_mode {
    my ($self, $mode) = @_;

    $mode = uc($mode // 'MANUAL');

    my %valid = map {
        $_ => 1
    } qw(
        MANUAL
        SESSION
        DAY
        WEEK
        MONTH
    );

    return if !$valid{$mode};

    # Si realmente no cambió, no es necesario recalcular.
    return
        if defined $self->{vwap_anchor_mode}
        && uc($self->{vwap_anchor_mode}) eq $mode;

    $self->{vwap_anchor_mode} = $mode;

    if ($mode ne 'MANUAL') {
        $self->{vwap_selecting_anchor} = 0;
    }

    # Cambió el período o tipo de ancla.
    $self->invalidate_vwap_cache();

    $self->draw()
        if $self->can('draw');
}

sub invalidate_vwap_cache {
    my ($self) = @_;

    $self->{vwap_cache} = undef;

    $self->{vwap_cache_anchor} = undef;
    $self->{vwap_cache_until}  = undef;
    $self->{vwap_cache_mode}   = undef;
}

sub _resolve_volume_profile_session_start {
    my ($self, $until_index) = @_;

    return undef if !defined $until_index;
    return undef if $until_index < 0;

    my $market = $self->{market};

    return undef if !$market;

    my $until_candle = $market->get_candle($until_index);

    return undef if !$until_candle;
    return undef if !defined $until_candle->{epoch};

    # Obtenemos la fecha de la última vela disponible.
    # Durante Replay, until_index corresponderá a la última
    # vela que ya fue revelada.
    my @until_time = localtime($until_candle->{epoch});

    my $until_year  = $until_time[5] + 1900;
    my $until_month = $until_time[4] + 1;
    my $until_day   = $until_time[3];

    my $session_key = sprintf(
        '%04d-%02d-%02d',
        $until_year,
        $until_month,
        $until_day
    );

    my $session_start = $until_index;

    # Recorremos hacia atrás desde la última vela disponible
    # hasta encontrar el inicio de su fecha o sesión.
    for (
        my $i = $until_index;
        $i >= 0;
        $i--
    ) {
        my $candle = $market->get_candle($i);

        next if !$candle;
        next if !defined $candle->{epoch};

        my @time = localtime($candle->{epoch});

        my $year  = $time[5] + 1900;
        my $month = $time[4] + 1;
        my $day   = $time[3];

        my $candle_session_key = sprintf(
            '%04d-%02d-%02d',
            $year,
            $month,
            $day
        );

        # Al llegar a una fecha diferente, la sesión actual
        # comienza en la vela siguiente.
        last if $candle_session_key ne $session_key;

        $session_start = $i;
    }

    return $session_start;
}

sub _resolve_volume_profile_historical_range {
    my ($self, $until_index) = @_;

    return if !defined $until_index;
    return if $until_index < 0;

    # Cantidad de velas históricas que se incluirán.
    # Si el valor no existe o es inválido, se utilizan
    # 500 velas como configuración predeterminada.
    my $historical_bars =
        $self->{volume_profile_historical_bars}
        //
        500;

    $historical_bars = int($historical_bars);

    if ($historical_bars < 1) {
        $historical_bars = 500;
    }

    # El índice final siempre será la última vela disponible.
    # Durante Replay, este índice corresponde únicamente
    # a las velas que ya han sido reveladas.
    my $last = $until_index;

    # Se resta bars - 1 porque tanto la primera como la
    # última vela forman parte del rango.
    #
    # Ejemplo:
    # last = 999
    # barras = 500
    # first = 999 - 500 + 1 = 500
    my $first =
        $last
        - $historical_bars
        + 1;

    # El rango nunca puede comenzar antes de la primera
    # vela disponible en el conjunto de datos.
    $first = 0 if $first < 0;

    return ($first, $last);
}

sub _volume_profile_structural_events {
    my ($self, $until_index) = @_;

    return [] if !defined $until_index;
    return [] if $until_index < 0;

    my @structural_events;

    # ============================================================
    # EVENTOS EXTERNOS BOS / CHoCH
    # ============================================================

    my $external_result = $self->{last_smc_external};

    if (
        $external_result
        && ref($external_result) eq 'HASH'
        && ref($external_result->{events}) eq 'ARRAY'
    ) {
        for my $event (@{$external_result->{events}}) {
            next if !$event;
            next if ref($event) ne 'HASH';

            my $raw_type = $event->{raw_type} // '';

            # Solo se consideran eventos estructurales BOS y CHoCH.
            next if $raw_type !~ /^(?:BOS|CHoCH)_(?:UP|DOWN)$/;

            my $event_index =
                $event->{break_index}
                //
                $event->{index};

            next if !defined $event_index;
            next if $event_index < 0;

            # Durante Replay no se permiten eventos futuros.
            next if $event_index > $until_index;

            push @structural_events, {
                %{$event},

                volume_profile_index => $event_index,
                volume_profile_scope => 'external',
            };
        }
    }

    # ============================================================
    # EVENTOS INTERNOS BOS / CHoCH
    # ============================================================

    my $internal_result = $self->{last_smc_internal};

    if (
        $internal_result
        && ref($internal_result) eq 'HASH'
        && ref($internal_result->{events}) eq 'ARRAY'
    ) {
        for my $event (@{$internal_result->{events}}) {
            next if !$event;
            next if ref($event) ne 'HASH';

            my $raw_type = $event->{raw_type} // '';

            next if $raw_type !~ /^(?:BOS|CHoCH)_(?:UP|DOWN)$/;

            my $event_index =
                $event->{break_index}
                //
                $event->{index};

            next if !defined $event_index;
            next if $event_index < 0;
            next if $event_index > $until_index;

            push @structural_events, {
                %{$event},

                volume_profile_index => $event_index,
                volume_profile_scope => 'internal',
            };
        }
    }

    # Se ordenan cronológicamente desde el evento más antiguo
    # hasta el más reciente.
    @structural_events = sort {
           $a->{volume_profile_index}
        <=> $b->{volume_profile_index}
    } @structural_events;

    return \@structural_events;
}


sub _resolve_volume_profile_structure_range {
    my ($self, $until_index) = @_;

    return if !defined $until_index;
    return if $until_index < 0;

    my $events =
        $self->_volume_profile_structural_events(
            $until_index
        );

    return if !$events;
    return if ref($events) ne 'ARRAY';
    return if !@{$events};

    # Como los eventos están ordenados cronológicamente,
    # el último elemento corresponde al BOS o CHoCH
    # confirmado más reciente.
    my $latest_event = $events->[-1];

    return if !$latest_event;

    my $anchor_index =
        $latest_event->{volume_profile_index};

    return if !defined $anchor_index;
    return if $anchor_index < 0;
    return if $anchor_index > $until_index;

    # Conservamos también el evento estructural anterior.
    my $previous_anchor_index;

    if (@{$events} >= 2) {
        $previous_anchor_index =
            $events->[-2]{volume_profile_index};
    }

    my $raw_type =
        $latest_event->{raw_type}
        //
        '';

    my $anchor_type;

    if ($raw_type =~ /^BOS_/) {
        $anchor_type = 'BOS';
    }
    elsif ($raw_type =~ /^CHoCH_/) {
        $anchor_type = 'CHOCH';
    }

    # Guardamos el estado para que pueda utilizarse
    # posteriormente en la interfaz, depuración o VWAP por POC.
    $self->{volume_profile_previous_anchor_index} =
        $previous_anchor_index;

    $self->{volume_profile_anchor_index} =
        $anchor_index;

    $self->{volume_profile_anchor_type} =
        $anchor_type;

    $self->{volume_profile_anchor_scope} =
        $latest_event->{volume_profile_scope};

    $self->{volume_profile_until_index} =
        $until_index;

    # El perfil comienza en la vela donde se confirmó
    # la ruptura estructural y termina en la última
    # vela actualmente disponible.
    my $first = $anchor_index;
    my $last  = $until_index;

    return ($first, $last);
}

sub _resolve_volume_profile_range {
    my ($self, %args) = @_;

    my $market = $self->{market};

    return if !$market;

    my $visible_first = $args{visible_first};
    my $visible_last  = $args{visible_last};

    return if !defined $visible_first;
    return if !defined $visible_last;

    my $last_market_index = $market->last_index();

    return if !defined $last_market_index;
    return if $last_market_index < 0;

    # ============================================================
    # ÚLTIMA VELA PERMITIDA
    # ============================================================

    # En modo normal se permite utilizar hasta la última vela
    # disponible en el mercado.
    my $until_index = $last_market_index;

    # Durante Replay, el límite debe ser la última vela revelada.
    if (
        $self->{replay_mode}
        && defined $self->{replay_index}
    ) {
        $until_index = $self->{replay_index};
    }

    # Protección adicional por si replay_index queda fuera
    # del rango disponible.
    $until_index = $last_market_index
        if $until_index > $last_market_index;

    return if $until_index < 0;

    $self->{volume_profile_until_index} =
        $until_index;

    # ============================================================
    # MODO ACTUAL
    # ============================================================

    my $mode =
        uc(
            $self->{volume_profile_mode}
            //
            'VISIBLE'
        );

    my %valid_modes = map {
        $_ => 1
    } qw(
        VISIBLE
        SESSION
        BOS_CHOCH
        HISTORICAL
    );

    # Si por algún motivo aparece un modo inválido,
    # se conserva el comportamiento anterior.
    $mode = 'VISIBLE'
        if !$valid_modes{$mode};

    my ($first, $last);

    # ============================================================
    # VISIBLE RANGE VOLUME PROFILE
    # ============================================================

    if ($mode eq 'VISIBLE') {
        $first = $visible_first;
        $last  = $visible_last;

        # Aunque el rango visible llegue más lejos,
        # Replay impide usar velas todavía no reveladas.
        $last = $until_index
            if $last > $until_index;

        $first = 0
            if $first < 0;
    }

    # ============================================================
    # VOLUME PROFILE POR SESIÓN
    # ============================================================

    elsif ($mode eq 'SESSION') {
        $first =
            $self->_resolve_volume_profile_session_start(
                $until_index
            );

        $last = $until_index;
    }

    # ============================================================
    # VOLUME PROFILE ANCLADO A BOS / CHoCH
    # ============================================================

    elsif ($mode eq 'BOS_CHOCH') {
        ($first, $last) =
            $self->_resolve_volume_profile_structure_range(
                $until_index
            );

        # Si todavía no existe ningún BOS o CHoCH confirmado,
        # se utiliza el rango histórico como respaldo.
        if (
            !defined $first
            || !defined $last
        ) {
            ($first, $last) =
                $self->_resolve_volume_profile_historical_range(
                    $until_index
                );

            # Al utilizar el respaldo no existe un ancla
            # estructural válida.
            $self->{volume_profile_anchor_index} = undef;

            $self->{volume_profile_previous_anchor_index} =
                undef;

            $self->{volume_profile_anchor_type} = undef;
            $self->{volume_profile_anchor_scope} = undef;
        }
    }

    # ============================================================
    # VOLUME PROFILE HISTÓRICO
    # ============================================================

    elsif ($mode eq 'HISTORICAL') {
        ($first, $last) =
            $self->_resolve_volume_profile_historical_range(
                $until_index
            );
    }

    return if !defined $first;
    return if !defined $last;

    # ============================================================
    # VALIDACIONES FINALES
    # ============================================================

    $first = int($first);
    $last  = int($last);

    $first = 0
        if $first < 0;

    $last = $until_index
        if $last > $until_index;

    $last = $last_market_index
        if $last > $last_market_index;

    return if $last < $first;

    return ($first, $last, $mode);
}


sub _calculate_volume_profile {
    my ($self,%args)=@_;

    my $market=$self->{market};

    return [] if !$market;

    my $first=$args{first};
    my $last =$args{last};

     # El modo puede recibirse explícitamente o tomarse
    # de la configuración actual del ChartEngine.
     my $mode = uc(
        $args{mode}
        //
        $self->{volume_profile_mode}
        //
        'VISIBLE'
    );

    return [] if !defined $first;
    return [] if !defined $last;
    return [] if $last<$first;

    if (
        defined $self->{volume_profile_cache}
        && defined $self->{volume_profile_cache_first}
        && defined $self->{volume_profile_cache_last}
        && defined $self->{volume_profile_cache_mode}
        && $self->{volume_profile_cache_first} == $first
        && $self->{volume_profile_cache_last}  == $last
        && $self->{volume_profile_cache_mode}  eq $mode
    ) {
        return $self->{volume_profile_cache};
    }

    my $low=9e99;
    my $high=-9e99;

    for my $i($first..$last){

        my $bar=$market->get_candle($i);
        next if !$bar;

        $low=$bar->{low}
            if $bar->{low}<$low;

        $high=$bar->{high}
            if $bar->{high}>$high;
    }

    return []
        if $high<=$low;

    my $rows=$self->{volume_profile_rows}||48;

    my $step=($high-$low)/$rows;

    $step=0.01 if $step<=0;

    my @bins;

    for(0..$rows-1){

        push @bins,{
            low=>$low+$_*$step,
            high=>$low+($_+1)*$step,
            volume=>0,
        };
    }

    for my $i($first..$last){

        my $bar=$market->get_candle($i);
        next if !$bar;

        my $vol=$bar->{volume}//0;
        next if $vol<=0;

        my $range=$bar->{high}-$bar->{low};

        if($range<=0){

            my $idx=int(
                (($bar->{close}-$low)/$step)
            );

            $idx=0 if $idx<0;
            $idx=$rows-1 if $idx>$rows-1;

            $bins[$idx]{volume}+=$vol;

            next;
        }

        for my $r(0..$rows-1){

            my $a=$bins[$r]{low};
            my $b=$bins[$r]{high};

            my $overlap=
                (
                    ($bar->{high}<$a)
                    ||
                    ($bar->{low}>$b)
                )
                ?0
                :(
                    (
                        ($bar->{high}<$b?$bar->{high}:$b)
                        -
                        ($bar->{low}>$a?$bar->{low}:$a)
                    )
                );

            next if $overlap<=0;

            my $weight=
                $overlap/$range;

            $bins[$r]{volume}
                +=$vol*$weight;
        }
    }

    my $max_volume=0;

    for(@bins){

        $max_volume=$_-> {volume}
            if $_->{volume}>$max_volume;
    }

    my $poc_index=0;

    for my $i(0..$#bins){

        if(
            $bins[$i]{volume}
            >=
            $bins[$poc_index]{volume}
        ){
            $poc_index=$i;
        }
    }

        my $total_volume = 0;

    $total_volume += $_->{volume}
        for @bins;

    my $target_volume =
        $total_volume
        *
        ($self->{volume_profile_value_area} || 0.70);

    my $accumulated =
        $bins[$poc_index]{volume};

    my $vah = $poc_index;
    my $val = $poc_index;

    while($accumulated < $target_volume){

        my $up_volume =
            ($vah < $#bins)
                ? $bins[$vah+1]{volume}
                : -1;

        my $down_volume =
            ($val > 0)
                ? $bins[$val-1]{volume}
                : -1;

        if($up_volume >= $down_volume){

            last
                if $vah >= $#bins;

            $vah++;

            $accumulated +=
                $bins[$vah]{volume};

        }
        else{

            last
                if $val <= 0;

            $val--;

            $accumulated +=
                $bins[$val]{volume};

        }

    }

    for my $i(0..$#bins){

        $bins[$i]{inside_value_area} =
            ($i >= $val && $i <= $vah)
            ? 1
            : 0;

    }

       $self->{volume_profile_cache} = \@bins;

    $self->{volume_profile_cache_first} = $first;
    $self->{volume_profile_cache_last}  = $last;
    $self->{volume_profile_cache_mode}  = $mode;

    $self->{volume_profile_poc} =
        $poc_index;

    $self->{volume_profile_vah} =
        $vah;

    $self->{volume_profile_val} =
        $val;

    $self->{volume_profile_max} =
        $max_volume;

    return \@bins;
}


sub _draw_volume_profile {
    my ($self, %args) = @_;

    my $canvas      = $args{canvas};
    my $start       = $args{start};
    my $end         = $args{end};
    my $state       = $args{state};
    my $price_panel = $args{price_panel};

    return if !$canvas;
    return if !$state;
    return if !$price_panel;

    # ============================================================
    # RESOLVER EL RANGO SEGÚN EL MODO DEL VOLUME PROFILE
    # ============================================================

    my ($profile_first, $profile_last, $profile_mode) =
        $self->_resolve_volume_profile_range(
            visible_first => $start,
            visible_last  => $end,
        );

    return if !defined $profile_first;
    return if !defined $profile_last;
    return if !defined $profile_mode;

    # Calculamos el perfil utilizando el rango resuelto.
    # Ya no se utiliza obligatoriamente el rango visible.
    my $profile =
        $self->_calculate_volume_profile(
            first => $profile_first,
            last  => $profile_last,
            mode  => $profile_mode,
        );

    return if !$profile;
    return if ref($profile) ne 'ARRAY';
    return if !@{$profile};

    my $scale = $price_panel->{scale};

    return if !$scale;

    my $right =
        $state->{right};

    my $price_height =
        $state->{price_h};

    return if !defined $right;
    return if !defined $price_height;

    # Ancho máximo del histograma dibujado
    # en el lado derecho del gráfico.
    my $max_width = 90;

    my $max_volume =
        $self->{volume_profile_max}
        //
        1;

    $max_volume = 1
        if $max_volume <= 0;

    # ============================================================
    # DIBUJO DE LAS FILAS DEL PERFIL
    # ============================================================

    for my $i (0 .. $#{$profile}) {
        my $row = $profile->[$i];

        next if !$row;
        next if ref($row) ne 'HASH';
        next if !defined $row->{volume};
        next if $row->{volume} <= 0;

        my $y1 =
            $scale->price_to_y(
                $row->{high},
                $state->{price_min},
                $state->{price_max},
                0,
                $price_height,
            );

        my $y2 =
            $scale->price_to_y(
                $row->{low},
                $state->{price_min},
                $state->{price_max},
                0,
                $price_height,
            );

        next if !defined $y1;
        next if !defined $y2;

        # No dibujamos filas completamente fuera
        # del panel visible de precios.
        next if $y2 < 0;
        next if $y1 > $price_height;

        my $width =
            (
                $row->{volume}
                /
                $max_volume
            )
            *
            $max_width;

        $width = 1
            if $width < 1;

        # Azul para el área de valor y azul claro
        # para las filas que quedan fuera.
        my $color =
            $row->{inside_value_area}
            ? '#2962ff'
            : '#9db7e5';

        # El POC se representa en color naranja.
        if (
            defined $self->{volume_profile_poc}
            &&
            $i == $self->{volume_profile_poc}
        ) {
            $color = '#ff9800';
        }

        $canvas->createRectangle(
            $right - $width,
            $y1,
            $right,
            $y2,

            -fill    => $color,
            -outline => $color,
        );
    }

    # ============================================================
    # LÍNEA DEL POC
    # ============================================================

    if (
        defined $self->{volume_profile_poc}
        &&
        defined $profile->[
            $self->{volume_profile_poc}
        ]
    ) {
        my $row =
            $profile->[
                $self->{volume_profile_poc}
            ];

        my $price =
            (
                $row->{high}
                +
                $row->{low}
            )
            /
            2;

        my $y =
            $scale->price_to_y(
                $price,
                $state->{price_min},
                $state->{price_max},
                0,
                $price_height,
            );

        if (
            defined $y
            &&
            $y >= 0
            &&
            $y <= $price_height
        ) {
            $canvas->createLine(
                $right - 92,
                $y,
                $right,
                $y,

                -fill  => '#ff9800',
                -width => 2,
            );

            $canvas->createText(
                $right - 95,
                $y,

                -anchor => 'e',
                -fill   => '#ff9800',
                -font   => ['Arial', 8, 'bold'],
                -text   => 'POC',
            );
        }
    }

    # ============================================================
    # LÍNEAS VAH Y VAL
    # ============================================================

    for my $pair (
        [
            $self->{volume_profile_vah},
            '#43a047',
            'VAH',
        ],
        [
            $self->{volume_profile_val},
            '#e53935',
            'VAL',
        ],
    ) {
        my ($index, $color, $text) =
            @{$pair};

        next if !defined $index;
        next if !defined $profile->[$index];

        my $row =
            $profile->[$index];

        my $price;

        if ($text eq 'VAH') {
            $price = $row->{high};
        }
        else {
            $price = $row->{low};
        }

        my $y =
            $scale->price_to_y(
                $price,
                $state->{price_min},
                $state->{price_max},
                0,
                $price_height,
            );

        next if !defined $y;
        next if $y < 0;
        next if $y > $price_height;

        $canvas->createLine(
            $right - 92,
            $y,
            $right,
            $y,

            -fill => $color,
            -dash => [4, 4],
        );

        $canvas->createText(
            $right - 95,
            $y,

            -anchor => 'e',
            -text   => $text,
            -fill   => $color,
            -font   => ['Arial', 8, 'bold'],
        );
    }
}

sub invalidate_volume_profile_cache {
    my ($self) = @_;

    # Elimina el histograma calculado anteriormente.
    $self->{volume_profile_cache} = undef;

    # Elimina el rango de velas asociado al caché anterior.
    $self->{volume_profile_cache_first} = undef;
    $self->{volume_profile_cache_last}  = undef;

    # Elimina el modo con el cual se construyó el caché.
    # Esto evita reutilizar, por ejemplo, un perfil VISIBLE
    # cuando el usuario cambió al modo SESSION o BOS_CHOCH.
    $self->{volume_profile_cache_mode} = undef;

    # Elimina los niveles calculados del perfil anterior.
    $self->{volume_profile_poc} = undef;
    $self->{volume_profile_vah} = undef;
    $self->{volume_profile_val} = undef;
    $self->{volume_profile_max} = undef;
}


1;
