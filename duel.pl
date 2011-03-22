use strict;

use vars qw($VERSION %IRSSI);
$VERSION = '2011/03/22';
%IRSSI = (
	   authors     => 'Marko Ivankovic', 'Bruno Rahle'
	   name        => 'duel',
	   description => 'Monitor Duels between users (based on Quizmaster script by Stefan Tomanek)',
	   license     => 'GPLv3',
	   url         => 'http://irssi.org/scripts/',
	   changed     => $VERSION,
	   modules     => 'Data::Dumper',
	   commands    => "duel"
);

use Irssi;
use Data::Dumper;

use vars qw(%sessions);

sub show_help() {
    my $help = "Coding Duel $VERSION
/duel
    Show running sessions.
/duel start
    Enable duels in the current channel.
/duel score
    Display the scoretable of  the current game.
/duel stop
    Stop dueling in the current channel.
";
    my $text='';
    foreach (split(/\n/, $help)) {
        $_ =~ s/^\/(.*)$/%9\/$1%9/;
        $text .= $_."\n";
    }
    print CLIENTCRAP &draw_box("Coding duel", $text, "Coding duel help", 1);
}

sub draw_box ($$$$) {
    my ($title, $text, $footer, $colour) = @_;
    my $box = '';
    $box .= '%R,--[%n%9%U'.$title.'%U%9%R]%n'."\n";
    foreach (split(/\n/, $text)) {
        $box .= '%R|%n '.$_."\n";
    }
    $box .= '%R`--<%n'.$footer.'%R>->%n';
    $box =~ s/%.//g unless $colour;
    return $box;
}

sub start_quiz ($) {
    my ($channel) = @_;
#    line2target($channel, '>>>> Dueling is now enabled. Let the best coder win! <<<<');
    $sessions{$channel}{enabled} = 1;
    $sessions{$channel}{score} = {};
    $sessions{$channel}{totalscore} = {};
    $sessions{$channel}{dueling} = {};
}

sub stop_quiz ($) {
    my ($target) = @_;
    show_scores($target);
#    line2target($target, '>>>> Everyone, keyboards down! Dueling disabled. <<<<');
    delete $sessions{$target};
}

sub event_public_message ($$$$) {
    my ($server, $text, $nick, $address, $target) = @_;
    parse($nick, $text, $target) if defined $sessions{$target} and $sessions{$target}{enabled};
}

sub event_message_own_public ($$$) {
    my ($server, $msg, $target, $otarget) = @_;
    parse($server->{nick}, $msg, $target) if defined $sessions{$target} and $sessions{$target}{enabled};
}

sub parse ($$$) {
    my ($nick, $text, $target) = @_;
    if ($text =~ /^!duel$/) {
        line2target($target, "$nick: Try !duel start <nick> <URL>.");
    }
    if ($text =~ /^!duel start ([a-zA-Z0-9_-]+) (.*)/) {
        my $defendant = $1;
        my $task = $2;
        if (defined $sessions{$target}{dueling}{$nick}) {
            line2target($target, "$nick: You are already in a duel! Solve that one first or !duel defeat.");
        }
        else {
            if (defined $sessions{$target}{dueling}{$defendant}) {
                line2target($target, "$nick: $defendant is already in a duel with ".$sessions{$target}{dueling}{$defendant});
            }
            else {
                $sessions{$target}{dueling}{$nick} = $defendant;
                $sessions{$target}{dueling}{$defendant} = "PENDING@".$nick;
                line2target($target, "$defendant: >>>> Challenged by $nick with $task. !duel accept or !duel reject. <<<<")
            }
        }
    }
    if ($text =~ /^!duel accept$/) {
	if (defined $sessions{$target}{dueling}{$nick}) {
	   $sessions{$target}{dueling}{$nick} =~ s/PENDING@//;
	   my $opponent = $sessions{$target}{dueling}{$nick};
	   line2target($target, "$opponent: $nick accepted your challenge. >>>> FIGHT! <<<<");
	}
    }
    if ($text =~ /^!duel reject$/) {
	if (defined $sessions{$target}{dueling}{$nick}) {
	   $sessions{$target}{dueling}{$nick} =~ s/PENDING@//;
	   my $opponent = $sessions{$target}{dueling}{$nick};
           delete $sessions{$target}{dueling}{$nick};
	   delete $sessions{$target}{dueling}{$opponent};
	   line2target($target, ">>>> $nick rejected. <<<<");
	}
    }
    if ($text =~ /^!duel defeat$/) {
        if (defined $sessions{$target}{dueling}{$nick}) {
            my $opponent = $sessions{$target}{dueling}{$nick};
            $sessions{$target}{score}{$opponent}{$nick}++;
            $sessions{$target}{totalscore}{$opponent}++;
            delete $sessions{$target}{dueling}{$opponent};
            delete $sessions{$target}{dueling}{$nick};
            line2target($target, ">>>> $opponent defeated $nick! ($nick claimed defeat) <<<<")
        }
    }
    if ($text =~ /^!duel score ([a-zA-Z0-9_-]+) ([a-zA-Z0-9_-]+)/) {
        if (defined $sessions{$target}{score}{$1}{$2}) {
            line2target($target, ">>>> $1 defeated $2 ".$sessions{$target}{score}{$1}{$2}." times. <<<<")
        } else {
            line2target($target, ">>>> $1 never defeated $2.<<<<")
        }
    }
    if ($text =~ /^!duel approve ([a-zA-Z0-9_-]+) ([a-zA-Z0-9_-]+)/) {
        if (defined $sessions{$target}{dueling}{$1} and defined $sessions{$target}{dueling}{$2}) {
            if ($sessions{$target}{dueling}{$1} eq $2 and $sessions{$target}{dueling}{$2} eq $1) {
                if (($nick ne $1) and ($nick ne $2)) {
                    $sessions{$target}{score}{$1}{$2}++;
                    $sessions{$target}{totalscore}{$1}++;
                    delete $sessions{$target}{dueling}{$1};
                    delete $sessions{$target}{dueling}{$2};
                    line2target($target, ">>>> $1 defeated $2! ($nick approved)<<<<");
                }
            }
        }
    }
    if ($text =~ /^!duel victory$/) {
        if (defined $sessions{$target}{dueling}{$nick}) {
            my $opponent = $sessions{$target}{dueling}{$nick};
            line2target($target, ">>>> $nick claimed victory. Approvers needed! Type !duel approve $nick $opponent if you approve!<<<<")
        }
    }
    if ($text =~ /^!duel topscore$/) {
        show_scores($target);
    }
}

sub line2target ($$) {
    my ($target, $line) = @_;
    my $witem = Irssi::window_item_find($target);
    $witem->{server}->command('MSG '.$target.' '.$line);
    #$witem->print('MSG '.$target.' '.$line);
}

sub show_scores ($) {
    my ($target) = @_;
    my $table;
    foreach (sort {$sessions{$target}{totalscore}{$b} <=> $sessions{$target}{totalscore}{$a}} keys(%{$sessions{$target}{totalscore}})) {
    	 $table .= "$_ now has ".$sessions{$target}{totalscore}{$_}." points.\n";
    }
    my $box = draw_box('Coding Duel', $table, 'score', 0);
    line2target($target, $_) foreach (split(/\n/, $box));
}

sub list_sessions {
    my $msg;
    foreach (sort keys %sessions) {
        $msg .= '`->%U'.$_.'%U '."\n";
    }
    print CLIENTCRAP &draw_box("Coding Duel", $msg, "sessions", 1);
}

sub event_nicklist_changed ($$$) {
    my ($channel, $nick, $oldnick) = @_;
    # handle incoming guests
}

sub cmd_codingduel ($$$) {
    my ($args, $server, $witem) = @_;
    my @arg = split(/ /, $args);
    if (scalar(@arg) == 0) {
	      list_sessions();
    } elsif ($arg[0] eq 'start') {
        start_quiz($witem->{name});
    } elsif ($arg[0] eq 'stop') {
    	  stop_quiz($witem->{name});
    } elsif ($arg[0] eq 'score') {
	      show_scores($witem->{name}) if defined $sessions{$witem->{name}};
    } elsif ($arg[0] eq 'help') {
    	  show_help();
    }
}

sub recover() {
    local *F;
    no strict 'vars';
    my $filename = Irssi::settings_get_str('duel_score_file');
    return unless -e $filename;
    open(F, $filename);
    $data .= $_ foreach (<F>);
    close F;
    return unless "$data";
    %sessions = %{ eval "$data" };
}

sub persist() {
    local *F;
    my $filename = Irssi::settings_get_str('duel_score_file');
    open(F, ">".$filename);
    my $dumper = Data::Dumper->new([\%sessions], ['sessions']);
    $dumper->Purity(1)->Deepcopy(1);
    my $data = $dumper->Dump;
    print F $data;
    close F;
}

Irssi::command_bind($IRSSI{'name'}, \&cmd_codingduel);
foreach my $cmd ('score', 'start', 'help', 'stop') {
Irssi::command_bind('codingduel '.$cmd => sub {
                    cmd_codingduel("$cmd ".$_[0], $_[1], $_[2]); });
}


Irssi::settings_add_int($IRSSI{'name'}, 'codingduel_timeout', 60);
Irssi::settings_add_str($IRSSI{'name'}, 'duel_score_file', "$ENV{HOME}/.irssi/duel_scorese");

Irssi::signal_add('message public', 'event_public_message');
Irssi::signal_add('message own_public', 'event_message_own_public');
Irssi::signal_add('nicklist changed', 'event_nicklist_changed');

Irssi::timeout_add(60000, 'persist', undef);
recover();

print CLIENTCRAP '%B>>%n '.$IRSSI{name}.' '.$VERSION.' loaded: /duel help for help';
