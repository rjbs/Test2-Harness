package App::Yath::Command::test;
use strict;
use warnings;

our $VERSION = '0.001017';

use Test2::Harness::Util::TestFile;
use Test2::Harness::Feeder::Run;
use Test2::Harness::Run::Runner;
use Test2::Harness::Run::Queue;
use Test2::Harness::Run;

use Test2::Harness::Util::Term qw/USE_ANSI_COLOR/;

use App::Yath::Util qw/is_generated_test_pl/;

use Time::HiRes qw/time/;

use parent 'App::Yath::Command';
use Test2::Harness::Util::HashBase;

sub group { ' test' }

sub has_jobs      { 1 }
sub has_runner    { 1 }
sub has_logger    { 1 }
sub has_display   { 1 }
sub manage_runner { 1 }

sub summary { "Run tests" }
sub cli_args { "[--] [test files/dirs] [::] [arguments to test scripts]" }

sub description {
    return <<"    EOT";
This yath command (which is also the default command) will run all the test
files for the current project. If no test files are specified this command will
look for the 't', and 't2' dirctories, as well as the 'test.pl' file.

This command is always recursive when given directories.

This command will add 'lib', 'blib/arch' and 'blib/lib' to the perl path for
you by default.

Any command line argument that is not an option will be treated as a test file
or directory of test files to be run.

If you wish to specify the ARGV for tests you may append them after '::'. This
is mainly useful for Test::Class::Moose and similar tools. EVERY test run will
get the same ARGV.
    EOT
}

sub handle_list_args {
    my $self = shift;
    my ($list) = @_;

    my $settings = $self->{+SETTINGS} ||= {};

    $settings->{search} = $list;

    my $has_search = $settings->{search} && @{$settings->{search}};

    unless ($has_search) {
        return if grep { $_->block_default_search($settings) } keys %{$settings->{plugins}};

        my @dirs = grep { -d $_ } './t', './t2';

        push @dirs => './xt'
            if -d './xt'
            && ($settings->{env_vars}->{AUTHOR_TESTING}
            || $ENV{AUTHOR_TESTING});

        my @files;
        push @files => 'test.pl' if -f 'test.pl' && !is_generated_test_pl('test.pl');

        $settings->{search} = [@dirs, @files];
    }
}


sub feeder {
    my $self = shift;

    my $settings = $self->{+SETTINGS};

    my $run = $self->make_run_from_settings(finite => 1);

    my $runner = Test2::Harness::Run::Runner->new(
        dir => $settings->{dir},
        run => $run,
    );

    my $queue = $runner->queue;
    $queue->start;

    my $job_id = 1;
    for my $tf ($run->find_files) {
        $queue->enqueue($tf->queue_item($job_id++));
    }

    my $pid = $runner->spawn(jobs_todo => $job_id - 1);

    $queue->end;

    my $feeder = Test2::Harness::Feeder::Run->new(
        run      => $run,
        runner   => $runner,
        dir      => $settings->{dir},
        keep_dir => $settings->{keep_dir},
    );

    return ($feeder, $runner, $pid, $job_id - 1);
}

sub run_command {
    my $self = shift;

    my $settings = $self->{+SETTINGS};

    my $renderers = $self->renderers;
    my $loggers   = $self->loggers;

    my ($feeder, $runner, $pid, $stat, $jobs_todo);
    my $ok = eval {
        ($feeder, $runner, $pid, $jobs_todo) = $self->feeder or die "No feeder!";

        my $harness = Test2::Harness->new(
            run_id            => $settings->{run_id},
            live              => $pid ? 1 : 0,
            feeder            => $feeder,
            loggers           => $loggers,
            renderers         => $renderers,
            event_timeout     => $settings->{event_timeout},
            post_exit_timeout => $settings->{post_exit_timeout},
            jobs              => $settings->{jobs},
            jobs_todo         => $jobs_todo,
        );

        $stat = $harness->run();

        1;
    };
    my $err = $@;
    warn $err unless $ok;

    my $exit = 0;

    if ($self->manage_runner) {
        unless ($ok) {
            if ($pid) {
                print STDERR "Killing runner\n";
                kill($self->{+SIGNAL} || 'TERM', $pid);
            }
        }

        if ($runner && $runner->pid) {
            $runner->wait;
            $exit = $runner->exit;
        }
    }

    if (-t STDOUT) {
        print STDOUT Term::ANSIColor::color('reset') if USE_ANSI_COLOR;
        print STDOUT "\r\e[K";
    }

    if (-t STDERR) {
        print STDERR Term::ANSIColor::color('reset') if USE_ANSI_COLOR;
        print STDERR "\r\e[K";
    }

    $self->paint("\n", '=' x 80, "\n");
    $self->paint("\nRun ID: $settings->{run_id}\n");

    my $bad = $stat ? $stat->{fail} : [];
    my $lost = $stat ? $stat->{lost} : 0;

    # Possible failure causes
    my $fail = $lost || $exit || !defined($exit) || !$ok || !$stat;

    if (@$bad) {
        $self->paint("\nThe following test jobs failed:\n");
        $self->paint("  [", $_->{job_id}, '] ', File::Spec->abs2rel($_->file), "\n") for sort {
            my $an = $a->{job_id};
            $an =~ s/\D+//g;
            my $bn = $b->{job_id};
            $bn =~ s/\D+//g;

            # Sort numeric if possible, otherwise string
            int($an) <=> int($bn) || $a->{job_id} cmp $b->{job_id}
        } @$bad;
        $self->paint("\n");
        $exit += @$bad;
    }

    if ($fail) {
        my $sig = $self->{+SIGNAL};

        $self->paint("\n");

        $self->paint("Test runner exited badly: $exit\n") if $exit;
        $self->paint("Test runner exited badly: ?\n") unless defined $exit;
        $self->paint("An exception was cought\n") if !$ok && !$sig;
        $self->paint("Received SIG$sig\n") if $sig;
        $self->paint("$lost test files were never run!\n") if $lost;

        $self->paint("\n");

        $exit ||= 255;
    }

    if (!@$bad && !$fail) {
        $self->paint("\nAll tests were successful!\n\n");

        if ($settings->{cover}) {
            require IPC::Cmd;
            if(my $cover = IPC::Cmd::can_run('cover')) {
                system($^X, (map { "-I$_" } @INC), $cover);
            }
            else {
                $self->paint("You will need to run the `cover` command manually to build the coverage report.\n\n");
            }
        }
    }

    print "Keeping work dir: $settings->{dir}\n" if $settings->{keep_dir} && $settings->{dir};

    print "Wrote " . ($ok ? '' : '(Potentially Corrupt) ') . "log file: $settings->{log_file}\n"
        if $settings->{log};

    $exit = 255 unless defined $exit;
    $exit = 255 if $exit > 255;

    return $exit;
}

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

App::Yath::Command::test - Command to run tests

=head1 DESCRIPTION

=head1 SYNOPSIS

=head1 COMMAND LINE USAGE

B<THIS SECTION IS AUTO-GENERATED AT BUILD>

=head1 SOURCE

The source code repository for Test2-Harness can be found at
F<http://github.com/Test-More/Test2-Harness/>.

=head1 MAINTAINERS

=over 4

=item Chad Granum E<lt>exodist@cpan.orgE<gt>

=back

=head1 AUTHORS

=over 4

=item Chad Granum E<lt>exodist@cpan.orgE<gt>

=back

=head1 COPYRIGHT

Copyright 2017 Chad Granum E<lt>exodist7@gmail.comE<gt>.

This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

See F<http://dev.perl.org/licenses/>

=cut
