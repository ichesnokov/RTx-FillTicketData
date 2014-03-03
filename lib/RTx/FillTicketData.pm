use v5.10;
use strict;
use warnings;

package RTx::FillTicketData;

our $VERSION = '0.01';

use DBI;
use Digest::MD5 qw(md5_hex);
use JSON qw(decode_json);

#use Data::Dumper;
#local $Data::Dumper::Sortkeys = 1;

RT->AddJavaScript('RTx-FillTicketData.js');

my $old_md5_sum = ''; # avoid uninitialized warning
my $config;
my %dbh_for;

# Signature for the appropriate user id
my %signature_for;

sub set_signature {
    my ($user_id, $signature) = @_;

    $signature_for{$user_id} = $signature;
    return $signature;
}

sub get_signature {
    my $user_id = shift;

    return $signature_for{$user_id};
}

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
    $config = decode_json($json_data);
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

    In: \%arg hash in the form
    (
        Object-RT::Ticket--CustomField-1-Values => $value1,
        Object-RT::Ticket--CustomField-3-Values => $value3,
        ...
    )
    Out: \%content_of - hash of values from the configured sources for the same
        fields as

=cut

sub get_data {
    my $arg = shift;

    #warn 'arg: ' . Dumper($arg);

    # Last try to read a config if we haven't already
    if (!$config) {
        read_config();
        init_connections();
    }

    # Detect whether we have key fields in the input
    my %field_id_for;
    my %key_field;

    while (my ($key, $value) = each %$arg) {
        $field_id_for{$key} = _get_field_id($key);

        if ($value ne '__exists__') {
            $key_field{ $field_id_for{$key} } = $value;
        }
    }

    # Append Subject and Body
    my %html_id_for = reverse %field_id_for, qw(Body Body Subject Subject);

    if (!%key_field) {
        warn 'no key field';
        return { error => 'No key field' };
    }

    # Contents of appropriate fields
    my %content_of;

    for my $field_id (
        grep {
            $_ ne '_comment'    # Filter out comments
            && $html_id_for{$_} # Filter out fields not on page
        } keys %{ $config->{field_sources} }
    ) {
        my @sources = @{ $config->{field_sources}->{$field_id} };
        for my $source (@sources) {

            # Detect type of source - command or database
            my $result =
                  $source->{command}  ? _get_command_result($source, %key_field)
                : $source->{database} ? _get_db_result($source, %key_field)
                : $source->{Text}     ? _get_text_result($source, %key_field)
                : "Wrong source configuration for field $field_id";
            #next if !$result;

            $result ||= ''; # avoid warning about uninitialized value

            # Data from different sources are concatenated using newlines
            if ($content_of{$field_id}) {
                $content_of{$field_id} .= "<br/>";
            }
            $content_of{$field_id} .= $result;
        }
    }

    #warn 'content_of: ' . Dumper(\%content_of);

    my %result = map { $html_id_for{$_} => $content_of{$_} } keys %content_of;

    my $signature
        = get_signature($HTML::Mason::Commands::session{'CurrentUser'}->Id);
    if ($result{Body} && $signature) {
        $result{Body} .= $signature;
    }

    #warn 'result: ' . Dumper(\%result);
    return \%result;
}

sub _get_command_result {
    my ($source, $id, $value) = @_;

    my $readable_id = $config->{key_fields}->{$id}
        or return;
    # Strip all non-digits from id field's value
    $value =~ s/\D+//g;
    return if !$value;

    my $command = $source->{command};

    # If command doesn't contain such ID, skip it
    return if $command !~ /$readable_id/;
    $command =~ s/$readable_id/$value/g;

    # NOTE: this is extremely unsafe
    my $result = `$command`;

    utf8::decode($result);
    return $result;
}

sub _get_db_result {
    my ($source, $id, $value) = @_;

    # Get readable id from config (e.g. ACCOUNT_ID)
    my $readable_id = $config->{key_fields}->{$id}
        or return;

    # Strip all non-digits from id field's value
    $value =~ s/\D+//g;
    return if !$value;

    my $sql = $source->{sql};

    # If SQL doesn't contain such ID, skip it
    return if $sql !~ /$readable_id/;

    my $dbh = $dbh_for{ $source->{database} }
        or return "No connection to database $source->{database}";

    my $quoted_value = $dbh->quote($value);
    $sql =~ s/$readable_id/$quoted_value/g;

    my @columns = $dbh->selectrow_array($sql);
    return join ', ', map { $_ || '' } @columns;
}

sub _get_text_result {
    my ($source, $id, $value) = @_;

    # Get readable id from config (e.g. ACCOUNT_ID)
    my $readable_id = $config->{key_fields}->{$id}
        or return;

    # Strip all non-digits from id field's value
    $value =~ s/\D+//g;
    return if !$value;

    my $text = $source->{Text};
    utf8::decode($text); # convert to characters
    $text =~ s/$readable_id/$value/g;
    return $text;
}

sub _get_field_id {
    my $html_id = shift;

    if ($html_id =~ /CustomField-(\d+)/) {
        #warn "html_id: $html_id, field_id: $1";
        return $1;
    }
    die "Field html id ($html_id) contains no digits";
}

1;
