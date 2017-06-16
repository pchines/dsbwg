use ExtUtils::MakeMaker;
WriteMakefile(
              NAME         => 'DSBWG',
              VERSION      => '0.01',
              ABSTRACT     => 'Programs for storage inventory and archives for NHGRI Data Storage and Backup Working Group',
              AUTHOR       => 'Peter Chines (pchines@mail.nih.gov)',
              EXE_FILES    => [qw(
                  archive_check archive_check_complete archive_set_size
                  archive_get_sizes
                  isilon_summarize_report
                  )],
              PREREQ_PM    => {
                'DBD::mysql' => 0,
                'MIME::Lite' => 0,
                'NHGRI::Db::Connector' => 0,
                },
             );
