#! /usr/bin/env bash

DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

echo "Travis OS: ${TRAVIS_OS_NAME}"

TestTarantool_VER=0.033
TestTarantool_URL=https://github.com/igorcoding/Test-Tarantool16/releases/download/v${TestTarantool_VER}/Test-Tarantool16-${TestTarantool_VER}.tar.gz
TestTarantool_LOCATION=/tmp/test-tarantool16.tar.gz
wget ${TestTarantool_URL} -O ${TestTarantool_LOCATION}

if [ -z "$TRAVIS_OS_NAME" ] || [ ${TRAVIS_OS_NAME} == 'linux' ]; then
	source "${DIR}/tnt-cares.sh"
	
elif [ ${TRAVIS_OS_NAME} == 'osx' ]; then
	sudo sh -c 'echo "127.0.0.1 localhost" >> /etc/hosts'
	sudo ifconfig lo0 alias 127.0.0.2 up
	brew update
	brew install curl
	brew install https://raw.githubusercontent.com/Homebrew/homebrew-core/master/Formula/cpanminus.rb
	brew install https://raw.githubusercontent.com/Homebrew/homebrew-core/master/Formula/c-ares.rb
	cpanm --version
	
	# sudo cp $DIR/macos_ares_rules.h /usr/local/include/ares_rules.h
	
	brew update
	brew install tarantool
	tarantool -V
	mkdir -p ~/Library/perl5/
  	eval `perl -I ~/Library/perl5/lib/perl5 -Mlocal::lib=~/Library/perl5`
	
	# cat ~/.cpanm/work/**/*.log
fi


cpanm Types::Serialiser
cpanm EV

cpanm Test::More
cpanm Test::Deep
cpanm AnyEvent
cpanm Proc::ProcessTable
cpanm Time::HiRes
cpanm Scalar::Util
cpanm Data::Dumper
cpanm Carp
cpanm ${TestTarantool_LOCATION}
