#!/usr/bin/env bash
DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
TNTCARES="${DIR}/tnt-cares.sh"

TestTarantool_VER=0.033
TestTarantool_URL=https://github.com/igorcoding/Test-Tarantool16/releases/download/v${TestTarantool_VER}/Test-Tarantool16-${TestTarantool_VER}.tar.gz
TestTarantool_LOCATION=/tmp/test-tarantool16.tar.gz
wget ${TestTarantool_URL} -O ${TestTarantool_LOCATION}


if [ ${TRAVIS} == true ]; then
	
else
	sudo apt-get install -y valgrind perl-doc
    curl -L https://cpanmin.us | sudo perl - App::cpanminus
    
	sudo cpanm Types::Serialiser
	sudo cpanm EV
	
	sudo cpanm Test::More
	sudo cpanm Test::Deep
	sudo cpanm AnyEvent
	sudo cpanm Proc::ProcessTable
	sudo cpanm Time::HiRes
	sudo cpanm Scalar::Util
	sudo cpanm Data::Dumper
	sudo cpanm Carp
	sudo cpanm $HOME/temp/test-tarantool16.tar.gz
	
	sudo cpanm Test::Valgrind
	sudo cpanm List::BinarySearch

	echo 'Build Perl 5.16.3...'

	mkdir -p ${HOME}/perl
	mkdir -p ${HOME}/perl-src

	cd ${HOME}/perl-src

	wget http://www.cpan.org/src/5.0/perl-5.16.3.tar.gz -O - | tar -xzvf -
	cd perl-5.16.3/
	./Configure -des -Dprefix=${HOME}/perl -Duselargefiles -Duse64bitint -DUSEMYMALLOC -DDEBUGGING -DDEBUG_LEAKING_SCALARS -DPERL_MEM_LOG -Dinc_version_list=none -Doptimize="-march=athlon64 -fomit-frame-pointer -pipe -ggdb -g3 -O2" -Dccflags="-DPIC -fPIC -O2 -march=athlon64 -fomit-frame-pointer -pipe -ggdb -g3" -D locincpth="${HOME}/perl/include /usr/local/include" -D loclibpth="${HOME}/perl/lib /usr/local/lib" -D privlib=${HOME}/perl/lib/perl5/5.16.3 -D archlib=${HOME}/perl/lib/perl5/5.16.3 -D sitelib=${HOME}/perl/lib/perl5/5.16.3 -D sitearch=${HOME}/perl/lib/perl5/5.16.3 -Uinstallhtml1dir= -Uinstallhtml3dir= -Uinstallman1dir= -Uinstallman3dir= -Uinstallsitehtml1dir= -Uinstallsitehtml3dir= -Uinstallsiteman1dir= -Uinstallsiteman3dir=
	# CLANG: # ./Configure -des -Dprefix=${HOME}/perl-llvm -Dcc=clang -Duselargefiles -Duse64bitint -DUSEMYMALLOC -DDEBUGGING -DDEBUG_LEAKING_SCALARS -DPERL_MEM_LOG -Dinc_version_list=none -Doptimize="-march=athlon64 -fomit-frame-pointer -pipe -ggdb -g3 -O2" -Dccflags="-DPIC -fPIC -O2 -march=athlon64 -fomit-frame-pointer -pipe -ggdb -g3" -D locincpth="${HOME}/perl-llvm/include /usr/local/include" -D loclibpth="${HOME}/perl-llvm/lib /usr/local/lib" -D privlib=${HOME}/perl-llvm/lib/perl5/5.16.3 -D archlib=${HOME}/perl-llvm/lib/perl5/5.16.3 -D sitelib=${HOME}/perl-llvm/lib/perl5/5.16.3 -D sitearch=${HOME}/perl-llvm/lib/perl5/5.16.3 -Uinstallhtml1dir= -Uinstallhtml3dir= -Uinstallman1dir= -Uinstallman3dir= -Uinstallsitehtml1dir= -Uinstallsitehtml3dir= -Uinstallsiteman1dir= -Uinstallsiteman3dir=

	make
	make install

	sudo ${HOME}/perl/bin/perl `which cpanm` Types::Serialiser
	sudo ${HOME}/perl/bin/perl `which cpanm` EV
	sudo ${HOME}/perl/bin/perl `which cpanm` EV::MakeMaker
	sudo ${HOME}/perl/bin/perl `which cpanm` AnyEvent
	sudo ${HOME}/perl/bin/perl `which cpanm` Test::Deep
	sudo ${HOME}/perl/bin/perl `which cpanm` Test::Valgrind
	sudo ${HOME}/perl/bin/perl `which cpanm` Devel::Leak

	mkdir -p ${HOME}/tnt
fi

# sudo service tarantool restart
tarantool --version
