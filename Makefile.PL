use inc::Module::Install;
RTx 'RTx-FillTicketData';
requires_rt('4.0.0');
all_from('lib/RTx/FillTicketData.pm');
no_index 'etc';
WriteAll();
