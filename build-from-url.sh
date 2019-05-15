SOURCE_VERSION="2.1.1"
BINARY_VERSION="2.11"
UBUNTU_REVISION="0ubuntu1"
DISTRIBUTION="bionic"
PPA_TAG="ppa"
PPA_SEQ="1"

step=1
set -e # Exit on error

function echo_step() {
    echo -en "\e[1m\e[92m"
    echo -n "#$((step++)): $1"
    echo -e "\e[0m" 
}

# Download package only if we need it
function download_kafka() {
    package=$1
    release=$2
    echo ${package} ${release}
    if [ ! -e ${package} ]; then
	# Install the signing keys
	( cd /tmp && \
	      wget https://www.apache.org/dist/kafka/KEYS && \
	      gpg --import KEYS \
	)

	wget http://www.apache.org/dist/kafka/${release}/${package}
	wget http://www.apache.org/dist/kafka/${release}/${package}.md5
	wget http://www.apache.org/dist/kafka/${release}/${package}.sha512
	wget http://www.apache.org/dist/kafka/${release}/${package}.asc

	sha512sum ${package}
	md5sum ${package}
	gpg --verify ${package}.asc ${package}
    fi
}

#########################
### Download packages ###
#########################

echo_step "Downloading kafka"

# Binary installer
download_kafka "kafka_${BINARY_VERSION}-${SOURCE_VERSION}.tgz" ${SOURCE_VERSION}

# Documentation
download_kafka "kafka_${BINARY_VERSION}-${SOURCE_VERSION}-site-docs.tgz" ${SOURCE_VERSION}

# Source code
download_kafka "kafka-${SOURCE_VERSION}-src.tgz" ${SOURCE_VERSION}

# Download our own packaging to ./kafka-debian
if [ ! -d kafka-debian ]; then
    git clone https://bryce@git.launchpad.net/~bryce/+git/kafka-debian
fi


#####################
### Prerequisites ###
#####################

echo_step "Installing build prereqs"

# Prerequisite:  Java jdk/jre
sudo apt-get -y remove  openjdk-8-jre openjdk-8-jdk
sudo apt-get -y install openjdk-11-jdk openjdk-11-jdk-headless
sudo apt-get -y install openjdk-11-jre openjdk-11-jre-headless
sudo apt-get -y install openjdk-11-source

# Prerequisite:  Upgraded gradle (we need 4.7 at least, this gives latest)
sudo add-apt-repository -yu ppa:cwchien/gradle
sudo apt-get install gradle


##########################
### Unpack the tarball ###
##########################

echo_step "Unpacking tarballs"

tar -xzf kafka_${BINARY_VERSION}-${SOURCE_VERSION}.tgz
KAFKA_BINARY_DIR="kafka_${BINARY_VERSION}-${SOURCE_VERSION}"
if [ ! -d ${KAFKA_BINARY_DIR}/ ]; then
    echo "Error: No ${KAFKA_BINARY_DIR}"
fi

KAFKA_DIR="kafka-${SOURCE_VERSION}"
mkdir ${KAFKA_DIR}

tar -xzf kafka-${SOURCE_VERSION}-src.tgz --strip-components=1 -C ${KAFKA_DIR}
if [ ! -e ${KAFKA_DIR}/LICENSE ]; then
    echo "Error: Failure extracting to ${KAFKA_DIR}"
fi

#################################################
### Build binary release from upstream source ###
#################################################

echo_step "Building"

cd ${KAFKA_DIR}
# (Source patching could be done at this point)
gradle
./gradlew jar
./gradlew srcJar
# (Various tests could be run at this point)
./gradlew clean
./gradlew releaseTarGz

ls -l ./core/build/distributions/

## Orig tarball
cp ./core/build/distributions/kafka_2.11-2.1.1.tgz ../kafka_${SOURCE_VERSION}.orig.tar.gz
cd ..

#############################
### Create debian package ###
#############################

echo_step "Creating debian package"

# TODO: The above build commands need to go into debian/rules, until then
#       we'll just package the binary release.
#cp kafka-${SOURCE_VERSION}-src.tgz kafka_${SOURCE_VERSION}.orig.tar.gz

rm -rf /tmp/${KAFKA_DIR}/
mv ${KAFKA_DIR} /tmp/

mkdir -p ${KAFKA_DIR}
tar xzf kafka_${SOURCE_VERSION}.orig.tar.gz --strip-components=1 -C ${KAFKA_DIR}

# Insert the debian directory
cp -ar ./kafka-debian/debian ${KAFKA_DIR}/

PACKAGE_VERSION=${SOURCE_VERSION}-${UBUNTU_REVISION}~${PPA_TAG}${PPA_SEQ}

( \
  cd ${KAFKA_DIR} && \
  dch -v ${PACKAGE_VERSION} \
      --distribution ${DISTRIBUTION} \
      "Update to upstream binary release ${BINARY_VERSION}-${SOURCE_VERSION}" && \
  echo "" > debian/patches/series && \
  debuild -i -uc -us -S -sa
)


#####################
### Build package ###
#####################

echo_step "Building installation package"

# If a bionic pbuilder is missing, will need to create it first
if [ ! -d /var/cache/pbuilder/bionic-amd64 ]; then
    sudo pbuilder create bionic
fi

echo "Now run: sudo DIST=bionic pbuilder build kafka_${PACKAGE_VERSION}.dsc"
echo
echo "If satisfied, upload this to ppa via:"
echo
echo "  debsign kafka_${PACKAGE_VERSION}_source.changes"
echo "  dput ppa:bryce/kafka-experimental kafka_${PACKAGE_VERSION}_source.changes"

