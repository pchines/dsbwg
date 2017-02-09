use ExtUtils::MakeMaker;
WriteMakefile(
              NAME         => 'DSBGW',
              VERSION      => '0.01',
              ABSTRACT     => 'Programs for storage inventory and archives for NHGRI Data Storage and Backup Working Group',
              AUTHOR       => 'Peter Chines (pchines@mail.nih.gov)',
              EXE_FILES    => ['archive_check', 'archive_check_complete'],
              PREREQ_PM    => { 'NHGRI::Db::Connector' => 0 },
             );
