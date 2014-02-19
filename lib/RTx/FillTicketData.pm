use strict;
use warnings;
use feature qw(switch);

package RTx::FillTicketData;

our $VERSION = '0.01';

use DBI;
use Digest::MD5 qw(md5_hex);
use JSON;

#use Data::Dumper;
#local $Data::Dumper::Sortkeys = 1;

RT->AddJavaScript('RTx-FillTicketData.js');

my $old_md5_sum = ''; # avoid uninitialized warning
my $config;
my %dbh_for;

sub config { return $config; }

sub find_config_file {
    RT->Config->Get('FillTicketDataSettingsFile');
}

sub read_config {
    my $config_file = shift || find_config_file();

    my $json_data = read_file($config_file);
    my $md5_sum = md5_hex($json_data);
    if ($md5_sum eq $old_md5_sum) {
        $RT::Logger->debug("MD5 sum matches the old one ($md5_sum), leaving config alone");
        return $config;
    }

    $RT::Logger->debug('New plugin configuration detected, re-reading config',
        "old_sum: $old_md5_sum, new sum: $md5_sum");
    $old_md5_sum = $md5_sum;
    $config = from_json($json_data);
}

sub read_file {
    my $filename = shift;
    local $/;
    open my $FH, '<', $filename
        or die "Could not open file $filename: $!";
    return <$FH>;
}

# Re-initialize database connections
sub init_connections {
    undef %dbh_for;

    for my $db_id (keys %{ $config->{databases} }) {
        $dbh_for{$db_id} = _connect_db($config->{databases}->{$db_id});
    }
}

# Connect to a database using configuration from $db_config
sub _connect_db {
    my $db_config = shift;

    my $dsn = "dbi:$db_config->{type}:$db_config->{database}";
    for my $field (qw(host port)) {
        $dsn .= ";$field=$db_config->{$field}" if $db_config->{$field};
    }

    my %more_attrs;
    given ($db_config->{type}) {
        when ('mysql') {
            %more_attrs = ( mysql_enable_utf8 => 1 );
        }
        when ('Pg') {
            %more_attrs = ( pg_enable_utf8 => 1 );
        }
    }
    my $dbh = DBI->connect(
        $dsn,
        $db_config->{username},
        $db_config->{password},
        {
            RaiseError => 1,
            PrintError => 1,
            %more_attrs
        },
    );
    $dbh->do('SET NAMES utf8') if $db_config->{type} ne 'SQLite';
    return $dbh;
}

=head3 get_data

Returns data from configured sources

    In: %arg hash in the form
    (
        Object-RT::Ticket--CustomField-1-Values => $value1,
        Object-RT::Ticket--CustomField-3-Values => $value3,
        ...
    )
    Out: %content_of - hash of values from the configured sources for the same
        fields as

=cut

sub get_data {
    my %arg = @_;

    # Last try to read a config if we haven't already
    read_config() if !$config;

    # Detect whether we have key fields in the input
    my %field_for_id = map { /(\d+)/, $_ } keys %arg;

    # Contents of appropriate fields
    my %content_of;

    for my $field_id (
        grep {
            $_ ne '_comment'     # Filter out comments
            && $field_for_id{$_} # Filter out fields not on page
        } keys %{ $config->{field_sources} }
    ) {
        my @sources = @{ $config->{field_sources}->{$field_id} };
        for my $source (@sources) {

            # Detect type of source - command or database
            if ($source->{command}) {
                if (my $result = _get_command_result($source, \%arg)) {
                    $content_of{$field_id} .= $result;
                }
            } elsif ($source->{database}) {
                if (my $result = _get_db_result($source, \%arg)) {
                    $content_of{$field_id} .= $result;
                }
            } else {
                $content_of{$field_id} = 'Error: wrong source configuration';
            }
        }
    }

    #warn 'content_of: ' . Dumper(\%content_of);

    my %result = map { $field_for_id{$_} => $content_of{$_} } keys %content_of;

    #warn 'result: ' . Dumper(\%result);
    return \%result;
}

sub _get_command_result {
    my $source = shift;
    return "command: $source->{command}";
}

sub _get_db_result {
    my $source = shift;
    return "database: $source->{sql}";
}

1;
