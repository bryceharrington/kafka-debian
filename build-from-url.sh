SOURCE_VERSION="2.2.0"
SCALA_VERSION="2.11"
UBUNTU_REVISION="0ubuntu0"
DISTRIBUTION="bionic"
PPA_TAG="bionic"
PPA_SEQ="1"

KAFKA_DIR="kafka-${SOURCE_VERSION}"
KAFKA_BINARY_DIR="kafka_${SCALA_VERSION}-${SOURCE_VERSION}"

step=1

function die() {
    echo "Error: $1" >&2
    exit 1
}

function echo_step() {
    echo -en "\e[1m\e[92m"
    echo -n "#$((step++)): $1"
    echo -e "\e[0m" 
}

function md5sum_pprint() {
    # Reformat md5sum output to what kafka shows in their md5 files
    s=${1^^}
    filename=${2}
    first=$(  echo ${s:0:16}  | sed 's/.\{2\}/& /g' | sed -e 's/[[:space:]]*$//')
    second=$( echo ${s:16:16} | sed 's/.\{2\}/& /g' | sed -e 's/[[:space:]]*$//')
    echo "$filename: ${first}  ${second}"
}

function check_md5_sig() {
    md5_a=$(md5sum_pprint $(md5sum ${1}))
    md5_b=$(cat $2)

    if [ "${md5_a}" != "${md5_b}" ]; then
	echo "'${md5_a}' != '${md5_b}'"
	return 1
    fi

    return 0
}

function check_gpg_sig() {
    gpg --verify $2 $1
}

# Download package only if we need it
function download_kafka() {
    package=$1
    release=$2
    echo ${package} ${release}
    if [ ! -e ${package} ]; then
	# Install the signing keys
	wget -O- https://www.apache.org/dist/kafka/KEYS | gpg --import 2> /dev/null
	if [ $? -ne 0 ]; then
	    die "Could not import gpg keys from kafka"
	fi

	wget http://www.apache.org/dist/kafka/${release}/${package} || die "wget"
	wget http://www.apache.org/dist/kafka/${release}/${package}.md5 || die "wget md5"
	wget http://www.apache.org/dist/kafka/${release}/${package}.asc || die "wget asc"

	echo "Checking md5 sig"
	check_md5_sig ${package} ${package}.md5 \
	    || die "md5sum mismatch on ${package}"

	echo "Checking gpg sig"
	check_gpg_sig ${package} ${package}.asc \
	    || die "Failed gpg verification on ${package}"
    fi
}

function apt_install() {
    package=$1

    dpkg -s ${package} > /dev/null
    if [ $? -ne 0 ]; then
	sudo apt-get -y install ${package} \
	    || die "Install of ${package} failed"
    fi
    return 0
}

function apt_install_only() {
    package=$1

    dpkg -s ${package} > /dev/null
    if [ $? -ne 0 ]; then
	sudo apt-get -y --no-install-recommends --no-install-suggests install ${package} \
	    || die "Install of ${package} failed"
    fi
    return 0
}

function ppa_install() {
    ppa=$1
    package=$2

    dpkg -s ${package} > /dev/null
    if [ $? -ne 0 ]; then
	sudo add-apt-repository -yu ${ppa} \
	    || die "Could not add the ${ppa} repo"
	sudo apt-get install ${package} \
	    || die "Could not install ${package} from PPA"
    fi
    return 0
}


##########################
### Check dir is clean ###
##########################

exists=0
if [ -e "${KAFKA_DIR}" ]; then 
    echo "Existing ${KAFKA_DIR} needs moved aside or removed" >&2
    exists=1
fi
if [ -e "${KAFKA_BINARY_DIR}" ]; then 
    echo "Existing ${KAFKA_BINARY_DIR} needs moved aside or removed" >&2
    exists=1
fi

if [ ${exists} -ne 0 ]; then
    exit 1
fi


#####################
### Prerequisites ###
#####################

echo_step "Installing build prereqs"

# Prerequisite:  Java jdk/jre
apt_install openjdk-11-jdk
apt_install openjdk-11-jdk-headless
apt_install openjdk-11-jre
apt_install openjdk-11-jre-headless
apt_install openjdk-11-source

# Prerequisite:  Upgraded gradle (we need 4.7 at least, this gives latest)
ppa_install ppa:cwchien/gradle gradle

# Prerequisite:  Packaging helpers
apt_install_only dpkg-dev
apt_install_only devscripts
apt_install_only tar
apt_install_only dpkg-dev
apt_install_only debhelper
apt_install_only dh-systemd
apt_install_only gnupg2


#########################
### Download packages ###
#########################

echo_step "Downloading kafka"

# Binary installer
download_kafka "kafka_${SCALA_VERSION}-${SOURCE_VERSION}.tgz" ${SOURCE_VERSION}

# Documentation
download_kafka "kafka_${SCALA_VERSION}-${SOURCE_VERSION}-site-docs.tgz" ${SOURCE_VERSION}

# Source code
download_kafka "kafka-${SOURCE_VERSION}-src.tgz" ${SOURCE_VERSION}

# Download our own packaging to ./kafka-debian
if [ ! -d kafka-debian ]; then
    git clone https://git.launchpad.net/~bryce/+git/kafka-debian
fi


##########################
### Unpack the tarball ###
##########################

echo_step "Unpacking tarballs"

tar -xzf kafka_${SCALA_VERSION}-${SOURCE_VERSION}.tgz
if [ ! -d ${KAFKA_BINARY_DIR}/ ]; then
    die "No ${KAFKA_BINARY_DIR}"
fi

mkdir ${KAFKA_DIR}
tar -xzf kafka-${SOURCE_VERSION}-src.tgz --strip-components=1 -C ${KAFKA_DIR}
if [ ! -e ${KAFKA_DIR}/LICENSE ]; then
    die "Failure extracting to ${KAFKA_DIR}"
fi

#################################################
### Build binary release from upstream source ###
#################################################

echo_step "Building"

cd ${KAFKA_DIR}

# Source patching could be done at this point
# --> May want to set -PcommitId if this is done

gradle
./gradlew -PscalaVersion=${SCALA_VERSION} jar
./gradlew -PscalaVersion=${SCALA_VERSION} srcJar
# (Various tests could be run at this point)
./gradlew -PscalaVersion=${SCALA_VERSION} clean
./gradlew -PscalaVersion=${SCALA_VERSION} releaseTarGz

## Orig tarball
cp -v ./core/build/distributions/kafka_${SCALA_VERSION}-${SOURCE_VERSION}.tgz \
   ../kafka_${SOURCE_VERSION}.orig.tar.gz \
   || die "Dist tarball could not be copied to orig"

cd ..


#############################
### Create debian package ###
#############################

echo_step "Creating debian package"

mkdir -p ${KAFKA_DIR} || die "Could not create ${KAFKA_DIR}"
tar xzf kafka_${SOURCE_VERSION}.orig.tar.gz --strip-components=1 -C ${KAFKA_DIR} \
    || die "Could not untar orig tarball"

# Insert the debian directory
cp -ar ./kafka-debian/debian ${KAFKA_DIR}/ \
    || die "Could not add debian directory"

PACKAGE_VERSION=${SOURCE_VERSION}-${UBUNTU_REVISION}~${PPA_TAG}${PPA_SEQ}

cd ${KAFKA_DIR} \
    || die "chdir ${KAFKA_DIR}"
dch -v ${PACKAGE_VERSION} \
    --distribution ${DISTRIBUTION} \
    "Update to upstream binary release ${SCALA_VERSION}-${SOURCE_VERSION}" \
    || die "dch failed"

debuild -i -uc -us -S -sa \
    || die "debuild failed"


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
